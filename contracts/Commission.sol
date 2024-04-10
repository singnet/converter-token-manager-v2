// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../interfaces/IERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Commission is Ownable {

    // Address of token contract
    IERC20Burnable public token; 
    address payable public commissionReceiver;

    uint8 public nativeTokenPercentage;
    uint8 public convertTokenPercentage;

    uint256 private constant ONE_HUNDRED = 100;

    event UpdateCommission(bool indexed nativeToken, uint8 newCommissionPercentage);
    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCommissionClaim(uint256 claimedBalance);

    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= 100, "Violates percentage limits");
        _;
    }

    constructor(
        uint8 _nativeTokenPercentage, 
        uint8 _convertTokenPercentage
    ) 
        Ownable(_msgSender()) 
        checkPercentageLimit(_nativeTokenPercentage) 
        checkPercentageLimit(_convertTokenPercentage) 
    {
        if(_nativeTokenPercentage != 0) 
            nativeTokenPercentage = _nativeTokenPercentage; 
        if(_convertTokenPercentage != 0) 
            convertTokenPercentage = _convertTokenPercentage; 
    }

    function _takeCommission(bool inNativeToken, uint256 amountToConvert) internal {
        if(inNativeToken) {
            require(
                msg.value == amountToConvert * uint256(nativeTokenPercentage) / ONE_HUNDRED,
                "Inaccurate payed commission in native token"
            );
        }
        else {
            if(convertTokenPercentage != 0)  {
                // direct transfer to commissionReceiver to safe fee
                // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
                (bool success, ) = address(token).call(
                        abi.encodeWithSelector(
                        0x23b872dd, 
                        _msgSender(), 
                        commissionReceiver, 
                        amountToConvert * uint256(convertTokenPercentage) / ONE_HUNDRED
                    )
                );

                require(success, "Commission transfer failed");
            }
        }
    }

    function setNativeTokenCommission(uint8 commissionPercentage) 
        external 
        onlyOwner
        checkPercentageLimit(commissionPercentage) 
    {
        nativeTokenPercentage = commissionPercentage;

        emit UpdateCommission(true, commissionPercentage);
    }

    function setConvertTokenCommission(uint8 commissionPercentage) 
        external 
        onlyOwner
        checkPercentageLimit(commissionPercentage) 
    {
        convertTokenPercentage = commissionPercentage;

        emit UpdateCommission(false, commissionPercentage);
    }

    function setCommissionReceiver(address newCommissionReceiver) external onlyOwner {
        require(newCommissionReceiver != address(0));

        emit UpdateReceiver(commissionReceiver, newCommissionReceiver);

        commissionReceiver = payable(newCommissionReceiver);
    }

    function claimNativeTokenCommission() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        (bool success,) = commissionReceiver.call{value: contractBalance}("");
        require(success, "Commission claim failed");
        
        emit NativeCommissionClaim(contractBalance);
    }
}