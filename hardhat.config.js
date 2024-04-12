require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");
const fs = require('fs');

require('dotenv').config({ path: '.env'});

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    }
  },
};