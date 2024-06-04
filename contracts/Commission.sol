// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Errors
error CommissionTransferFailed();
error NativeClaimFailed();
error NotEnoughBalance();
error ZeroAddress();
error ViolationOfFixedNativeTokensLimit();
error UnauthorizedCommissionReceiver(address caller);
error PercentageLimitExceeded();
error InvalidProportionSum(uint8 proportion1, uint8 proportion2);
error TakeFixedNativeTokensCommissionFailed(uint256 sent, uint256 required);
error ZeroFixedNativeTokensCommissionLimit();
error EnablingZeroFixedNativeTokenCommission();
error EnablingZeroFixedTokenCommission();
error EnablingZeroTokenPercentageCommission();


/// @title Commission module for bridge contract
/// @author SingularityNET
abstract contract Commission is Ownable, ReentrancyGuard {
    // Address of token contract for  
    address internal immutable TOKEN;

    uint256 private constant ONE_HUNDRED = 100;
    uint256 private immutable FIXED_NATIVE_TOKEN_COMMISSION_LIMIT;
    
    enum CommissionType {
        PercentageTokens, // commission in percentage tokens
        FixedTokens, // commission in fix value of tokens
        FixedNativeTokens // commission in native currency
    }

    CommissionSettings public commissionSettings;
    struct CommissionSettings {
        uint8 convertTokenPercentage; // percentage sum of commission in token
        uint8 receiverCommissionProportion; // proportion for commission receiver
        uint8 bridgeOwnerCommissionProportion; // proportion for bridge owner commission receiver
        uint16 pointOffsetShifter; // point offset variable
        bool commissionIsEnabled; // activate/deactivate commission
        uint256 fixedNativeTokensCommission; // fixed value of commission in native tokens
        uint256 fixedTokenCommission; // fixed value of commission in tokens
        CommissionType commissionType; // global type of commission
        address payable receiverCommission;
        address payable bridgeOwner; // can't be zero address
    } 

    bytes4 private constant TRANSFERFROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 internal constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    // Events
    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event UpdateCommissionType(
        bool indexed commissionIsEnabled,
        uint256 indexed commissionType,
        uint256 indexed timestamp     // matches `Update...Commission` events
    );
    event UpdateFixedNativeTokensCommission( 
        uint256 indexed timestamp,
        uint256 fixedNativeTokensCommission
    );
    event UpdateFixedTokensCommission( 
        uint256 indexed timestamp,
        uint256 fixedTokenCommission
    );
     event UpdatePercentageTokensCommission( 
        uint256 indexed timestamp,
        uint256 convertTokenPercentage,
        uint256 pointOffsetShifter
    );
    event UpdateCommissionProportions(
        uint8 receiverCommissionProportion, 
        uint8 bridgeOwnerCommissionProportion,
        uint256 updateTimestamp
    );
    event FixedNativeTokensCommissionClaim(uint256 indexed time);

    // Check that the caller is a recipient of the commission.
    modifier isCommissionReceiver(address caller) {
        if (
            _msgSender() != commissionSettings.receiverCommission &&
            _msgSender() != commissionSettings.bridgeOwner
        ) 
            revert UnauthorizedCommissionReceiver(_msgSender());
        _;
    }

    modifier checkProportion(uint8 proportionOne, uint8 proportionTwo) {
        if (proportionOne + proportionTwo != uint8(100)) 
            revert InvalidProportionSum(proportionOne, proportionTwo);
        _;
    }

    modifier notZeroAddress(address account) {
        if (account == address(0))
            revert ZeroAddress();
        _;
    }

    constructor(
        address token,
        bool commissionIsEnabled,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint256 fixedNativeTokensCommissionLimit,
        address payable receiverCommission,
        address payable bridgeOwner
    ) 
        Ownable() 
        notZeroAddress(token) 
        notZeroAddress(bridgeOwner) 
    {

        TOKEN = token;

        if (fixedNativeTokensCommissionLimit == 0)
            revert ZeroFixedNativeTokensCommissionLimit();
        FIXED_NATIVE_TOKEN_COMMISSION_LIMIT = fixedNativeTokensCommissionLimit;
 
        uint256 timestamp = block.timestamp;
        if (commissionIsEnabled) {
            commissionSettings.commissionIsEnabled = true;
            emit UpdateCommissionType(true, 0, timestamp);
        }

        if (receiverCommission != address(0)) {
            commissionSettings.receiverCommission = payable(receiverCommission);
            emit UpdateReceiver(address(0), receiverCommission);
            
            updateCommissionProportions(receiverCommissionProportion, bridgeOwnerCommissionProportion);
        } else {
            updateCommissionProportions(0, 100);
        }

        commissionSettings.bridgeOwner = payable(bridgeOwner);
        emit UpdateReceiver(address(0), bridgeOwner);

        emit UpdateCommissionProportions(
            receiverCommissionProportion, 
            bridgeOwnerCommissionProportion, 
            timestamp
        );
    }

    /**
     * @notice Method to disable commission of any type
     */
    function disableCommission() external onlyOwner {
        commissionSettings.commissionIsEnabled = false;

        emit UpdateCommissionType(false, uint256(commissionSettings.commissionType), block.timestamp);
    }


    /**
     * @notice Method to enable commission, if it's not enabled and
     *  update amount of native tokens charged as a commission
     * @dev Enables the commission if it is currently disabled. Sets the commission type to fixed native tokens if it is not already. 
     * If `newFixedNativeTokensCommission` is non-zero, updates the commission amount. Emits corresponding events.
     * @param newFixedNativeTokensCommission The new amount of native tokens to be charged as commission.
     */
    function enableAndUpdateFixedNativeTokensCommission(
        uint256 newFixedNativeTokensCommission
    ) 
        external 
        onlyOwner 
    {
        uint256 timestamp = block.timestamp;

        if (!commissionSettings.commissionIsEnabled) {
            commissionSettings.commissionIsEnabled = true;
        }

        // enable type of fixed native token commission
        if ( commissionSettings.commissionType != CommissionType.FixedNativeTokens) {
            if (newFixedNativeTokensCommission == 0)
                revert EnablingZeroFixedNativeTokenCommission();
            commissionSettings.commissionType = CommissionType.FixedNativeTokens;
            emit UpdateCommissionType(true, 2, timestamp);
        }

        // update amount of fixed native token commission
        _checkFixedFixedNativeTokensLimit(newFixedNativeTokensCommission);
        commissionSettings.fixedNativeTokensCommission = newFixedNativeTokensCommission;
        emit UpdateFixedNativeTokensCommission(timestamp, newFixedNativeTokensCommission);
    }

    /**
     * @notice Method to enable commission, if it's not enabled and update the amount of fixed tokens charged as a commission.
     * @dev Enables the commission if it is currently disabled. Sets the commission type to fixed tokens if it is not already. 
     * If `newFixedTokenCommission` is non-zero, updates the commission amount. Emits corresponding events.
     * @param newFixedTokenCommission The new amount of fixed tokens to be charged as commission.
     */
    function enableAndUpdateFixedTokensCommission(uint256 newFixedTokenCommission) external onlyOwner {
        uint256 timestamp = block.timestamp;

        if (!commissionSettings.commissionIsEnabled) 
            commissionSettings.commissionIsEnabled = true;

        // enable type of fixed token commission
        if (commissionSettings.commissionType != CommissionType.FixedTokens) {
            if (newFixedTokenCommission == 0)
                revert EnablingZeroFixedTokenCommission();
            commissionSettings.commissionType = CommissionType.FixedTokens;
            emit UpdateCommissionType(true, 1, timestamp);
        }
            
        // update amount of fixed token commission
        commissionSettings.fixedTokenCommission = newFixedTokenCommission;
        emit UpdateFixedTokensCommission(timestamp, newFixedTokenCommission);
    }

    /**
     * @notice Method to enable commission, if it's not enabled and update the percentage of tokens charged as a commission.
     *  Updates together token percentage and point offset shifter
     * @dev Enables the commission if it is currently disabled. Sets the commission type to percentage tokens if it is not already. 
     * If `newConvertTokenPercentage` and `newPointOffsetShifter` are non-zero, updates the commission percentage and point offset. 
     * Emits corresponding events.
     * @param newConvertTokenPercentage The new percentage of tokens to be charged as commission.
     * @param newPointOffsetShifter The new point offset shifter for the token percentage commission.
     */
    function enableAndUpdatePercentageTokensCommission(
        uint8 newConvertTokenPercentage, 
        uint16 newPointOffsetShifter
    ) 
        external 
        onlyOwner 
    {
        uint256 timestamp = block.timestamp;

        if (!commissionSettings.commissionIsEnabled) 
            commissionSettings.commissionIsEnabled = true;

        // enable type of token commission in percentage
        if (commissionSettings.commissionType != CommissionType.PercentageTokens) {
            if (newConvertTokenPercentage == 0 || newPointOffsetShifter == 0)
                revert EnablingZeroTokenPercentageCommission();
            commissionSettings.commissionType = CommissionType.PercentageTokens;
            emit UpdateCommissionType(true, 0, timestamp);
        }

        // update amount of token commission in percentage
        _checkPercentageLimit(newConvertTokenPercentage, newPointOffsetShifter);
        commissionSettings.pointOffsetShifter = newPointOffsetShifter;
        commissionSettings.convertTokenPercentage = newConvertTokenPercentage;
        emit UpdatePercentageTokensCommission(
            timestamp, 
            newConvertTokenPercentage, 
            newPointOffsetShifter
        );
    }

    /**
     * @notice Method for changing bridge commission receiver address
     * @dev newReceiverCommission address can be zero address
     * @param newReceiverCommission - new bridge commission receiver address
     */
    function updateReceiverCommission(address newReceiverCommission) external onlyOwner { 
        if(newReceiverCommission == address(0))
            updateCommissionProportions(0, 100);
        emit UpdateReceiver(commissionSettings.receiverCommission, newReceiverCommission);

        commissionSettings.receiverCommission = payable(newReceiverCommission);
    }

    /**
     * @notice Method for changing bridge owner commission receiver address
     * @param newBridgeOwner - new bridge owner commission receiver address
     */
    function updateBridgeOwner(address newBridgeOwner) 
        external 
        onlyOwner  
        notZeroAddress(newBridgeOwner)
    {
        emit UpdateReceiver(commissionSettings.bridgeOwner, newBridgeOwner);

        commissionSettings.bridgeOwner = payable(newBridgeOwner);
    }

    /**
     * @notice Method for claiming collected native token commission
     * @dev This method can be called by one of the recipients, which will result in receiving
     * its share of the collected commission, as well as sending a share to the second recipient
     * according to the current shares in the contract
     */
    function claimFixedNativeTokensCommission()
        external
        nonReentrant
        isCommissionReceiver(_msgSender())
    {
        uint256 contractBalance = address(this).balance;
        if (contractBalance == 0 )
            revert NotEnoughBalance();

        if (
            commissionSettings.receiverCommissionProportion != 0
        ) {
            (bool sendToReceiver, ) = 
                commissionSettings.receiverCommission
                    .call{ 
                        value: 
                            contractBalance * commissionSettings.receiverCommissionProportion 
                                / ONE_HUNDRED 
                    }("");
        
            if (!sendToReceiver) {
                revert NativeClaimFailed();
            }
        }

        (bool sendToOwner,) = 
            commissionSettings.bridgeOwner
                .call{
                    value: 
                        contractBalance * commissionSettings.bridgeOwnerCommissionProportion 
                            / ONE_HUNDRED
                }("");

        if (!sendToOwner) 
            revert NativeClaimFailed();
        
        emit FixedNativeTokensCommissionClaim(block.timestamp);
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
    function getCommissionSettings() external view returns (
        bool commissionIsEnabled,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint8 convertTokenPercentage,
        uint16 offsetShifter,
        uint256 tokenTypeCommission,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokensCommission,
        address payable receiverCommission,
        address payable bridgeOwner,
        address token
    ) {
        return (
            commissionSettings.commissionIsEnabled,
            commissionSettings.receiverCommissionProportion,
            commissionSettings.bridgeOwnerCommissionProportion,
            commissionSettings.convertTokenPercentage,
            commissionSettings.pointOffsetShifter,
            uint256(commissionSettings.commissionType),
            commissionSettings.fixedTokenCommission,
            commissionSettings.fixedNativeTokensCommission,
            commissionSettings.receiverCommission,
            commissionSettings.bridgeOwner,
            TOKEN
        );
    }

    /**
     * @notice Method to update the commission proportions for the receiver and the bridge owner.
     * @dev Updates the receiver's commission proportion and the bridge owner's commission proportion 
     * if the new values are different from the current ones. Emits an event with the new proportions.
     * @param newReceiverCommissionProportion The new proportion of commission for the receiver.
     * @param newBridgeOwnerCommissionProportion The new proportion of commission for the bridge owner.
     */
    function updateCommissionProportions(
        uint8 newReceiverCommissionProportion,
        uint8 newBridgeOwnerCommissionProportion
    ) 
        public
        onlyOwner
        checkProportion(
            newReceiverCommissionProportion, 
            newBridgeOwnerCommissionProportion
        ) 
    {
        // receiverCommissionProportion can be null
        if (commissionSettings.receiverCommissionProportion != newReceiverCommissionProportion)
            commissionSettings.receiverCommissionProportion = newReceiverCommissionProportion; 

        if (
            newBridgeOwnerCommissionProportion != 0 && 
            commissionSettings.bridgeOwnerCommissionProportion != newBridgeOwnerCommissionProportion
        )  
            commissionSettings.bridgeOwnerCommissionProportion = newBridgeOwnerCommissionProportion; 

        emit UpdateCommissionProportions(
            commissionSettings.receiverCommissionProportion, 
            commissionSettings.bridgeOwnerCommissionProportion,
            block.timestamp
        );
    }


    /**
     * @notice Method to check when charging a fee in native token
     */
    function _checkPayedCommissionInNative() internal {
        if (msg.value != commissionSettings.fixedNativeTokensCommission) {
            revert TakeFixedNativeTokensCommissionFailed(
                msg.value,
                commissionSettings.fixedNativeTokensCommission
            );
        }
    }
    
    /**
     * @notice Method to take a commission in tokens in conversionOut
     * @param amount - amount of conversion
     * @return charged commission amount
     */
    function _takeCommissionInTokenOutput(uint256 amount) internal returns (uint256) {
        (uint256 commissionAmountBridgeOwner, uint256 commissionSum) =
            _calculateCommissionInToken(amount);

        if (commissionSettings.receiverCommissionProportion != 0 && commissionSum != commissionAmountBridgeOwner) {
            (bool transferToReceiver, ) = TOKEN.call(
                abi.encodeWithSelector(
                    TRANSFERFROM_SELECTOR,
                    _msgSender(),
                    commissionSettings.receiverCommission,
                    commissionSum - commissionAmountBridgeOwner
                )
            );
            
            if (!transferToReceiver) 
                revert CommissionTransferFailed();
        }
        (bool transferToBridgeOwner, ) = TOKEN.call(
            abi.encodeWithSelector(
                TRANSFERFROM_SELECTOR,
                _msgSender(),
                commissionSettings.bridgeOwner,
                commissionAmountBridgeOwner
            )
        );

        if(!transferToBridgeOwner) 
            revert CommissionTransferFailed();

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

        if (commissionSettings.receiverCommissionProportion != 0 && commissionSum != commissionAmountBridgeOwner) {
            (bool transferToReceiver, ) = TOKEN.call(
                abi.encodeWithSelector(
                    TRANSFER_SELECTOR,
                    commissionSettings.receiverCommission,
                    commissionSum - commissionAmountBridgeOwner
                )
            );
            
            if (!transferToReceiver) 
                revert CommissionTransferFailed();
        }

        (bool transferToBridgeOwner, ) = TOKEN.call(
            abi.encodeWithSelector(
                TRANSFER_SELECTOR,
                commissionSettings.bridgeOwner,
                commissionAmountBridgeOwner
            )
        );

        if (!transferToBridgeOwner) 
            revert CommissionTransferFailed();

        return commissionSum;
    }

    /**
     * @notice Method for calculating a charging commission in tokens
     * @param amount - amount of conversion
     * @return commission amount for bridge owner and the whole sum of commission
     */
    function _calculateCommissionInToken(uint256 amount) internal view returns (uint256, uint256) {
        if (commissionSettings.commissionType == CommissionType.PercentageTokens) {
            uint256 commissionSum = amount* uint256(commissionSettings.convertTokenPercentage) / commissionSettings.pointOffsetShifter;
            return (
                _calculateCommissionBridgeOwnerProportion(commissionSum), 
                commissionSum
            );
        } else {
            return (
                _calculateCommissionBridgeOwnerProportion(
                    commissionSettings.fixedTokenCommission
                ), 
                commissionSettings.fixedTokenCommission
            );
        }
    }

    /**
     * @notice Method for calculating a bridge owner proportion of the whole sum of commission
     * @param amount - amount of conversion
     * @return bridge owner proportion of commission
     */
    function _calculateCommissionBridgeOwnerProportion(uint256 amount) private view returns(uint256) {
        return (amount * uint256(commissionSettings.bridgeOwnerCommissionProportion) / ONE_HUNDRED);
    }

    /**
     * @notice Method to disable commission
     * @param fixedNativeTokensCommission - value native tokens commission value for check
     */
    function _checkFixedFixedNativeTokensLimit(uint256 fixedNativeTokensCommission) private view {
        if (fixedNativeTokensCommission > FIXED_NATIVE_TOKEN_COMMISSION_LIMIT)
            revert ViolationOfFixedNativeTokensLimit();
    }

    /**
     * @notice Method to check customization of percenatage parameters
     * @param convertTokenPercentage - new convert token percentage
     * @param pointOffsetShifter - new offset point shifter
     */
    // convertTokenPercentage <= pointOffsetShifter in order to represent 
    // floating point fees with one decimal place
    function _checkPercentageLimit(uint8 convertTokenPercentage, uint16 pointOffsetShifter) private pure {
        if (convertTokenPercentage > pointOffsetShifter) 
            revert PercentageLimitExceeded();
    }
}