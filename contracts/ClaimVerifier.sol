pragma solidity ^0.5.0;

import "./Commons.sol";
import "./IdentityContract.sol";
import "./IdentityContractLib.sol";
import "./ClaimCommons.sol";
import "./../dependencies/jsmnSol/contracts/JsmnSolLib.sol";
import "./../dependencies/dapp-bin/library/stringUtils.sol";
import "./../node_modules/openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

library ClaimVerifier {
    // Constants ERC-735
    uint256 constant public ECDSA_SCHEME = 1;
    
    /**
     * Iff _requiredValidAt is not zero, only claims that are not expired at that time and are already valid at that time are considered. If it is set to zero, no expiration or starting date check is performed.
     */
    function verifyClaim(IdentityContract marketAuthority, address _subject, uint256 _claimId, uint64 _requiredValidAt, bool allowFutureValidity) public view returns(bool __valid) {
        (uint256 topic, uint256 scheme, address issuer, bytes memory signature, bytes memory data, ) = IdentityContract(_subject).getClaim(_claimId);
        ClaimCommons.ClaimType claimType = ClaimCommons.topic2ClaimType(topic);
        
        if(_requiredValidAt != 0) {
            uint64 currentTime = Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), _requiredValidAt);
            if(getExpiryDate(data) < currentTime || ((!allowFutureValidity) && getStartDate(data) > currentTime))
                return false;
        }
        
        if(claimType == ClaimCommons.ClaimType.IsBalanceAuthority || claimType == ClaimCommons.ClaimType.IsMeteringAuthority || claimType == ClaimCommons.ClaimType.IsPhysicalAssetAuthority || claimType == ClaimCommons.ClaimType.IdentityContractFactoryClaim || claimType == ClaimCommons.ClaimType.EnergyTokenContractClaim || claimType == ClaimCommons.ClaimType.MarketRulesClaim) {
            return verifySignature(_subject, topic, scheme, issuer, signature, data);
        }
        
        if(claimType == ClaimCommons.ClaimType.MeteringClaim || claimType == ClaimCommons.ClaimType.BalanceClaim || claimType == ClaimCommons.ClaimType.ExistenceClaim || claimType == ClaimCommons.ClaimType.MaxPowerGenerationClaim || claimType == ClaimCommons.ClaimType.GenerationTypeClaim || claimType == ClaimCommons.ClaimType.LocationClaim || claimType == ClaimCommons.ClaimType.AcceptedDistributorClaim) {
            return verifySignature(_subject, topic, scheme, issuer, signature, data) && (getClaimOfType(marketAuthority, address(uint160(issuer)), ClaimCommons.getHigherLevelClaim(claimType), _requiredValidAt) != 0);
        }
        
        require(false, "Claim verification failed because the claim type was not recognized.");
    }
    
    function verifyClaim(IdentityContract marketAuthority, address _subject, uint256 _claimId) public view returns(bool __valid) {
        return verifyClaim(marketAuthority, _subject, _claimId, uint64(now), false);
    }
    
    /**
     * This method does not verify that the given claim exists in the contract. It merely checks whether it is a valid claim.
     * 
     * Use this method before adding claims to make sure that only valid claims are added.
     */
    function validateClaim(IdentityContract marketAuthority, ClaimCommons.ClaimType _claimType, address _subject, uint256 _topic, uint256 _scheme, address _issuer, bytes memory _signature, bytes memory _data) public view returns(bool) {
        if(ClaimCommons.claimType2Topic(_claimType) != _topic)
            return false;
       
        if(_claimType == ClaimCommons.ClaimType.IsBalanceAuthority || _claimType == ClaimCommons.ClaimType.IsMeteringAuthority || _claimType == ClaimCommons.ClaimType.IsPhysicalAssetAuthority || _claimType == ClaimCommons.ClaimType.IdentityContractFactoryClaim || _claimType == ClaimCommons.ClaimType.EnergyTokenContractClaim || _claimType == ClaimCommons.ClaimType.MarketRulesClaim) {
            if(_issuer != address(marketAuthority))
                return false;
            
            bool correct = verifySignature(_subject, _topic, _scheme, _issuer, _signature, _data);
            return correct;
        }
        
        if(_claimType == ClaimCommons.ClaimType.MeteringClaim || _claimType == ClaimCommons.ClaimType.BalanceClaim || _claimType == ClaimCommons.ClaimType.ExistenceClaim || _claimType == ClaimCommons.ClaimType.MaxPowerGenerationClaim || _claimType == ClaimCommons.ClaimType.GenerationTypeClaim || _claimType == ClaimCommons.ClaimType.LocationClaim || _claimType == ClaimCommons.ClaimType.AcceptedDistributorClaim) {
            bool correctAccordingToSecondLevelAuthority = verifySignature(_subject, _topic, _scheme, _issuer, _signature, _data);
            return correctAccordingToSecondLevelAuthority && (getClaimOfType(marketAuthority, address(uint160(_issuer)), ClaimCommons.getHigherLevelClaim(_claimType)) != 0);
        }
        
        require(false, "Claim validation failed because the claim type was not recognized.");
    }
    
    /**
     * Returns the claim ID of a claim of the stated type. Only valid claims are considered.
     * 
     * Iff _requiredValidAt is not zero, only claims that are not expired at that time and are already valid at that time are considered. If it is set to zero, no expiration or startig date check is performed.
     */
    function getClaimOfType(IdentityContract marketAuthority, address _subject, ClaimCommons.ClaimType _claimType, uint64 _requiredValidAt) public view returns (uint256 __claimId) {
        uint256 topic = ClaimCommons.claimType2Topic(_claimType);
        uint256[] memory claimIds = IdentityContract(_subject).getClaimIdsByTopic(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, , , , ,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
            
            if(!verifyClaim(marketAuthority, _subject, claimIds[i], _requiredValidAt, false))
                continue;
            
            return claimIds[i];
        }
        
        return 0;
    }
    
    function getClaimOfType(IdentityContract marketAuthority, address _subject, ClaimCommons.ClaimType _claimType) public view returns (uint256 __claimId) {
        return getClaimOfType(marketAuthority, _subject, _claimType, Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), now));
    }
    
    function getClaimOfTypeByIssuer(IdentityContract marketAuthority, address _subject, ClaimCommons.ClaimType _claimType, address _issuer, uint64 _requiredValidAt) public view returns (uint256 __claimId) {
        uint256 topic = ClaimCommons.claimType2Topic(_claimType);
        uint256 claimId = IdentityContractLib.getClaimId(_issuer, topic);

        (uint256 cTopic, , , , ,) = IdentityContract(_subject).getClaim(claimId);
        
        if(cTopic != topic)
            return 0;
        
        if(!verifyClaim(marketAuthority, _subject, claimId, _requiredValidAt, false))
            return 0;
        
        return claimId;
    }
    
    function getClaimOfTypeByIssuer(IdentityContract marketAuthority, address _subject, ClaimCommons.ClaimType _claimType, address _issuer) public view returns (uint256 __claimId) {
        return getClaimOfTypeByIssuer(marketAuthority, _subject, _claimType, _issuer, Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), now));
    }
    
    function getClaimOfTypeWithMatchingField(IdentityContract marketAuthority, address _subject, ClaimCommons.ClaimType _claimType, string memory _fieldName, string memory _fieldContent, uint64 _requiredValidAt) public view returns (uint256 __claimId) {
        uint256 topic = ClaimCommons.claimType2Topic(_claimType);
        uint256[] memory claimIds = IdentityContract(_subject).getClaimIdsByTopic(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, , , , bytes memory cData,) = IdentityContract(_subject).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
            
            if((_requiredValidAt > 0) && getExpiryDate(cData) < Commons.getBalancePeriod(marketAuthority.balancePeriodLength(), _requiredValidAt))
                continue;
            
            if(!verifyClaim(marketAuthority, _subject, claimIds[i]))
                continue;
            
            // Separate function call to avoid stack too deep error.
            if(doesMatchingFieldExist(_fieldName, _fieldContent, cData)) {
                return claimIds[i];
            }
        }
        
        return 0;
    }
    
    function doesMatchingFieldExist(string memory _fieldName, string memory _fieldContent, bytes memory _data) internal pure returns(bool) {
        string memory json = string(_data);
        (uint exitCode, JsmnSolLib.Token[] memory tokens, uint numberOfTokensFound) = JsmnSolLib.parse(json, 20);
        require(exitCode == 0, "Error in doesMatchingFieldExist. Exit code is not 0.");
        
        for(uint i = 1; i < numberOfTokensFound; i += 2) {
            JsmnSolLib.Token memory keyToken = tokens[i];
            JsmnSolLib.Token memory valueToken = tokens[i+1];

            if(StringUtils.equal(JsmnSolLib.getBytes(json, keyToken.start, keyToken.end), _fieldName) && StringUtils.equal(JsmnSolLib.getBytes(json, valueToken.start, valueToken.end), _fieldContent)) {
                return true;
            }
        }
        return false;
    }
    
    function getUint64Field(string memory _fieldName, bytes memory _data) public pure returns(uint64) {
        int fieldAsInt = JsmnSolLib.parseInt(getStringField(_fieldName, _data));
        require(fieldAsInt >= 0, "fieldAsInt must be greater than or equal to 0.");
        require(fieldAsInt < 0x10000000000000000, "fieldAsInt must be less than 0x10000000000000000.");
        return uint64(fieldAsInt);
    }
    
    function getUint256Field(string memory _fieldName, bytes memory _data) public pure returns(uint256) {
        int fieldAsInt = JsmnSolLib.parseInt(getStringField(_fieldName, _data));
        require(fieldAsInt >= 0, "fieldAsInt must be greater than or equal to 0.");
        return uint256(fieldAsInt);
    }
    
    function getStringField(string memory _fieldName, bytes memory _data) public pure returns(string memory) {
        string memory json = string(_data);
        (uint exitCode, JsmnSolLib.Token[] memory tokens, uint numberOfTokensFound) = JsmnSolLib.parse(json, 20);

        require(exitCode == 0, "Error in getStringField. Exit code is not 0.");
        for(uint i = 1; i < numberOfTokensFound; i += 2) {
            JsmnSolLib.Token memory keyToken = tokens[i];
            JsmnSolLib.Token memory valueToken = tokens[i+1];
            
            if(StringUtils.equal(JsmnSolLib.getBytes(json, keyToken.start, keyToken.end), _fieldName)) {
                return JsmnSolLib.getBytes(json, valueToken.start, valueToken.end);
            }
        }
        
        require(false, "_fieldName not found.");
    }
    
    function getExpiryDate(bytes memory _data) public pure returns(uint64) {
        return getUint64Field("expiryDate", _data);
    }
    
    function getStartDate(bytes memory _data) public pure returns(uint64) {
        return getUint64Field("startDate", _data);
    }
    
    function claimAttributes2SigningFormat(address _subject, uint256 _topic, bytes memory _data) internal pure returns (bytes32 __claimInSigningFormat) {
        return keccak256(abi.encodePacked(_subject, _topic, _data));
    }
    
    function getSignerAddress(bytes32 _claimInSigningFormat, bytes memory _signature) internal pure returns (address __signer) {
        return ECDSA.recover(_claimInSigningFormat, _signature);
    }
    
    function verifySignature(address _subject, uint256 _topic, uint256 _scheme, address _issuer, bytes memory _signature, bytes memory _data) public view returns (bool __valid) {
         // Check for currently unsupported signature.
        if(_scheme != ECDSA_SCHEME)
            return false;
        
        address signer = getSignerAddress(claimAttributes2SigningFormat(_subject, _topic, _data), _signature);
        
        if(isContract(_issuer)) {
            return signer == IdentityContract(_issuer).owner();
        } else {
            return signer == _issuer;
        }
    }
    
    // https://stackoverflow.com/a/40939341
    function isContract(address _addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(_addr) }
        return size > 0;
    }
}
