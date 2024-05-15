// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Commission.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenConversionManager is Commission, ReentrancyGuard {
    address private _conversionAuthorizer; // Authorizer Address for the conversion

    bytes4 private constant MINT_SELECTOR = bytes4(keccak256("mint(address,uint256)"));
    bytes4 private constant BURN_SELECTOR = bytes4(keccak256("burnFrom(address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    //already used conversion signature from authorizer in order to prevent replay attack
    mapping (bytes32 => bool) private _usedSignatures; 

    // Conversion Configurations
    uint256 private _perTxnMinAmount;
    uint256 private _perTxnMaxAmount;
    uint256 private _maxSupply;

    // Events
    event NewAuthorizer(address conversionAuthorizer);
    event UpdateConfiguration(uint256 perTxnMinAmount, uint256 perTxnMaxAmount, uint256 maxSupply);

    event ConversionOut(address indexed tokenHolder, bytes32 conversionId, uint256 amount);
    event ConversionIn(address indexed tokenHolder, bytes32 conversionId, uint256 amount);


    // Modifiers
    modifier checkLimits(uint256 amount) {
        // Check for min, max per transaction limits
        require(amount >= _perTxnMinAmount && amount <= _perTxnMaxAmount, "Violates conversion limits");
        _;
    }

    constructor(
        address token, 
        bool commissionIsEnabled,
        uint8 convertTokenPercentage,
        uint8 receiverCommissionProportion,
        uint8 bridgeOwnerCommissionProportion,
        uint256 commissionType,
        uint256 fixedNativeTokenCommission,
        uint256 fixedNativeTokenCommissionLimit,
        uint256 fixedTokenCommission,
        address payable commissionReceiver,
        address payable bridgeOwner
    ) 
        Commission(
            commissionIsEnabled,
            convertTokenPercentage,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            commissionType,
            fixedNativeTokenCommission,
            fixedNativeTokenCommissionLimit,
            fixedTokenCommission,
            commissionReceiver,
            bridgeOwner
        )
    {
        _token = token;
        _conversionAuthorizer = _msgSender(); 
    }

    /**
    * @dev To update the authorizer who can authorize the conversions.
    */
    function updateAuthorizer(address newAuthorizer) external onlyOwner {
        require(newAuthorizer != address(0), "Invalid operator address");

        _conversionAuthorizer = newAuthorizer;

        emit NewAuthorizer(newAuthorizer);
    }

    /**
    * @dev To update the per transaction limits for the conversion and to provide max total supply 
    */
    function updateConfigurations(
        uint256 perTxnMinAmount, 
        uint256 perTxnMaxAmount, 
        uint256 maxSupply
    )
        external 
        onlyOwner 
    {
        // Check for the valid inputs
        require(perTxnMinAmount > 0 && perTxnMaxAmount > perTxnMinAmount && maxSupply > 0, "Invalid inputs");

        // Update the configurations
        _perTxnMinAmount = perTxnMinAmount;
        _perTxnMaxAmount = perTxnMaxAmount;
        _maxSupply = maxSupply;

        emit UpdateConfiguration(perTxnMinAmount, perTxnMaxAmount, maxSupply);
    }


    /**
    * @dev To convert the tokens from Ethereum to non Ethereum network. 
    * The tokens which needs to be convereted will be burned on the host network.
    * The conversion authorizer needs to provide the signature to call this function.
    */
    function conversionOut(
        uint256 amount, 
        bytes32 conversionId, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) 
        external 
        payable
        checkLimits(amount) 
        nonReentrant 
    {
        // Check for non zero value for the amount is not needed as the Signature will not be generated for zero amount

        // Check for the Balance
        require(IERC20(_token).balanceOf(_msgSender()) >= amount, "Not enough balance");
        
        //compose the message which was signed
        bytes32 message = prefixed(
            keccak256(
                abi.encodePacked(
                    "__conversionOut", 
                    amount,
                    _msgSender(),
                    conversionId, 
                    this
                )
            )
        );

        // check that the signature is from the authorizer
        require(ecrecover(message, v, r, s) == _conversionAuthorizer, "Invalid request or signature");

        //check for replay attack (message signature can be used only once)
        require(!_usedSignatures[message], "Signature has already been used");
        _usedSignatures[message] = true;
        
        if (commissionSettings.commissionIsEnabled) {
            if(commissionSettings.commissionType == CommissionType.NativeCurrency) 
                _checkPayedCommissionInNative();
            else
                // amount to burn = amount - commission
                // commission is transffered in '_takeCommissionInTokenOutput()'
                amount -= _takeCommissionInTokenOutput(amount);
        }
            
        // Burn the tokens on behalf of the Wallet
        // token.burnFrom(_msgSender(), amount)
        (bool success, ) = _token.call(abi.encodeWithSelector(BURN_SELECTOR, _msgSender(), amount));

        // In case if the burn call fails
        require(success, "conversionOut Failed");

        emit ConversionOut(_msgSender(), conversionId, amount);
    }

    /**
    * @dev To convert the tokens from non Ethereum to Ethereum network. 
    * The tokens which needs to be convereted will be minted on the host network.
    * The conversion authorizer needs to provide the signature to call this function.
    */
    function conversionIn(
        address to, 
        uint256 amount, 
        bytes32 conversionId, 
        uint8 v, 
        bytes32 r, 
        bytes32 s
    ) 
        external
        payable
        checkLimits(amount) 
        nonReentrant 
    {
        // Check for the valid destimation wallet
        require(to != address(0), "Invalid wallet");

        // Check for non zero value for the amount is not needed as the Signature will not be generated for zero amount

        //compose the message which was signed
        bytes32 message = prefixed(
            keccak256(
                abi.encodePacked(
                    "__conversionIn",
                    amount, 
                    _msgSender(), 
                    conversionId, 
                    this
                )
            )
        );

        // check that the signature is from the authorizer
        require(ecrecover(message, v, r, s) == _conversionAuthorizer, "Invalid request or signature");

        //check for replay attack (message signature can be used only once)
        require(! _usedSignatures[message], "Signature has already been used");
        _usedSignatures[message] = true;

        // Check for the supply
        require(IERC20(_token).totalSupply() + amount <= _maxSupply, "Invalid Amount");

        if (commissionSettings.commissionIsEnabled) {
            if (commissionSettings.commissionType == CommissionType.NativeCurrency) {
                _checkPayedCommissionInNative();

                (bool success, ) = _token.call(abi.encodeWithSelector(MINT_SELECTOR, to, amount));
                require(success, "ConversionIn Failed");
            } else {
                (bool mintSuccess, ) = _token.call(abi.encodeWithSelector(MINT_SELECTOR, address(this), amount));
                require(mintSuccess, "Mint & ConversionIn Failed");

                amount -= _takeCommissionInTokenInput(amount);
                require(amount > 0, "Invalid amount after commission deduction");

                (bool transferSuccess, ) = _token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount));
                require(transferSuccess, "Transfer & ConversionIn Failed");
            }
        } else {
            (bool success, ) = _token.call(abi.encodeWithSelector(MINT_SELECTOR, to, amount));
            require(success, "ConversionIn Failed");
        }

        emit ConversionIn(to, conversionId, amount);
    }

    /// builds a prefixed hash to mimic the behavior of ethSign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function getconversionAuthorizer() external view returns(address) {
        return _conversionAuthorizer;
    }

    function getConversionConfigurations() external view returns(uint256,uint256,uint256) {
        return(_perTxnMinAmount, _perTxnMaxAmount, _maxSupply);
    }

}
