# Installation

Recommended using WSLv2/Linux/MacOS with LTS Node >= 18 & NPM >= 10 version

# Functionality

1. A contract is needed to burn and mint tokens as part of the bridge between blockchains.

2. The contract can take a commission in tokens and in ETH

Attention: Also, the commission is distributed between the two recipients in a set proportion of the amount of the commission charged

* % of conversion amount

* fix tokens commission for each amount of conversion

* fix ETH amount for each conversion regardless of the amount

3. Contract allowed to change any settings: commission receivers, value of commision, min, max amount of conversion, etc

A detailed description of the contract's capabilities and mechanics of its use can be found in the [document](https://docs.google.com/document/d/1eyqZTU7vKpZ077GCq9VA9RCwvlW_M6825YjYtDXvMbE/edit?usp=sharing).


# Technical requirements


##  Project components

###  `Token Conversion Manager` Contract

The TokenConversionManager contract manages token conversions between Ethereum and non-Ethereum networks with signature verification. Signature is received from backend service and is used in order to prevent replay attacks. Key functionalities include updating authorizer address (backend service address actually) and configurations, and executing conversions in and out.

#### Key-functions:
- **constructor**
  - **Description**: Initializes the contract with token address, commission settings, and sets the conversion authorizer to the deployer.

- **conversionOut**
  - **Parameters**: `uint256 amount, bytes32 conversionId, uint8 v, bytes32 r, bytes32 s`
  - **Description**: Converts tokens from Ethereum to non Ethereum network. The tokens which needs to be convereted will be burned on the Ethereum network. The conversion authorizer needs to provide the signature to call this function.

- **conversionIn**
  - **Parameters**: `address to, uint256 amount, bytes32 conversionId, uint8 v, bytes32 r, bytes32 s`
  - **Description**: Converts tokens in (mints them) after verifying the signature and preventing replay attacks.

- **updateAuthorizer**
  - **Parameters**: `address newAuthorizer`
  - **Description**: Updates the conversion authorizer address. Only callable by the contract owner.

- **updateConfigurations**
  - **Parameters**: `uint256 perTxnMinAmount, uint256 perTxnMaxAmount, uint256 maxSupply`
  - **Description**: Updates the conversion configuration limits. Only callable by the contract owner.

- **getconversionAuthorizer**
  - **Returns**: `address`
  - **Description**: Returns the current conversion authorizer address.

- **getConversionConfigurations**
  - **Returns**: `(uint256, uint256, uint256)`
  - **Description**: Returns the current conversion configuration limits.

</br>

#### State variables:

- **_conversionAuthorizer**
  - **Type**: `address`
  - **Description**: Stores the address of the entity authorized to approve conversions.

- **MINT_SELECTOR, BURN_SELECTOR, TRANSFER_SELECTOR**
  - **Type**: `bytes4`
  - **Description**: Constants storing function selectors for minting, burning, and transferring tokens.

- **_usedSignatures**
  - **Type**: `mapping (bytes32 => bool)`
  - **Description**: Tracks used conversion signatures to prevent replay attacks.

- **_perTxnMinAmount, _perTxnMaxAmount, _maxSupply**
  - **Type**: `uint256`
  - **Description**: Configurations for minimum and maximum transaction amounts and maximum total supply.


###  `Commission` Contract

The `Commission` contract module manages commission settings and calculations for a bridge contract. It includes functionality for enabling/disabling commissions, calculating different types of commissions, and handling commission transfers.

#### Key-functions:

- **constructor**
  - **Parameters**: Various commission settings
  - **Description**: Initializes the commission settings.

- **disableCommission**
  - **Description**: Disables the commission. Only callable by the contract owner.

- **updateCommissionConfiguration**
  - **Parameters**: Various commission settings
  - **Description**: Updates the commission configuration.Only callable by the contract owner.

- **updateReceiverCommission**
  - **Parameters**: `address newReceiverCommission`
  - **Description**: Updates the receiver commission address. Only callable by the contract owner.

- **updateBridgeOwner**
  - **Parameters**: `address newBridgeOwner`
  - **Description**: Updates the bridge owner commission address. Only callable by the contract owner.

- **claimNativeCurrencyCommission**
  - **Description**: Claims the native currency commission. Only callable by bridge owner or commission receiver addresses

- **getCommissionReceiverAddresses**
  - **Returns**: `(address, address)`
  - **Description**: Returns bridge owner and commission receiver addresses

- **getCommissionSettings**
  - **Returns**: Various commission settings
  - **Description**: Returns the current commission settings.

- **_takeCommissionInTokenOutput**
  - **Parameters**: `uint256 amount`
  - **Description**: Takes a commission in tokens during conversion out.

- **_takeCommissionInTokenInput**
  - **Parameters**: `uint256 amount`
  - **Description**: Takes a commission in tokens during conversion in.

- **_calculateCommissionInToken**
  - **Parameters**: `uint256 amount`
  - **Description**: Calls `_calculateCommissionBridgeOwnerProportion` and returns commission amount for bridge owner and the whole sum of commission.

- **_calculateCommissionBridgeOwnerProportion**
  - **Parameters**: `uint256 amount`
  - **Description**: Calculates the bridge owner's proportion of the commission.


</br>

#### State variables:

- **ONE_HUNDRED, ONE_THOUSAND**
  - **Type**: `uint256`
  - **Description**: Constants for percentage calculations.

- **FIXED_NATIVE_TOKEN_COMMISSION_LIMIT**
  - **Type**: `uint256`
  - **Description**: Immutable limit for fixed native token commission.

- **commissionSettings**
  - **Type**: `struct CommissionSettings`
  - **Description**: Stores commission settings including percentages, proportions, and addresses.

- **_token**
  - **Type**: `address`
  - **Description**: Address of the token contract.

- **TRANSFERFROM_SELECTOR, MINT_SELECTOR, TRANSFER_SELECTOR**
  - **Type**: `bytes4`
  - **Description**: Constants storing function selectors for token operations.


##  Technologies used in the project
 - Solidity - smart contracts' language
 - Hardhat - framework for testing smart contracts

##  Architectural design
 
<p align="center">
    <img src="./schemes/architecture.png"></img>
</p>


## Installation dependencies
```bash
npm install
```

## Run Tests
```bash
npx hardhat test --no-compile
```

## Run deploy !OUTDATED!
```bash
npx hardhat run scripts/deploy.js --network <network from config>
```

## Recognize contract size
```bash
npx hardhat size-contracts
```