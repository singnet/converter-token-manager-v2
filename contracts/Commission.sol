// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Errors
error CommissionTransferFailed();
error NativeClaimFailed();
error InvalidUpdateConfigurations();
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
error CommissionIsNotEnabled();


/// @title Commission module for bridge contract
/// @author SingularityNET
abstract contract Commission is Ownable, ReentrancyGuard {

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
    
    // Address of token contract for  
    address internal immutable _token;

    bytes4 private constant TRANSFERFROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 internal constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    // Events
    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event FixedNativeTokensCommissionClaim(uint256 indexed time);
    event UpdateCommissionConfiguration(
        bool commissionIsEnabled,
        uint8 convertTokenPercentage,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint16 pointOffsetShifter,
        uint256 commissionType,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokensCommission,
        address payable receiverCommission,
        address payable bridgeOwner,
        uint256 updateTimestamp
    );

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
        if(account == address(0))
            revert ZeroAddress();
        _;
    }

    constructor(
        address token,
        bool commissionIsEnabled,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
      /* uint8 convertTokenPercentage,
        uint16 pointOffsetShifter,
        uint256 commissionType,
        uint256 fixedNativeTokensCommission,*/
        uint256 fixedNativeTokensCommissionLimit,
       // uint256 fixedTokenCommission,
        address payable receiverCommission,
        address payable bridgeOwner
    ) 
        Ownable() 
        notZeroAddress(token) 
        notZeroAddress(bridgeOwner) 
    {

        _token = token;

        if (fixedNativeTokensCommissionLimit == 0)
            revert ZeroFixedNativeTokensCommissionLimit();
        FIXED_NATIVE_TOKEN_COMMISSION_LIMIT = fixedNativeTokensCommissionLimit;

        if (commissionIsEnabled) 
            commissionSettings.commissionIsEnabled = true;

        updateCommissionProportions(receiverCommissionProportion, bridgeOwnerCommissionProportion);

        commissionSettings.bridgeOwner = payable(bridgeOwner);
        if(receiverCommission != address(0))
            commissionSettings.receiverCommission = payable(receiverCommission);

        emit UpdateCommissionConfiguration(
            commissionIsEnabled,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            receiverCommission,
            bridgeOwner,
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

        if (commissionSettings.receiverCommission != address(0) && commissionSum != commissionAmountBridgeOwner) {
            (bool transferToReceiver, ) = _token.call(
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
        (bool transferToBridgeOwner, ) = _token.call(
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

        if (commissionSettings.receiverCommission != address(0) && commissionSum != commissionAmountBridgeOwner) {
            (bool transferToReceiver, ) = _token.call(
                abi.encodeWithSelector(
                    TRANSFER_SELECTOR,
                    commissionSettings.receiverCommission,
                    commissionSum - commissionAmountBridgeOwner
                )
            );
            
            if (!transferToReceiver) 
                revert CommissionTransferFailed();
        }

        (bool transferToBridgeOwner, ) = _token.call(
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
        } else if (commissionSettings.commissionType == CommissionType.FixedTokens) {
            return (
                _calculateCommissionBridgeOwnerProportion(
                    commissionSettings.fixedTokenCommission
                ), 
                commissionSettings.fixedTokenCommission
            );
        } else if (commissionSettings.commissionType == CommissionType.FixedNativeTokens) {
            return (
                _calculateCommissionBridgeOwnerProportion(commissionSettings.fixedNativeTokensCommission),
                (commissionSettings.fixedNativeTokensCommission)
            );
        }
        return (0, 0);
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
     */
    function disableCommission() external onlyOwner {
        commissionSettings.commissionIsEnabled = false;
    }

    /**
     * @notice Method for updating commission configuration
     * @param commissionIsEnabled - enable/disable commission on bridge contract
     * @param receiverCommissionProportion - bridge commission receiver proportion
     * @param bridgeOwnerCommissionProportion - bridge owner commission proportion
     * @param newConvertTokenPercentage - percenatage for charging commission in tokens
     * @param newCommissionType - newCommissionType type of charging commission
     * @param newFixedTokenCommission - fix token amount for charging commission in tokens
     * @param newFixedNativeTokensCommission - fix native token amount for charging commission
     * @param receiverCommission - bridge commission receiver address
     * @param bridgeOwner - bridge owner commission receiver address
     */
    function updateCommissionConfiguration(
        bool commissionIsEnabled,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint8 newConvertTokenPercentage,
        uint16 newPointOffsetShifter,
        uint256 newCommissionType,
        uint256 newFixedTokenCommission,
        uint256 newFixedNativeTokensCommission,
        address payable receiverCommission,
        address payable bridgeOwner
    )
        external onlyOwner
      
    {
   
        _checkPercentageLimit(newConvertTokenPercentage, newPointOffsetShifter);


        emit UpdateCommissionConfiguration(
            commissionIsEnabled,
            newConvertTokenPercentage,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            newPointOffsetShifter,
            newCommissionType,
            newFixedTokenCommission,
            newFixedNativeTokensCommission,
            receiverCommission,
            bridgeOwner,
            block.timestamp
        );
    }

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

    }

    function enableAndUpdateFixedNativeTokensCommission(uint256 newFixedNativeTokensCommission) external onlyOwner {
        if(!commissionSettings.commissionIsEnabled) 
            commissionSettings.commissionIsEnabled = true;

        // enable type of fixed native token commission
        if(commissionSettings.commissionType != CommissionType.FixedNativeTokens) {
            if(
                newFixedNativeTokensCommission == 0 &&
                commissionSettings.fixedNativeTokensCommission == 0
            )
                revert EnablingZeroFixedNativeTokenCommission();
            commissionSettings.commissionType = CommissionType.FixedNativeTokens;
        }

        // update amount of fixed native token commission
        if (newFixedNativeTokensCommission != 0) {
            _checkFixedFixedNativeTokensLimit(newFixedNativeTokensCommission);
            commissionSettings.fixedNativeTokensCommission = newFixedNativeTokensCommission;
        }
    }

    function enableAndUpdateFixedTokensCommission(uint256 newFixedTokenCommission) external onlyOwner {
        if(!commissionSettings.commissionIsEnabled) 
            commissionSettings.commissionIsEnabled = true;

        // enable type of fixed token commission
        if(commissionSettings.commissionType != CommissionType.FixedTokens) {
            if(
                newFixedTokenCommission == 0 &&
                commissionSettings.fixedTokenCommission == 0
            )
                revert EnablingZeroFixedTokenCommission();
            commissionSettings.commissionType = CommissionType.FixedTokens;
        }
            
        // update amount of fixed token commission
        if (newFixedTokenCommission != 0) {
            commissionSettings.fixedTokenCommission = newFixedTokenCommission;
        }
    }

    function enableAndUpdatePercentageTokensCommission(
        uint8 newConvertTokenPercentage, 
        uint16 newPointOffsetShifter
    ) 
        external 
        onlyOwner 
    {
        if(!commissionSettings.commissionIsEnabled) 
            commissionSettings.commissionIsEnabled = true;

        // enable type of token commission in percentage
        if(commissionSettings.commissionType != CommissionType.PercentageTokens) {
            if(
                newConvertTokenPercentage == 0 &&
                commissionSettings.convertTokenPercentage == 0
            )
                revert EnablingZeroTokenPercentageCommission();
            commissionSettings.commissionType = CommissionType.PercentageTokens;
        }

        // update amount of token commission in percentage
        if (_checkPercentageLimit(newConvertTokenPercentage, newPointOffsetShifter)) {
            commissionSettings.pointOffsetShifter = newPointOffsetShifter;
            commissionSettings.convertTokenPercentage = newConvertTokenPercentage;
        }   
    }

    /**
     * @notice Method for change bridge commission receiver address
     * @dev newReceiverCommission address can be zero address
     * @param newReceiverCommission - new bridge commission receiver address
     */
    function updateReceiverCommission(address newReceiverCommission) external onlyOwner { 
        emit UpdateReceiver(commissionSettings.receiverCommission, newReceiverCommission);

        commissionSettings.receiverCommission = payable(newReceiverCommission);
    }

    /**
     * @notice Method for change bridge owner commission receiver address
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
     * @notice Method for claim collected native token commission
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
        if (contractBalance < 0 )
            revert NotEnoughBalance();

        if (
            commissionSettings.receiverCommission != address(0) && 
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
    function getCommissionSettings() public view returns (
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
            _token
        );
    }

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
    function _checkPercentageLimit(uint8 convertTokenPercentage, uint16 pointOffsetShifter) private pure returns(bool) {
        if (
            convertTokenPercentage != 0 &&
            pointOffsetShifter != 0 &&
            convertTokenPercentage > pointOffsetShifter) 
        {
            revert PercentageLimitExceeded();
        }
        return true;
    }
}