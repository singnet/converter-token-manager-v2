const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TokenConversionManager", function () {
    let authorizer, tokenHolder, commissionReceiver;
    let token, converter;

    beforeEach(async () => {
        [authorizer, tokenHolder, commissionReceiver] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        await token.deployed();
        
        const TokenConversionManager = await ethers.getContractFactory("TokenConversionManager");
        converter = await TokenConversionManager.deploy(
            token.address, 
            false, 
            0, 
            0, 
            0, 
            0, 
            0,
            commissionReceiver.address
        );
        await manager.deployed();
    });
    
    
    it("should handle token conversions correctly", async function () {

        await token.connect(tokenHolder).approve(manager.address, amount);

        const amount = 500;
        const messageHash = ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, tokenHolder.address, ethers.utils.formatBytes32String("conversionId1"), converter.address]
        ));
        
        const messageHashBinary = ethers.utils.arrayify(messageHash);
        const signature = await authorizer.signMessage(messageHashBinary);
        const { v, r, s } = ethers.utils.splitSignature(signature);
        
        await expect(manager.connect(tokenHolder).conversionOut(
            amount,
            ethers.utils.formatBytes32String("conversionId1"),
            v, r, s
        )).to.emit(manager, "ConversionOut");

        expect(finalBalanceTokenHolder).to.equal(initialBalanceTokenHolder.sub(amount));
        expect(finalBalanceManager).to.equal(initialBalanceManager.add(amount));

    });
});