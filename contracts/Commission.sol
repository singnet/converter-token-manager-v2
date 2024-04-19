// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Commission is Ownable {

    uint256 private constant ONE_HUNDRED = 100;
    
    enum CommissionType {
        Disable, // disable
        NativeCurrency, // commission in native currency
        PercentageTokens, // commission in percentage tokens
        FixTokens // commission in fix value of tokens
    }
    CommissionType public commissionType;

    CommissionSettings public commissionSettings;
    struct CommissionSettings {
        bool enableCommission; // activate/deactivate commission
        bool typeCommission; // false - commission in ETH, true - commission in tokens
        uint8 nativeCurrencyPercentage; // percentage for commission in native currency
        uint8 convertTokenPercentage; // percentage for commission in tokens
        uint32 pointOffset; // point offset indicator for percentage in native currency
        bool typeTokenCommission; // type of commission in tokens: false - fix, true -  percentage
        uint256 fixValueTokenCommission; // fix value of commission in tokens
        address payable commissionReceiver; // commission receiver
        CommissionType commissionType; // global type of commission
    }
    
    // Address of token contract for  
    address internal _token;

    /**
     * pointOffset:
     *
     * 100 - 1% of 1 ETH = 0.01 ETH
     * 10000 - 0.01% of 1 ETH = 0.0001 ETH
     * 1000000 - 0.0001% of 1 ETH = 0.000001 ETH
     * 
     * formula:
     * 1 ETH * nativeTokenPercentage / pointOffset
     * 
     */

    bytes4 private constant TRANSFERFROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant MINT_SELECTOR = bytes4(keccak256("mint(address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    event UpdateCommission(bool indexed nativeToken, uint8 newCommissionPercentage);
    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCurrencyCommissionClaim(uint256 claimedBalance, uint256 time);
    event ChangeComissionType(bool indexed status, uint256 time);
    event UpdatePointIndicator(uint32 newIndicator, uint256 time);

    event UpdateCommissionConfiguration(
        uint256 updateTimestamp,
        bool enableCommission,
        bool TypeCommission,
        bool TypeTokenCommission,
        uint256 FixValueTokenCommission,
        uint32 PointOffset,
        uint8 NativeCurrencyPercentage,
        uint8 ConvertTokenPercentage,
        address newCommissionReceiver
    );

    event UpdateTypeCommission(
        uint256 updateTimestamp,
        bool TypeCommission,
        bool TypeTokenCommission,
        uint256 FixValueTokenCommission,
        uint32 PointOffset,
        uint8 NativeCurrencyPercentage,
        uint8 ConvertTokenPercentage
    );
    event UpdatePercentageNativeCurrencyCommission(uint256 updateTime, uint8 newPercentage, uint32 newOffset);
    
    event UpdatePercentageTokensCommission(uint256 updateTime, uint8 newPercentage);
    event UpdateFixTokensCommission(uint256 updateTime, uint256 newFixTokensValueCommisssion);

    event UpdateTokenTypeCommission(uint256 updateTime, bool newTypeTokenCommission);


    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= 100, "Violates percentage limits");
        _;
    }

    modifier checkOffsetValue(uint32 newOffsetValue) {
        require(
            newOffsetValue == 100 || newOffsetValue == 10000 || newOffsetValue == 1000000,
            "The offset indicator has an invalid value"
        );
        require(
            commissionSettings.pointOffset != newOffsetValue,
            "New offset indicator must be different from current value"
        );
        _;
    }

    constructor(
        bool enableCommission,
        bool typeCommission,
        uint8 nativeCurrencyPercentage,
        uint32 pointOffset,
        bool typeTokenCommission,
        uint256 fixValueTokenCommission,
        uint8 convertTokenPercentage,
        address commissionReceiver
    )
        Ownable()
        checkPercentageLimit(nativeCurrencyPercentage)
        checkPercentageLimit(convertTokenPercentage)
        checkOffsetValue(pointOffset)
    {
        commissionSettings.commissionReceiver = payable(commissionReceiver);

        if (!enableCommission) return;

        commissionSettings.enableCommission = true;

        if (typeCommission) {
            commissionSettings.typeCommission = true;
            if (typeTokenCommission && convertTokenPercentage > 0) {
                commissionSettings.typeTokenCommission = true;
                commissionSettings.convertTokenPercentage = convertTokenPercentage;
                commissionSettings.commissionType = CommissionType.PercentageTokens;
            } else {
                commissionSettings.fixValueTokenCommission = fixValueTokenCommission;
                commissionSettings.commissionType = CommissionType.FixTokens;
            }
        } else if (nativeCurrencyPercentage > 0) {
            commissionSettings.nativeCurrencyPercentage = nativeCurrencyPercentage;
            commissionSettings.pointOffset = pointOffset;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        emit UpdateCommissionConfiguration(
            block.timestamp,
            enableCommission,
            typeCommission,
            typeTokenCommission,
            fixValueTokenCommission,
            pointOffset,
            nativeCurrencyPercentage,
            convertTokenPercentage,
            commissionReceiver
        );
    }

    function _checkPayedCommissionInNative() internal {
        if (commissionSettings.commissionType == CommissionType.NativeCurrency) {
            require(
                msg.value == 1 ether * uint256(commissionSettings.nativeCurrencyPercentage) / commissionSettings.pointOffset,
                "Inaccurate payed commission in native token"
            );
        }
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
        return (commissionSettings.commissionType == CommissionType.FixTokens) ? commissionSettings.fixValueTokenCommission : 0;
    }

    function disableCommission() external onlyOwner {
        commissionSettings.typeCommission = false;
        commissionSettings.typeTokenCommission = false;
        commissionSettings.fixValueTokenCommission = 0;
        commissionSettings.pointOffset = 0;
        commissionSettings.nativeCurrencyPercentage = 0;
        commissionSettings.convertTokenPercentage = 0;
        delete commissionSettings.commissionReceiver;

        commissionSettings.enableCommission = false;
        delete commissionSettings.commissionType;
    }

    function updateCommissionConfiguration(
        bool enableCommission,
        bool newTypeCommission,
        bool newTypeTokenCommission,
        uint256 newFixValueTokenCommission,
        uint32 newPointOffset,
        uint8 newNativeCurrencyPercentage,
        uint8 newConvertTokenPercentage
    )
        external onlyOwner
        checkPercentageLimit(newNativeCurrencyPercentage)
        checkPercentageLimit(newConvertTokenPercentage)
        checkOffsetValue(newPointOffset)
    {
        if (!enableCommission) return;

        commissionSettings.enableCommission = true;

        if (newTypeCommission) {
            commissionSettings.typeCommission = true;
            if (newTypeTokenCommission && newConvertTokenPercentage > 0) {
                commissionSettings.typeTokenCommission = true;
                commissionSettings.convertTokenPercentage = newConvertTokenPercentage;
                commissionSettings.commissionType = CommissionType.PercentageTokens;
            } else {
                commissionSettings.fixValueTokenCommission = newFixValueTokenCommission;
                commissionSettings.commissionType = CommissionType.FixTokens;
            }
        } else if (newNativeCurrencyPercentage > 0) {
            commissionSettings.nativeCurrencyPercentage = newConvertTokenPercentage;
            commissionSettings.pointOffset = newPointOffset;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        emit UpdateCommissionConfiguration(
            block.timestamp,
            enableCommission,
            newTypeCommission,
            newTypeTokenCommission,
            newFixValueTokenCommission,
            newPointOffset,
            newNativeCurrencyPercentage,
            newConvertTokenPercentage,
            commissionSettings.commissionReceiver
        );
    }

    function updateTypeCommission(
        bool newTypeCommission,
        bool newTypeTokenCommission,
        uint256 newFixValueTokenCommission,
        uint32 newPointOffset,
        uint8 newNativeCurrencyPercentage,
        uint8 newConvertTokenPercentage
    ) 
        external onlyOwner
        checkPercentageLimit(newNativeCurrencyPercentage)
        checkPercentageLimit(newConvertTokenPercentage)
        checkOffsetValue(newPointOffset)
    {
        require(commissionSettings.enableCommission);
        delete commissionSettings.commissionType;

        if (newTypeCommission) {
            commissionSettings.typeCommission = true;
            if (newTypeTokenCommission && newConvertTokenPercentage > 0) {
                commissionSettings.typeTokenCommission = true;
                commissionSettings.convertTokenPercentage = newConvertTokenPercentage;
                commissionSettings.commissionType = CommissionType.PercentageTokens;
            } else {
                commissionSettings.fixValueTokenCommission = newFixValueTokenCommission;
                commissionSettings.commissionType = CommissionType.FixTokens;
            }
        } else if (newNativeCurrencyPercentage > 0) {
            commissionSettings.nativeCurrencyPercentage = newConvertTokenPercentage;
            commissionSettings.pointOffset = newPointOffset;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        emit UpdateTypeCommission(
            block.timestamp,
            newTypeCommission,
            newTypeTokenCommission,
            newFixValueTokenCommission,
            newPointOffset,
            newNativeCurrencyPercentage,
            newConvertTokenPercentage
        );
    }

    function updatePercentageNativeCurrencyCommission(uint8 newPercentage, uint32 newOffset)
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
        checkOffsetValue(newOffset)
    {
        require(
            commissionSettings.enableCommission && !commissionSettings.typeCommission,
            "At the current moment commission disabled or active a different commission type"
        );
        require(newPercentage > 0, "Invalid percentage for this type commission");
        commissionSettings.nativeCurrencyPercentage = newPercentage;
        commissionSettings.pointOffset = newOffset;

        emit UpdatePercentageNativeCurrencyCommission(block.timestamp, newPercentage, newOffset);
    }

    function updateTokenTypeCommission(bool newTokenTypeCommission, uint8 newPercentage, uint256 newFixTokensValueCommisssion)
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
    {

        require(
            commissionSettings.enableCommission &&
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
            newFixTokensValueCommisssion > 0,
            "The fixed value of the commission in tokens cannot be equal to zero"
        );
        commissionSettings.fixValueTokenCommission = newFixTokensValueCommisssion;
        emit UpdateFixTokensCommission(block.timestamp, newFixTokensValueCommisssion);
    }


    function updatePercentageTokensCommission(uint8 newPercentage)
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
    {
        require(
            commissionSettings.enableCommission && commissionSettings.typeCommission && commissionSettings.typeTokenCommission,
            "At the current moment commission disabled or active a different commission type"
        );

        if (newPercentage > 0) commissionSettings.convertTokenPercentage = newPercentage;

        emit UpdatePercentageTokensCommission(block.timestamp, newPercentage);
    }

    function updateFixTokensCommission(uint256 newFixTokensValueCommisssion)
        external
        onlyOwner
    {
        require(
            commissionSettings.enableCommission && commissionSettings.typeCommission && commissionSettings.typeTokenCommission,
            "At the current moment commission disabled or active a different commission type"
        );

        if (newFixTokensValueCommisssion > 0) commissionSettings.fixValueTokenCommission = newFixTokensValueCommisssion;

        emit UpdateFixTokensCommission(block.timestamp, newFixTokensValueCommisssion);
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

    function getCommissionReceiverAddress() external view returns(address) {
        return commissionSettings.commissionReceiver;
    }

    function getCommissionSettings() public view returns (
        bool enableCommission,
        bool typeCommission,
        uint8 nativeCurrencyPercentage,
        uint8 convertTokenPercentage,
        uint32 pointOffset,
        bool typeTokenCommisssion,
        uint256 fixValueTokenCommission,
        address payable commissionReceiver,
        address token
    ) {
        return (
            commissionSettings.enableCommission,
            commissionSettings.typeCommission,
            commissionSettings.nativeCurrencyPercentage,
            commissionSettings.convertTokenPercentage,
            commissionSettings.pointOffset,
            commissionSettings.typeTokenCommission,
            commissionSettings.fixValueTokenCommission,
            commissionSettings.commissionReceiver,
            _token
        );
    }
}
