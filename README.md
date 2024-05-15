## Installation

Recommended using WSLv2/Linux/MacOS with LTS Node >= 18 & NPM >= 10 version

## Functionality

1. A contract is needed to burn and mint tokens as part of the bridge between blockchains.

2. The contract can take a commission in tokens and in ETH

Attention: Also, the commission is distributed between the two recipients in a set proportion of the amount of the commission charged

* % of conversion amount

* fix tokens commission for each amount of conversion

* fix ETH amount for each conversion regardless of the amount

3. Contract allowed to change any settings: commission receivers, value of commision, min, max amount of conversion, etc

### Installation dependencies
```bash
npm install
```

### Compile contracts
```bash
npx hardhat compile
```

!OUTDATED!
### Run Tests
```bash
npx hardhat test
```

!OUTDATED!
### Run deploy
```bash
npx hardhat run scripts/deploy.js --network <network from config>
```

### Recognize contract size
```bash
npx hardhat size-contracts
```


!OUTDATED! A detailed description of the contract's capabilities and mechanics of its use can be found in the [document](https://docs.google.com/document/d/1eyqZTU7vKpZ077GCq9VA9RCwvlW_M6825YjYtDXvMbE/edit?usp=sharing).