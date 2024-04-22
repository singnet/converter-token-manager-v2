// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Commission is Ownable {

    uint256 private constant ONE_HUNDRED = 100;
    uint256 private immutable FIXED_NATIVE_TOKEN_COMMISSION_LIMIT;
    
    enum CommissionType {
        Disable, // disable
        NativeCurrency, // commission in native currency
        PercentageTokens, // commission in percentage tokens
        FixTokens // commission in fix value of tokens
    }
    CommissionType public commissionType;

    CommissionSettings public commissionSettings;
    struct CommissionSettings {
        uint8 convertTokenPercentage; // percentage for commission in tokens
        bool commissionIsEnabled; // activate/deactivate commission
        bool typeCommission; // false - commission in ETH, true - commission in tokens
        bool typeTokenCommission; // type of commission in tokens: false - fix, true -  percentage
        uint256 fixedNativeTokenCommission; // fixed value of commission in native tokens
        uint256 fixedTokenCommission; // fixed value of commission in tokens
        address payable commissionReceiver; // commission receiver
        CommissionType commissionType; // global type of commission
    }
    
    // Address of token contract for  
    address internal _token;

    bytes4 private constant TRANSFERFROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant MINT_SELECTOR = bytes4(keccak256("mint(address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCurrencyCommissionClaim(uint256 claimedBalance, uint256 time);
    event UpdateCommissionConfiguration(
        uint256 updateTimestamp,
        bool commissionIsEnabled,
        bool typeCommission,
        bool typeTokenCommission,
        uint8 convertTokenPercentage,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission,
        address newCommissionReceiver
    );
    event UpdateTypeCommission(
        uint256 updateTimestamp,
        bool typeCommission,
        bool typeTokenCommission,
        uint8 convertTokenPercentage,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission   
    );
    event UpdateFixedNativeTokenCommission(uint256 updateTime, uint256 newFixedNativeTokenCommission);
    event UpdatePercentageTokensCommission(uint256 updateTime, uint8 newPercentage);
    event UpdateFixedTokenCommission(uint256 updateTime, uint256 newFixedTokenCommisssion);
    event UpdateTokenTypeCommission(uint256 updateTime, bool newTypeTokenCommission);

    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= 100, "Violates percentage limits");
        _;
    }

    constructor(
        bool commissionIsEnabled,
        bool typeCommission,
        uint256 fixedNativeTokenCommission,
        uint256 fixedNativeTokenCommissionLimit,
        bool typeTokenCommission,
        uint256 fixedTokenCommission,
        uint8 convertTokenPercentage,
        address commissionReceiver
    )
        Ownable()
        checkPercentageLimit(convertTokenPercentage)
    {
        commissionSettings.commissionReceiver = payable(commissionReceiver);
        FIXED_NATIVE_TOKEN_COMMISSION_LIMIT = fixedNativeTokenCommissionLimit;

        if (!commissionIsEnabled) return;

        commissionSettings.commissionIsEnabled = true;

        if (typeCommission) {
            commissionSettings.typeCommission = true;
            if (typeTokenCommission && convertTokenPercentage > 0) {
                commissionSettings.typeTokenCommission = true;
                commissionSettings.convertTokenPercentage = convertTokenPercentage;
                commissionSettings.commissionType = CommissionType.PercentageTokens;
            } else {
                commissionSettings.fixedTokenCommission = fixedTokenCommission;
                commissionSettings.commissionType = CommissionType.FixTokens;
            }
        } else if (fixedNativeTokenCommission > 0) {
            _checkFixedNativeTokenLimit(fixedNativeTokenCommission);
            commissionSettings.fixedNativeTokenCommission = fixedNativeTokenCommission;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        emit UpdateCommissionConfiguration(
            block.timestamp,
            commissionIsEnabled,
            typeCommission,
            typeTokenCommission,
            convertTokenPercentage,
            fixedTokenCommission,
            fixedNativeTokenCommission,
            commissionReceiver
        );
    }

    function _checkPayedCommissionInNative() internal {
        require(
            msg.value == commissionSettings.fixedNativeTokenCommission,
            "Inaccurate payed commission in native token"
        );
    }

    function _takeCommissionInTokenOutput(uint256 amount) internal returns (uint256) {
        uint256 commissionAmount = _calculateCommissionInToken(amount);

        if (commissionAmount > 0) {
            (bool success, ) = _token.call(
                abi.encodeWithSelector(
                    TRANSFERFROM_SELECTOR,
                    _msgSender(),
                    commissionSettings.commissionReceiver,
                    commissionAmount
                )
            );

            require(success, "Commission transfer failed");
        }
        return commissionAmount;
    }

    function _takeCommissionInTokenInput(uint256 amount) internal returns (uint256) {
        uint256 commissionAmount = _calculateCommissionInToken(amount);

        // transfer minted commission to receiver
        if (commissionAmount > 0) {
            (bool success, ) = _token.call(
                abi.encodeWithSelector(
                    TRANSFER_SELECTOR,
                    commissionSettings.commissionReceiver,
                    commissionAmount
                )
            );

            require(success, "Commission transfer failed");
        }
        return commissionAmount;
    }

    function _calculateCommissionInToken(uint256 amount) internal view returns (uint256) {
        if (commissionSettings.commissionType == CommissionType.PercentageTokens) {
            return amount * uint256(commissionSettings.convertTokenPercentage) / ONE_HUNDRED;
        } 
        // If commissionType is not PercentageTokens, it's either FixTokens or Disable
        return commissionSettings.fixedTokenCommission;
    }

    function disableCommission() external onlyOwner {
        delete commissionSettings;
    }

    function updateCommissionConfiguration(
        bool commissionIsEnabled,
        bool newTypeCommission,
        bool newTypeTokenCommission,
        uint8 newConvertTokenPercentage,
        uint256 newFixedTokenCommission,
        uint256 newFixedNativeTokenCommission
    )
        external onlyOwner
        checkPercentageLimit(newConvertTokenPercentage)
    {
        if (!commissionIsEnabled) return;

        commissionSettings.commissionIsEnabled = true;

        if (newTypeCommission) {
            commissionSettings.typeCommission = true;
            if (newTypeTokenCommission && newConvertTokenPercentage > 0) {
                commissionSettings.typeTokenCommission = true;
                commissionSettings.convertTokenPercentage = newConvertTokenPercentage;
                commissionSettings.commissionType = CommissionType.PercentageTokens;
            } else {
                commissionSettings.fixedTokenCommission = newFixedTokenCommission;
                commissionSettings.commissionType = CommissionType.FixTokens;
            }
        } else if (newFixedNativeTokenCommission > 0) {
            _checkFixedNativeTokenLimit(newFixedNativeTokenCommission);
            commissionSettings.fixedNativeTokenCommission = newFixedNativeTokenCommission;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        emit UpdateCommissionConfiguration(
            block.timestamp,
            commissionIsEnabled,
            newTypeCommission,
            newTypeTokenCommission,
            newConvertTokenPercentage,
            newFixedTokenCommission,
            newFixedNativeTokenCommission,
            commissionSettings.commissionReceiver
        );
    }

    function updateTypeCommission(
        bool newTypeCommission,
        bool newTypeTokenCommission,
        uint8 newConvertTokenPercentage,
        uint256 newFixedTokenCommission,
        uint256 newFixedNativeTokenCommission
    ) 
        external onlyOwner
        checkPercentageLimit(newConvertTokenPercentage)
    {
        require(commissionSettings.commissionIsEnabled);
        delete commissionSettings.commissionType;

        if (newTypeCommission) {
            commissionSettings.typeCommission = true;
            if (newTypeTokenCommission && newConvertTokenPercentage > 0) {
                commissionSettings.typeTokenCommission = true;
                commissionSettings.convertTokenPercentage = newConvertTokenPercentage;
                commissionSettings.commissionType = CommissionType.PercentageTokens;
            } else {
                commissionSettings.fixedTokenCommission = newFixedTokenCommission;
                commissionSettings.commissionType = CommissionType.FixTokens;
            }
        } else if (newFixedNativeTokenCommission > 0) {
            _checkFixedNativeTokenLimit(newFixedNativeTokenCommission);
            commissionSettings.fixedNativeTokenCommission = newFixedNativeTokenCommission;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        emit UpdateTypeCommission(
            block.timestamp,
            newTypeCommission,
            newTypeTokenCommission,
            newConvertTokenPercentage,
            newFixedTokenCommission,
            newFixedNativeTokenCommission
        );
    }

    function updateFixedNativeTokenCommission(uint256 newFixedNativeTokenCommission)
        external
        onlyOwner
    {
        require(
            commissionSettings.commissionIsEnabled && !commissionSettings.typeCommission,
            "At the current moment commission disabled or active a different commission type"
        );

        require(newFixedNativeTokenCommission > 0, "Zero value of new commission in native token");
        _checkFixedNativeTokenLimit(newFixedNativeTokenCommission);

        commissionSettings.fixedNativeTokenCommission = newFixedNativeTokenCommission;
      
        emit UpdateFixedNativeTokenCommission(block.timestamp, newFixedNativeTokenCommission);
    }

    function updateTokenTypeCommission(
        bool newTokenTypeCommission, 
        uint8 newPercentage, 
        uint256 newFixedTokenCommisssion
    )
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
    {

        require(
            commissionSettings.commissionIsEnabled &&
            commissionSettings.typeCommission &&
            newTokenTypeCommission != commissionSettings.typeTokenCommission,
            "Update type token commission unavailable"
        );

        emit UpdateTokenTypeCommission(block.timestamp, newTokenTypeCommission);

        if (newTokenTypeCommission) {
            commissionSettings.convertTokenPercentage = newPercentage;
            emit UpdatePercentageTokensCommission(block.timestamp, newPercentage);
        }
        require(
            newFixedTokenCommisssion > 0,
            "The fixed value of the commission in tokens cannot be equal to zero"
        );
        commissionSettings.fixedTokenCommission = newFixedTokenCommisssion;
        emit UpdateFixedTokenCommission(block.timestamp, newFixedTokenCommisssion);
    }

    function updatePercentageTokensCommission(uint8 newPercentage)
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
    {
        require(
            commissionSettings.commissionIsEnabled && commissionSettings.typeCommission && commissionSettings.typeTokenCommission,
            "At the current moment commission disabled or active a different commission type"
        );

        if (newPercentage > 0) commissionSettings.convertTokenPercentage = newPercentage;

        emit UpdatePercentageTokensCommission(block.timestamp, newPercentage);
    }

    function updateFixedTokensCommission(uint256 newFixedTokenCommisssion)
        external
        onlyOwner
    {
        require(
            commissionSettings.commissionIsEnabled && commissionSettings.typeCommission && commissionSettings.typeTokenCommission,
            "At the current moment commission disabled or active a different commission type"
        );

        if (newFixedTokenCommisssion > 0) commissionSettings.fixedTokenCommission = newFixedTokenCommisssion;

        emit UpdateFixedTokenCommission(block.timestamp, newFixedTokenCommisssion);
    }

    function setCommissionReceiver(address newCommissionReceiver) external onlyOwner {
        require(newCommissionReceiver != address(0));
    
        emit UpdateReceiver(commissionSettings.commissionReceiver, newCommissionReceiver);

        commissionSettings.commissionReceiver = payable(newCommissionReceiver);
    }

    function claimNativeCurrencyCommission() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0);

        (bool success,) = (commissionSettings.commissionReceiver).call{value: contractBalance}("");
        require(success, "Commission claim failed");
        
        emit NativeCurrencyCommissionClaim(contractBalance, block.timestamp);
    }

    function _checkFixedNativeTokenLimit(uint256 fixedNativeTokenCommission) private view {
        require(
            fixedNativeTokenCommission <= FIXED_NATIVE_TOKEN_COMMISSION_LIMIT, 
            "Violates native token commission limit"
        );
    }

    function getCommissionReceiverAddress() external view returns(address) {
        return commissionSettings.commissionReceiver;
    }

    function getCommissionSettings() public view returns (
        bool commissionIsEnabled,
        bool typeCommission,
        uint8 convertTokenPercentage,
        bool typeTokenCommisssion,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission,
        address payable commissionReceiver,
        address token
    ) {
        return (
            commissionSettings.commissionIsEnabled,
            commissionSettings.typeCommission,
            commissionSettings.convertTokenPercentage,
            commissionSettings.typeTokenCommission,
            commissionSettings.fixedTokenCommission,
            commissionSettings.fixedNativeTokenCommission,
            commissionSettings.commissionReceiver,
            _token
        );
    }
}
