const { expect } = require("chai");
const { ethers } = require("hardhat");
const {formatBytes32String} = require("@ethersproject/strings");
const {arrayify, splitSignature} = require("@ethersproject/bytes");


describe("TokenConversionManager", function () {
    let authorizer, tokenHolder, commissionReceiver;
    let token, converter

    const amount = 14;

    beforeEach(async () => {
        [authorizer, tokenHolder, commissionReceiver] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
       
        await token.mint(tokenHolder.address, 10000);       
        
        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManager");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), 
            false, 
            0, 
            0, 
            0, 
            0, 
            0,
            commissionReceiver.address
        );
    
        await converter.updateConfigurations(10, 20, 100)
       
    });
    
    
    it("should handle token conversions correctly", async function () {

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);

        const messageHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, tokenHolder.address, 
            formatBytes32String("conversionId1"), 
            await converter.getAddress()]
        ));

        const messageHashBinary = arrayify(messageHash)
        const signature = await authorizer.signMessage(messageHashBinary);
        const { v, r, s } = splitSignature(signature)
        

        await converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId1"),
            v, r, s
        )
      //  )).to.emit(converter, "ConversionOut");

        expect(finalBalanceTokenHolder).to.equal(initialBalanceTokenHolder.sub(amount));
        expect(finalBalanceconverter).to.equal(initialBalanceconverter.add(amount));

    });
});