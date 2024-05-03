const { expect } = require("chai");
const { ethers } = require("hardhat");
const { formatBytes32String } = require("@ethersproject/strings");
const { arrayify, splitSignature } = require("@ethersproject/bytes");
var ethereumjsabi = require('ethereumjs-abi')
const Buffer = require('buffer').Buffer;


describe("TokenConversionManager without commission", function () {
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
            0, // convertTokenPercentage
            0, // commissionType
            0, // fixedTokenCommission
            10000000000,  // fixedNativeTokenCommissionLimit
            0, // fixedNativeTokenCommission
            commissionReceiver.getAddress() //commissionReceiver
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });
    
    it("Should handle token conversionOut correctly without commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionOut = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
        await converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )
        
        expect(BigInt(initBalanceBeforeConversionOut-amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
    }); 

    it("Should handle token conversionIn correctly without commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionIn = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )
        expect(BigInt(initBalanceBeforeConversionIn+amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
    }); 
});

describe("TokenConversionManager with percentage tokens commission", function () {
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
            true, // commissionIsEnabled,
            1, // convertTokenPercentage
            0, // commissionType
            0, // fixedTokenCommission
            10000000000,  // fixedNativeTokenCommissionLimit
            0, // fixedNativeTokenCommission
            commissionReceiver.getAddress() //commissionReceiver
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });
    
    it("Should handle token conversionOut correctly with percentage tokens commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionOut = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
        await converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )
        expect(BigInt(initBalanceBeforeConversionOut-amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(amount/100*1)).to.equal(BigInt(await token.balanceOf(commissionReceiver.getAddress())));
    }); 

    it("Should handle token conversionIn correctly with percentage tokens commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionIn = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )
        expect(BigInt(initBalanceBeforeConversionIn+amount-(amount/100*1))).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(amount/100*1)).to.equal(BigInt(await token.balanceOf(commissionReceiver.getAddress())));
    }); 
});

describe("TokenConversionManager with fix amount tokens commission", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;
    const fixedNativeTokenCommission_ = 200
    const fixedTokenCommission_ = 100

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
            true, // commissionIsEnabled,
            0, // convertTokenPercentage
            1, // commissionType
            fixedNativeTokenCommission_, //  fixedNativeTokenCommission
            10000000000,  // fixedNativeTokenCommissionLimit
            fixedTokenCommission_, // fixedTokenCommission
            commissionReceiver.getAddress() //commissionReceiver
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });
    
    it("Should handle token conversionOut correctly with fix amount tokens commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionOut = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
        await converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        );

  
        console.log(await token.balanceOf(await commissionReceiver.getAddress()))
        console.log("holder balance: ",await token.balanceOf(await tokenHolder.getAddress()))

        expect(BigInt(initBalanceBeforeConversionOut-amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(fixedTokenCommission_)).to.equal(BigInt(await token.balanceOf(await commissionReceiver.getAddress())));
    }); 

    it("Should handle token conversionIn correctly with fix amount tokens commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionIn = 1000000000000;
                                           // 10000000000 

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )

        expect(BigInt(initBalanceBeforeConversionIn+(amount-fixedTokenCommission_))).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(fixedTokenCommission_)).to.equal(BigInt(await token.balanceOf(commissionReceiver.getAddress())));
    }); 
});

describe("TokenConversionManager with commission in native currency", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;
    const fixedNativeTokenCommission_ = 200
    const fixedTokenCommission_ = 100

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
            true, // commissionIsEnabled,
            0, // convertTokenPercentage
            2, // commissionType
            fixedNativeTokenCommission_, // fixedNativeTokenCommission
            10000000000,  // fixedNativeTokenCommissionLimit
            fixedTokenCommission_, // fixedTokenCommission
            commissionReceiver.getAddress() //commissionReceiver
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });
    
    it("Should handle token conversionOut correctly with commission in native currency", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionOut = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
       
        await converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s,{value: fixedNativeTokenCommission_}
        )
        console.log(await ethers.provider.getBalance(await converter.getAddress()))

        expect(BigInt(initBalanceBeforeConversionOut-amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(fixedNativeTokenCommission_))
            .to.equal(
                BigInt(
                    await ethers.provider.getBalance(
                        await converter.getAddress()
                    )
                )
            );
    }); 

    it("Should handle token conversionIn correctly with commission in native currency", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionIn = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s, {value: fixedNativeTokenCommission_}
        )
        console.log(await ethers.provider.getBalance(await converter.getAddress()))

        expect(BigInt(initBalanceBeforeConversionIn+amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(fixedNativeTokenCommission_))
            .to
            .equal(
                BigInt(
                    await ethers.provider.getBalance(
                        await converter.getAddress()
                    )
                )
            );
    }); 

    // TODO: Add test for send native currency commission
    it("Should handle correctly send commission in native currency to commission receiver", async function () {
        // converter.sendNativeCurrencyCommission()
    });

    // TODO: Add test for claim native currency commission
    it("Should handle correctly claim commission in native currency by commission receiver", async function () {
        // converter.claimNativeCurrencyCommission()
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
        const token = await Token.deploy("SingularityNET Token", "AGIX");
       
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

    it("Administrative Operation - Change Commission receiver", async function () {
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