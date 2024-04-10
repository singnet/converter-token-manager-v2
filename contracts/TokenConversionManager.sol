// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./Commission.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TokenConversionManager is Commission, ReentrancyGuard {
    address public conversionAuthorizer; // Authorizer Address for the conversion 

    //already used conversion signature from authorizer in order to prevent replay attack
    mapping (bytes32 => bool) public usedSignatures; 

    // Conversion Configurations
    uint256 public perTxnMinAmount;
    uint256 public perTxnMaxAmount;
    uint256 public maxSupply;

    // Method Declaration
    bytes4 private constant MINT_SELECTOR = bytes4(keccak256("mint(address,uint256)"));

    // Events
    event NewAuthorizer(address conversionAuthorizer);
    event UpdateConfiguration(uint256 perTxnMinAmount, uint256 perTxnMaxAmount, uint256 maxSupply);

    event ConversionOut(address indexed tokenHolder, bytes32 conversionId, uint256 amount);
    event ConversionIn(address indexed tokenHolder, bytes32 conversionId, uint256 amount);


    // Modifiers
    modifier checkLimits(uint256 amount) {
        // Check for min, max per transaction limits
        require(amount >= perTxnMinAmount && amount <= perTxnMaxAmount, "Violates conversion limits");
        _;
    }

    constructor(
        address _token, 
        uint8 _nativeTokenPercentage,
        uint8 _convertTokenPercentage
    ) 
        Commission(_nativeTokenPercentage, _convertTokenPercentage) 
    {
        token = IERC20Burnable(_token);
        conversionAuthorizer = _msgSender(); 
    }

    /**
    * @dev To update the authorizer who can authorize the conversions.
    */
    function updateAuthorizer(address newAuthorizer) external onlyOwner {
        require(newAuthorizer != address(0), "Invalid operator address");

        conversionAuthorizer = newAuthorizer;

        emit NewAuthorizer(newAuthorizer);
    }

    /**
    * @dev To update the per transaction limits for the conversion and to provide max total supply 
    */
    function updateConfigurations(
        uint256 _perTxnMinAmount, 
        uint256 _perTxnMaxAmount, 
        uint256 _maxSupply
    )
        external 
        onlyOwner 
    {
        // Check for the valid inputs
        require(_perTxnMinAmount > 0 && _perTxnMaxAmount > _perTxnMinAmount && _maxSupply > 0, "Invalid inputs");

        // Update the configurations
        perTxnMinAmount = _perTxnMinAmount;
        perTxnMaxAmount = _perTxnMaxAmount;
        maxSupply = _maxSupply;

        emit UpdateConfiguration(_perTxnMinAmount, _perTxnMaxAmount, _maxSupply);
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
        bytes32 s,
        bool commissionInNativeToken
    ) 
        external 
        payable
        checkLimits(amount) 
        nonReentrant 
    {
        // Check for non zero value for the amount is not needed as the Signature will not be generated for zero amount

        // Check for the Balance
        require(token.balanceOf(_msgSender()) >= amount, "Not enough balance");
        
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
        address signAddress = ecrecover(message, v, r, s);
        require(signAddress == conversionAuthorizer, "Invalid request or signature");

        //check for replay attack (message signature can be used only once)
        require(!usedSignatures[message], "Signature has already been used");
        usedSignatures[message] = true;

        // Burn the tokens on behalf of the Wallet
        token.burnFrom(_msgSender(), amount);

        _takeCommission(commissionInNativeToken, amount);

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
        bytes32 s,
        bool commissionInNativeToken
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
        address signAddress = ecrecover(message, v, r, s);
        require(signAddress == conversionAuthorizer, "Invalid request or signature");

        //check for replay attack (message signature can be used only once)
        require( ! usedSignatures[message], "Signature has already been used");
        usedSignatures[message] = true;

        // Check for the supply
        require(token.totalSupply() + amount <= maxSupply, "Invalid Amount");

        // Mint the tokens and transfer to the User Wallet using the Call function
        // token.mint(_msgSender(), amount);

        (bool success, ) = address(token).call(abi.encodeWithSelector(0x4e6ec247, to, amount));

        // In case if the mint call fails
        require(success, "ConversionIn Failed");

        _takeCommission(commissionInNativeToken, amount);

        emit ConversionIn(_msgSender(), conversionId, amount);
    }

    /// builds a prefixed hash to mimic the behavior of ethSign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

}