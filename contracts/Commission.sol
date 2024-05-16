// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Commission module for bridge contract
/// @author SingularityNET
abstract contract Commission is Ownable {

    uint256 private constant ONE_HUNDRED = 100;
    uint256 private constant ONE_THOUSAND = 1000;
    uint256 private immutable FIXED_NATIVE_TOKEN_COMMISSION_LIMIT;
    
    enum CommissionType {
        PercentageTokens, // commission in percentage tokens
        FixTokens, // commission in fix value of tokens
        NativeCurrency // commission in native currency
    }

    CommissionSettings public commissionSettings;
    struct CommissionSettings {
        uint8 convertTokenPercentage; // percentage sum of commission in token
        uint8 receiverCommissionProportion; // proportion for commission receiver
        uint8 bridgeOwnerCommissionProportion; // proportion for bridge owner commission receiver
        bool commissionIsEnabled; // activate/deactivate commission
        uint256 fixedNativeTokenCommission; // fixed value of commission in native tokens
        uint256 fixedTokenCommission; // fixed value of commission in tokens
        CommissionType commissionType; // global type of commission
        address payable receiverCommission;
        address payable bridgeOwner;
    }
    
    // Address of token contract for  
    address internal _token;

    bytes4 private constant TRANSFERFROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant MINT_SELECTOR = bytes4(keccak256("mint(address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCurrencyCommissionClaim(uint256 indexed time);
    event UpdateCommissionConfiguration(
        bool commissionIsEnabled,
        uint8 convertTokenPercentage,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint256 commissionType,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission,
        address payable receiverCommission,
        address payable bridgeOwner,
        uint256 updateTimestamp
    );

    modifier isCommissionReceiver(address caller) {
        require(
            _msgSender() == commissionSettings.receiverCommission ||
            _msgSender() == commissionSettings.bridgeOwner,
            "Signer is not a commission receiver"
        );
        _;
    }

    // convertTokenPercentage <= 1000 in order to represent 
    // floating point fees with one decimal place
    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= ONE_THOUSAND, "Violates percentage limits");
        _;
    }

    modifier checkProportion(uint8 proportion1, uint8 proportion2) {
        require(
            proportion1 + proportion2 == uint8(100),
            "Sum of proportion isn't equal to 100"
        );
        _;
    }

    constructor(
        bool commissionIsEnabled,
        uint8 convertTokenPercentage,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint256 commissionType,
        uint256 fixedNativeTokenCommission,
        uint256 fixedNativeTokenCommissionLimit,
        uint256 fixedTokenCommission,
        address payable receiverCommission,
        address payable bridgeOwner
    )
        Ownable()
        checkPercentageLimit(convertTokenPercentage)
        checkProportion(receiverCommissionProportion, bridgeOwnerCommissionProportion) 
    {

        FIXED_NATIVE_TOKEN_COMMISSION_LIMIT = fixedNativeTokenCommissionLimit;

        if (!commissionIsEnabled) return;

        commissionSettings.commissionIsEnabled = true;
        
        _updateCommissionSettings(
            convertTokenPercentage,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            commissionType,
            fixedTokenCommission, 
            fixedNativeTokenCommission,
            receiverCommission,
            bridgeOwner
        );

        emit UpdateCommissionConfiguration(
            commissionIsEnabled,
            convertTokenPercentage,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            commissionType,
            fixedTokenCommission,
            fixedNativeTokenCommission,
            receiverCommission,
            bridgeOwner,
            block.timestamp
        );
    }

    /**
     * @notice Method to check when charging a fee in a native token
     */
    function _checkPayedCommissionInNative() internal {
        require(
            msg.value == commissionSettings.fixedNativeTokenCommission,
            "Inaccurate payed commission in native token"
        );
    }
    
    /**
     * @notice Method to take a commission in tokens in conversionOut
     * @param amount - amount of conversion
     * @return commission amount
     */
    function _takeCommissionInTokenOutput(uint256 amount) internal returns (uint256) {
        (uint256 commissionAmountBridgeOwner, uint256 commissionSum) =
            _calculateCommissionInToken(amount);

        (bool transferToReceiver, ) = _token.call(
            abi.encodeWithSelector(
                TRANSFERFROM_SELECTOR,
                _msgSender(),
                commissionSettings.receiverCommission,
                commissionSum - commissionAmountBridgeOwner
            )
        );
        (bool transferToBridgeOwner, ) = _token.call(
            abi.encodeWithSelector(
                TRANSFERFROM_SELECTOR,
                _msgSender(),
                commissionSettings.bridgeOwner,
                commissionAmountBridgeOwner
            )
        );
        require(transferToReceiver && transferToBridgeOwner, "Commission transfer failed");

        return commissionSum;
    }

    /**
     * @notice Method to take a commission in tokens in conversionIn
     * @param amount - amount of conversion
     * @return charged commission amount
     */
    function _takeCommissionInTokenInput(uint256 amount) internal returns (uint256) {
       (uint256 commissionAmountBridgeOwner, uint256 commissionSum) =
            _calculateCommissionInToken(amount);

        (bool transferToReceiver, ) = _token.call(
            abi.encodeWithSelector(
                TRANSFER_SELECTOR,
                commissionSettings.receiverCommission,
                commissionSum - commissionAmountBridgeOwner
            )
        );

        (bool transferToBridgeOwner, ) = _token.call(
            abi.encodeWithSelector(
                TRANSFER_SELECTOR,
                commissionSettings.bridgeOwner,
                commissionAmountBridgeOwner
            )
        );

        require(transferToReceiver && transferToBridgeOwner, "Commission transfer failed");
            
        return commissionSum;
    }

    /**
     * @notice Method for calculation a charged commission in tokens
     * @param amount - amount of conversion
     * @return commission amount
     */
    function _calculateCommissionInToken(uint256 amount) internal view returns (uint256, uint256) {
        if (commissionSettings.commissionType == CommissionType.PercentageTokens) {
            uint256 commissionSum = amount* uint256(commissionSettings.convertTokenPercentage) / ONE_THOUSAND;
            return (
                _calculateCommissionBridgeOwnerProportion(commissionSum), 
                commissionSum
            );
        } else if (commissionSettings.commissionType == CommissionType.FixTokens) {
            return (
                _calculateCommissionBridgeOwnerProportion(
                    commissionSettings.fixedTokenCommission
                ), 
                commissionSettings.fixedTokenCommission
            );
        } else if (commissionSettings.commissionType == CommissionType.NativeCurrency) {
            return (
                _calculateCommissionBridgeOwnerProportion(commissionSettings.fixedNativeTokenCommission),
                (commissionSettings.fixedNativeTokenCommission)
            );
        }
        return (0, 0);
    }

    /**
     * @notice Method for calculation a bridge owner proportion of commission
     * @param amount - amount of conversion
     * @return bridge owner proportion of commission
     */
    function _calculateCommissionBridgeOwnerProportion(uint256 amount) private view returns(uint256) {
        return (amount * uint256(commissionSettings.bridgeOwnerCommissionProportion) / ONE_HUNDRED);
    }

    /**
     * @notice Method for disable commission
     */
    function disableCommission() external onlyOwner {
        commissionSettings.commissionIsEnabled = false;
    }

    /**
     * @notice Method for update commission configuration
     * @param commissionIsEnabled - enable/disable commission on bridge contract
     * @param receiverCommissionProportion - bridge commission receiver proportion
     * @param bridgeOwnerCommissionProportion - bridge owner commission proportion
     * @param newConvertTokenPercentage - percenatage for charge commission in tokens
     * @param newCommissionType - newCommissionType type of charged commission
     * @param newFixedTokenCommission - fix token amount for charged commission in tokens
     * @param newFixedNativeTokenCommission - fix native token amount for charged commission
     * @param receiverCommission - bridge commission receiver address
     * @param bridgeOwner - bridge owner commission receiver address
     */
    function updateCommissionConfiguration(
        bool commissionIsEnabled,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint8 newConvertTokenPercentage,
        uint256 newCommissionType,
        uint256 newFixedTokenCommission,
        uint256 newFixedNativeTokenCommission,
        address payable receiverCommission,
        address payable bridgeOwner
    )
        external onlyOwner
        checkPercentageLimit(newConvertTokenPercentage)
        checkProportion(receiverCommissionProportion, bridgeOwnerCommissionProportion) 
    {
        if (!commissionSettings.commissionIsEnabled)
            commissionSettings.commissionIsEnabled = true;

        _updateCommissionSettings(
            newConvertTokenPercentage,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            newCommissionType,
            newFixedTokenCommission, 
            newFixedNativeTokenCommission,
            receiverCommission,
            bridgeOwner
        );

        emit UpdateCommissionConfiguration(
            commissionIsEnabled,
            newConvertTokenPercentage,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            newCommissionType,
            newFixedTokenCommission,
            newFixedNativeTokenCommission,
            receiverCommission,
            bridgeOwner,
            block.timestamp
        );
    }

    /**
     * @notice Method for change bridge commission receiver address
     * @param newReceiverCommission - new bridge commission receiver address
     */
    function updateReceiverCommission(address newReceiverCommission) external onlyOwner { 
        require(
            newReceiverCommission != address(0),
            "The commission recipient address cannot be zero"
        );
    
        emit UpdateReceiver(commissionSettings.receiverCommission, newReceiverCommission);

        commissionSettings.receiverCommission = payable(newReceiverCommission);
    }

    /**
     * @notice Method for change bridge owner commission receiver address
     * @param newBridgeOwner - new bridge owner commission receiver address
     */
    function updateBridgeOwner(address newBridgeOwner) external onlyOwner {
        require(
            newBridgeOwner != address(0),
            "The commission recipient address cannot be zero"
        );
    
        emit UpdateReceiver(commissionSettings.bridgeOwner, newBridgeOwner);

        commissionSettings.bridgeOwner = payable(newBridgeOwner);
    }

    /**
     * @notice Method for claim collected native token commission
     * @dev This method can be called by one of the recipients, which will result in receiving
     * its share of the collected commission, as well as sending a share to the second recipient
     * according to the current shares in the contract
     */
    function claimNativeCurrencyCommission()
        external
        isCommissionReceiver(_msgSender())
    {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0);

        (bool sendToReceiver, ) = 
            commissionSettings
                .receiverCommission
                .call{ 
                    value: contractBalance * commissionSettings.receiverCommissionProportion / ONE_HUNDRED 
                }("");

        (bool sendToOwner,) = 
        commissionSettings
            .bridgeOwner
            .call{
                value: contractBalance*commissionSettings.bridgeOwnerCommissionProportion/ONE_HUNDRED
            }("");

        require(sendToReceiver && sendToOwner, "Commission claim failed");
        
        emit NativeCurrencyCommissionClaim(block.timestamp);
    }

    /**
     * @notice Method for get receivers addresses
     * @return Receivers addresses
     */
    function getCommissionReceiverAddresses() external view returns(address, address) {
        return (commissionSettings.receiverCommission, commissionSettings.bridgeOwner);
    }

    /**
     * @notice Method for get current commission configuration
     */
    function getCommissionSettings() public view returns (
        bool commissionIsEnabled,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint8 convertTokenPercentage,
        uint256 tokenTypeCommission,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission,
        address payable receiverCommission,
        address payable bridgeOwner,
        address token
    ) {
        return (
            commissionSettings.commissionIsEnabled,
            commissionSettings.receiverCommissionProportion,
            commissionSettings.bridgeOwnerCommissionProportion,
            commissionSettings.convertTokenPercentage,
            uint256(commissionSettings.commissionType),
            commissionSettings.fixedTokenCommission,
            commissionSettings.fixedNativeTokenCommission,
            commissionSettings.receiverCommission,
            commissionSettings.bridgeOwner,
            _token
        );
    }

    /**
     * @notice Method for update configurations parameters
     */
    function _updateCommissionSettings(
        uint8 convertTokenPercentage,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint256 commissionType,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission,
        address payable receiverCommission,
        address payable bridgeOwner
        ) 
        private 
    {
        if(commissionSettings.receiverCommissionProportion != receiverCommissionProportion)
            commissionSettings.receiverCommissionProportion = receiverCommissionProportion; 

        if(commissionSettings.bridgeOwnerCommissionProportion != bridgeOwnerCommissionProportion)  
            commissionSettings.bridgeOwnerCommissionProportion = bridgeOwnerCommissionProportion; 

        if(
            commissionType == 0 && 
            convertTokenPercentage > 0
        ) 
        {
            commissionSettings.convertTokenPercentage = convertTokenPercentage;
            commissionSettings.commissionType = CommissionType.PercentageTokens;
        } else if(commissionType == 1) {
            commissionSettings.fixedTokenCommission = fixedTokenCommission;
            commissionSettings.commissionType = CommissionType.FixTokens;
        } else if(fixedNativeTokenCommission > 0) {
            _checkFixedNativeTokenLimit(fixedNativeTokenCommission);
            commissionSettings.fixedNativeTokenCommission = fixedNativeTokenCommission;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
        }

        if(commissionSettings.receiverCommission != receiverCommission) 
            commissionSettings.receiverCommission = receiverCommission;

        if(commissionSettings.bridgeOwner != bridgeOwner && bridgeOwner != address(0)) 
            commissionSettings.bridgeOwner = bridgeOwner;
    }

    function _checkFixedNativeTokenLimit(uint256 fixedNativeTokenCommission) private view {
        require(
            fixedNativeTokenCommission <= FIXED_NATIVE_TOKEN_COMMISSION_LIMIT, 
            "Violates native token commission limit"
        );
    }
}