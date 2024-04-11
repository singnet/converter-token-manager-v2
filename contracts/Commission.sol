// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Commission is Ownable {

    uint8 private _nativeTokenPercentage;
    uint8 private _convertTokenPercentage;

    // Address of token contract
    address internal _token; 
    address payable private _commissionReceiver;

    uint256 private constant ONE_HUNDRED = 100;

    event UpdateCommission(bool indexed nativeToken, uint8 newCommissionPercentage);
    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCommissionClaim(uint256 claimedBalance);

    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= 100, "Violates percentage limits");
        _;
    }

    constructor(
        uint8 nativeTokenPercentage, 
        uint8 convertTokenPercentage
    ) 
        Ownable(_msgSender()) 
        checkPercentageLimit(nativeTokenPercentage) 
        checkPercentageLimit(convertTokenPercentage) 
    {
        if(nativeTokenPercentage != 0) 
            _nativeTokenPercentage = nativeTokenPercentage; 
        if(convertTokenPercentage != 0) 
            _convertTokenPercentage = convertTokenPercentage; 
    }

    function _checkPayedCommissionInNative(uint256 amount) internal {
        require(
            msg.value == amount * uint256(_nativeTokenPercentage) / ONE_HUNDRED,
            "Inaccurate payed commission in native token"
        );
    }

    function _takeCommissionInToken(uint256 amount) internal returns (uint256) {
        uint256 commissionAmount = _calculateCommissionInToken(amount);

        if(commissionAmount > 0) {
            (bool success, ) = _token.call(
                abi.encodeWithSelector(
                    0x23b872dd, 
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

    function setNativeTokenCommission(uint8 commissionPercentage) 
        external 
        onlyOwner
        checkPercentageLimit(commissionPercentage) 
    {
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
}