// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Commission is Ownable {

    uint8 private _nativeTokenPercentage;
    uint8 private _convertTokenPercentage;

    // Address of token contract
    address internal _token; 
    address payable private _commissionReceiver;


    /**
     * 100 - 1% of 1 ETH = 0.01 ETH
     * 10000 - 0.01% of 1 ETH = 0.0001 ETH
     * 1000000 - 0.0001% of 1 ETH = 0.000001 ETH (Default)
     * 
     * formula:
     * 1 ETH * nativeTokenPercentage / pointIndicator
     * 
     */
    uint256 private pointIndicator = 1000000;
    
    bool private commissionInNativeToken;

    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));

    event UpdateCommission(bool indexed nativeToken, uint8 newCommissionPercentage);
    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCommissionClaim(uint256 claimedBalance);
    event ChangeComissionType(bool indexed status, uint256 time);
    event UpdatePointIndicator(uint32 newIndicator, uint256 time);

    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= 100, "Violates percentage limits");
        _;
    }

    constructor(
        uint8 nativeTokenPercentage, 
        uint8 convertTokenPercentage
    ) 
        Ownable() 
        checkPercentageLimit(nativeTokenPercentage) 
        checkPercentageLimit(convertTokenPercentage) 
    {
        if(nativeTokenPercentage != 0) 
            _nativeTokenPercentage = nativeTokenPercentage; 
        if(convertTokenPercentage != 0) 
            _convertTokenPercentage = convertTokenPercentage; 
    }

    function _checkPayedCommissionInNative() internal {
        require(
            msg.value == 1 ether * uint256(_nativeTokenPercentage) / pointIndicator,
            "Inaccurate payed commission in native token"
        );
    }

    function _checkPointIndicator(uint32 _indicator) internal {
        require(_indicator > 0, "Point indicator must be greater than zero");
        require(_indicator <= 1000000, "Point indicator exceeds maximum allowed value, point indicator is too low");
        require(_indicator != pointIndicator, "New point indicator must be different from current value");
    }

    function _takeCommissionInToken(uint256 amount) internal returns (uint256) {
        uint256 commissionAmount = _calculateCommissionInToken(amount);

        if (commissionAmount > 0) {
            (bool success, ) = _token.call(
                abi.encodeWithSelector(
                    TRANSFER_SELECTOR,
                    _msgSender(),
                    _commissionReceiver,
                    commissionAmount
                )
            );

            require(success, "Commission transfer failed");
        }
        return commissionAmount;
    }

    // returns commission 
    function _calculateCommissionInToken(uint256 amount) internal view returns (uint256) {
        if(_convertTokenPercentage > 0)  
           return amount * uint256(_convertTokenPercentage) / ONE_HUNDRED;
        
        return 0;
    }

    function enableNativeTokenComission(bool enableNativeComission) external onlyOwner {
        require(commissionInNativeToken != enableNativeComission);
        commissionInNativeToken = enableNativeComission;

        emit ChangeComissionType(enableNativeComission, block.timestamp);
    }

    function setNativeTokenCommission(uint8 commissionPercentage) 
        external 
        onlyOwner
        checkPercentageLimit(commissionPercentage) 
    { 
        require(commissionInNativeToken);
        _nativeTokenPercentage = commissionPercentage;

        emit UpdateCommission(true, commissionPercentage);
    }

    function setConvertTokenCommission(uint8 commissionPercentage) 
        external 
        onlyOwner
        checkPercentageLimit(commissionPercentage) 
    {
        _convertTokenPercentage = commissionPercentage;

        emit UpdateCommission(false, commissionPercentage);
    }

    function setCommissionReceiver(address newCommissionReceiver) external onlyOwner {
        require(newCommissionReceiver != address(0));

        emit UpdateReceiver(_commissionReceiver, newCommissionReceiver);

        _commissionReceiver = payable(newCommissionReceiver);
    }

    function setPointIndicator(uint32 newPointIndicator) external onlyOwner {
        _checkPointIndicator(newPointIndicator);
        
        pointIndicator = newPointIndicator;
        
        emit UpdatePointIndicator(newPointIndicator, block.timestamp);
    }

    function claimNativeTokenCommission() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        (bool success,) = _commissionReceiver.call{value: contractBalance}("");
        require(success, "Commission claim failed");
        
        emit NativeCommissionClaim(contractBalance);
    }

    function getCommissionReceiverAddress() external view returns(address) {
        return _commissionReceiver;
    }

    function getConfigurations() external view returns(address, uint8, uint8) {
        return (_token, _nativeTokenPercentage, _convertTokenPercentage);
    }

    function getComissionType() external view returns(bool) {
        return commissionInNativeToken;
    }
}