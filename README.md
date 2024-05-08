A detailed description of the contract's capabilities and mechanics of its use can be found in the [document](https://docs.google.com/document/d/1eyqZTU7vKpZ077GCq9VA9RCwvlW_M6825YjYtDXvMbE/edit?usp=sharing).

## Installation

Recommended using WSLv2 with LTS Node & NPM version

### Installation dependencies
```bash
npm install
```

### Compile contracts
```bash
npx hardhat compile
```

### Run Tests
```bash
npx hardhat test
```

### Run deploy
```bash
npx hardhat run scripts/deploy.js --network <network from config>
```

### Recognize contract size
```bash
npx hardhat size-contracts
```
