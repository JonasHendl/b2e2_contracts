pragma solidity ^0.5.0;

import "./Commons.sol";
import "./IdentityContract.sol";
import "./ClaimCommons.sol";
import "./../dependencies/jsmnSol/contracts/JsmnSolLib.sol";
import "./../dependencies/dapp-bin/library/stringUtils.sol";

contract ClaimVerifier is Commons, ClaimCommons {
    IdentityContract marketAuthority;
    
    constructor(IdentityContract _marketAuthority) public {
        marketAuthority = _marketAuthority;
    }

    function verifyFirstLevelClaim(address payable _subject, ClaimType _firstLevelClaim) public view returns(bool) {
        // Make sure the given claim actually is a first-level claim.
        require(_firstLevelClaim == ClaimType.IsBalanceAuthority || _firstLevelClaim == ClaimType.IsMeteringAuthority || _firstLevelClaim == ClaimType.IsPhysicalAssetAuthority || _firstLevelClaim == ClaimType.IdentityContractFactoryClaim || _firstLevelClaim == ClaimType.EnergyTokenContractClaim || _firstLevelClaim == ClaimType.MarketRulesClaim);
        
        uint256 topic = claimType2Topic(_firstLevelClaim);
        bytes32[] memory claimIds = IdentityContract(_subject).getClaimIdsByType(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            if(cIssuer != address(marketAuthority))
                continue;
            
            bool correct = marketAuthority.verifySignature(cTopic, cScheme, cIssuer, cSignature, cData);
            if(correct)
                return true;
        }
        
        return false;
    }
    
    function verifySecondLevelClaim(address payable _subject, ClaimType _secondLevelClaim) public view returns(bool) {
        // Make sure the given claim actually is a second-level claim.
        require(_secondLevelClaim == ClaimType.MeteringClaim || _secondLevelClaim == ClaimType.BalanceClaim || _secondLevelClaim == ClaimType.ExistenceClaim || _secondLevelClaim == ClaimType.GenerationTypeClaim || _secondLevelClaim == ClaimType.LocationClaim || _secondLevelClaim == ClaimType.AcceptedDistributorContractsClaim);
        uint256 topic = claimType2Topic(_secondLevelClaim);
        bytes32[] memory claimIds = IdentityContract(_subject).getClaimIdsByType(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            bool correctAccordingToSecondLevelAuthority = IdentityContract(address(uint160(cIssuer))).verifySignature(cTopic, cScheme, cIssuer, cSignature, cData);
            if(correctAccordingToSecondLevelAuthority && verifyFirstLevelClaim(address(uint160(cIssuer)), getHigherLevelClaim(_secondLevelClaim))) {
                return true;
            }
        }
        
        return false;
    }
    
    function verifyClaim(address payable _subject, ClaimType _claimType) public view returns(bool) {
        if(_claimType == ClaimType.IsBalanceAuthority || _claimType == ClaimType.IsMeteringAuthority || _claimType == ClaimType.IsPhysicalAssetAuthority || _claimType == ClaimType.IdentityContractFactoryClaim || _claimType == ClaimType.EnergyTokenContractClaim || _claimType == ClaimType.MarketRulesClaim) {
            return verifyFirstLevelClaim(_subject, _claimType);
        }
        
        if(_claimType == ClaimType.MeteringClaim || _claimType == ClaimType.BalanceClaim || _claimType == ClaimType.ExistenceClaim || _claimType == ClaimType.GenerationTypeClaim || _claimType == ClaimType.LocationClaim || _claimType == ClaimType.AcceptedDistributorContractsClaim) {
            return verifySecondLevelClaim(_subject, _claimType);
        }
        
        require(false);
    }
    
    /**
     * This method does not verify that the given claim exists in the contract. It merely checks whether it is a valid claim.
     * 
     * Use this method before adding claims to make sure that only valid claims are added.
     */
    function validateClaim(ClaimType _claimType, uint256 _topic, uint256 _scheme, address _issuer, bytes memory _signature, bytes memory _data) public view returns(bool) {
        if(claimType2Topic(_claimType) != _topic)
            return false;
        
        if(_claimType == ClaimType.IsBalanceAuthority || _claimType == ClaimType.IsMeteringAuthority || _claimType == ClaimType.IsPhysicalAssetAuthority || _claimType == ClaimType.IdentityContractFactoryClaim || _claimType == ClaimType.EnergyTokenContractClaim || _claimType == ClaimType.MarketRulesClaim) {
            bool correct = marketAuthority.verifySignature(_topic, _scheme, _issuer, _signature, _data);
            return correct;
        }
        
        if(_claimType == ClaimType.MeteringClaim || _claimType == ClaimType.BalanceClaim || _claimType == ClaimType.ExistenceClaim || _claimType == ClaimType.GenerationTypeClaim || _claimType == ClaimType.LocationClaim || _claimType == ClaimType.AcceptedDistributorContractsClaim) {
            bool correctAccordingToSecondLevelAuthority = IdentityContract(address(uint160(_issuer))).verifySignature(_topic, _scheme, _issuer, _signature, _data);
            return correctAccordingToSecondLevelAuthority && verifyFirstLevelClaim(address(uint160(_issuer)), getHigherLevelClaim(_claimType));
        }
        
        require(false);
    }
    
    /**
     * Checking a claim only makes sure that it exists. It does not verify the claim.
     * 
     * Iff requireNonExpired is set, only claims that have not yet expired are considered.
     */
    function checkHasClaimOfType(address payable _subject, ClaimType _claimType, bool requireNonExpired) public view returns (bool) {
        uint256 topic = claimType2Topic(_claimType);
        bytes32[] memory claimIds = IdentityContract(_subject).getClaimIdsByType(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            if(requireNonExpired && getExpiryDate(cData) > getBalancePeriod())
                continue;
            
            return true;
        }
        
        return false;
    }
    
    function getUint64Field(string memory fieldName, bytes memory data) public pure returns(uint64) {
        int expiryDateAsInt = JsmnSolLib.parseInt(getStringField(fieldName, data));
        require(expiryDateAsInt >= 0);
        require(expiryDateAsInt < 0x10000000000000000);
        return uint64(expiryDateAsInt);
    }
    
    function getStringField(string memory fieldName, bytes memory data) public pure returns(string memory) {
        string memory json = string(data);
        (uint exitCode, JsmnSolLib.Token[] memory tokens, uint numberOfTokensFound) = JsmnSolLib.parse(json, 5); // TODO: Check whether this works as there is a comment on SE saying it doesn't: https://ethereum.stackexchange.com/questions/2519/how-to-convert-a-bytes32-to-string#comment78462_59335
        assert(exitCode == 0);
        
        for(uint i = 1; i <= numberOfTokensFound; i += 2) { // TODO: check value of numberOfTokensFound. Maybe subtract something here.
            JsmnSolLib.Token memory keyToken = tokens[i];
            JsmnSolLib.Token memory valueToken = tokens[i+1];
            
            if(StringUtils.equal(JsmnSolLib.getBytes(json, keyToken.start, keyToken.end), fieldName)) {
                return JsmnSolLib.getBytes(json, valueToken.start, valueToken.end);
            }
        }
        
        require(false);
    }
    
    function getExpiryDate(bytes memory data) public pure returns(uint64) {
        return getUint64Field("expiryDate", data);
    }
}