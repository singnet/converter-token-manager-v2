const { expect } = require("chai");
const { ethers } = require("hardhat");
const { formatBytes32String } = require("@ethersproject/strings");
const { arrayify, splitSignature } = require("@ethersproject/bytes");
var ethereumjsabi = require('ethereumjs-abi')

const Buffer = require('buffer').Buffer;


describe("TokenConversionManager", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManager");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address token, 
            false, // commissionIsEnabled,
            1, // convertTokenPercentage
            0, // commissionType
            0, // fixedTokenCommission
            10000000000,  // fixedNativeTokenCommissionLimit
            0, // fixedNativeTokenCommission
            commissionReceiver.getAddress() //commissionReceiver
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
    });
    
    
    it("Should handle token conversions correctly", async function () {

        const [auth] = await ethers.getSigners();

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await auth.getAddress())


        console.log("Auth", await auth.getAddress())
        console.log("TokenHolder", await tokenHolder.getAddress())
  

        /*const messageHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
            [ "uint256" ],
            [ amount ])
        );*/

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", 
            amount, 
            await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId1").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await auth.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
        await converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId1"),
            v, r, s
        )
        const initBalance = 1000000000000;
        expect(BigInt(initBalance-amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
    }); 
});


describe("Administrative functionality", function () {

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer,
          intruder,
          newCommissionReceiver
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
       
        await token.mint(tokenHolder.address, 10000);       
        
        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManager");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), 
            false, // commissionIsEnabled,
            1, // convertTokenPercentage
            0, // commissionType
            0, //fixedNativeTokenCommission
            100000000000,  // fixedNativeTokenCommissionLimit
            0, // fixedTokenCommission
            commissionReceiver.getAddress()
        )
    });

    it("Administrative Operation - Update Conversion Authorizer", async function () {
        await converter.updateAuthorizer(await newAuthorizer.getAddress());
        let updatedAuthorizer = await converter.getconversionAuthorizer();
        expect(updatedAuthorizer).to.equal(await newAuthorizer.getAddress());

        await expect(
            converter.connect(intruder).updateAuthorizer(
                await newAuthorizer.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Administrative Operation - Update Conversion Configuration", async function () {
        let minimum = 100;
        let maximum = 500;
        let maxSupply = 1000;
        await converter.updateConfigurations(minimum, maximum, maxSupply);
        let updatedConfigurations = await converter.getConversionConfigurations();
        expect(updatedConfigurations[0]).to.equal(BigInt(minimum));
        expect(updatedConfigurations[1]).to.equal(BigInt(maximum));
        expect(updatedConfigurations[2]).to.equal(BigInt(maxSupply));

        await expect(
            converter.connect(intruder).updateConfigurations(
                minimum, maximum, maxSupply
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Administrative Operation - Setup Commission Configurations", async function () {

        //
        //PercentageTokens, // commission in percentage tokens
        //FixTokens, // commission in fix value of tokens
        //NativeCurrency // commission in native currency

        let newCommissionIsEnabled = true;
        let newCommissionType = 2;
        let newConvertTokenPercentage = 0; // setup 5% in tokens commission
        let newFixedTokenCommission = 0;
        let newFixedNativeTokenCommission = 1;

        await converter.updateCommissionConfiguration(
            newCommissionIsEnabled,
            newCommissionType,
            newConvertTokenPercentage,
            newFixedTokenCommission,
            newFixedNativeTokenCommission
        );

        let updatedCommissionConfigurations = await converter.getCommissionSettings();
        expect(updatedCommissionConfigurations[0]).to.equal(newCommissionIsEnabled);
        expect(updatedCommissionConfigurations[1]).to.equal(BigInt(newCommissionType));
        expect(updatedCommissionConfigurations[2]).to.equal(BigInt(newConvertTokenPercentage));
        expect(updatedCommissionConfigurations[3]).to.equal(BigInt(newFixedTokenCommission));
        expect(updatedCommissionConfigurations[4]).to.equal(BigInt(newFixedNativeTokenCommission));

        await expect(
            converter.connect(intruder).updateCommissionConfiguration(
                newCommissionIsEnabled,
                0,
                newCommissionType,
                newFixedTokenCommission,
                newFixedNativeTokenCommission
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Administrative Operation - Change commission receiver", async function () {
        let newReceiver = await newCommissionReceiver.getAddress()
        
        // update receiver
        await converter.setCommissionReceiver(
            newReceiver
        );

        let updatedReceiver = await converter.getCommissionReceiverAddress();
        expect(updatedReceiver).to.equal(newReceiver);

        await expect(
            converter.connect(intruder).setCommissionReceiver(
                "0x0792157d69D1ee26c927d8A6E6e88D50D4DC039e"
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

});
