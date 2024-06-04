const { expect } = require("chai");
const { ethers } = require("hardhat");
const { formatBytes32String } = require("@ethersproject/strings");
const { arrayify, splitSignature } = require("@ethersproject/bytes");
var ethereumjsabi = require('ethereumjs-abi')
const Buffer = require('buffer').Buffer;


describe("TokenConversionManagerV2 without commission", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer,
          bridgeOwner
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            false, // commissionIsEnabled,
            0,
            100,
            100000000, // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
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
        expect(BigInt(0)).to.equal(BigInt(await token.balanceOf(await commissionReceiver.getAddress())));
        expect(BigInt(0)).to.equal(BigInt(await token.balanceOf(await bridgeOwner.getAddress())));
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
        expect(BigInt(0)).to.equal(BigInt(await token.balanceOf(await commissionReceiver.getAddress())));
        expect(BigInt(0)).to.equal(BigInt(await token.balanceOf(await bridgeOwner.getAddress())));
    });

    it("Should be revert token conversionIn correctly while token paused", async function () {

        const [ authorizer ] = await ethers.getSigners();
        // const initBalanceBeforeConversionIn = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress());

        await token.pause();

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await expect(converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "ConversionFailed")
    }); 
});

describe("TokenConversionManagerV2 with percentage tokens commission", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;

    // constructor arguments      
    const receiverCommissionProportion = 20
    const bridgeOwnerCommissionProportion = 80

    // enableAndUpdatePercentageTokensCommission arguments
    const convertTokenPercentage = 10
    const offsetPoints = 100;


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
    
        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            true, // commissionIsEnabled,
            receiverCommissionProportion,
            bridgeOwnerCommissionProportion,
            10000000000,  // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())

        await converter.enableAndUpdatePercentageTokensCommission(convertTokenPercentage, offsetPoints);
    });

    it("Should revert incorrect setup commission percentage limit exceeded", async function () {

        let [ newOwnerContract ] = await ethers.getSigners();

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        let badConvertTokenPercentage = 100;
        let badOffsetPoints = 10;

        await converter.disableCommission();

        await expect(
            converter.connect(newOwnerContract).enableAndUpdatePercentageTokensCommission(badConvertTokenPercentage, badOffsetPoints)
        ).to.be.revertedWithCustomError(converter, "PercentageLimitExceeded");
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
        expect(BigInt((amount*convertTokenPercentage/offsetPoints)*receiverCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(commissionReceiver.getAddress())));
        expect(BigInt((amount*convertTokenPercentage/offsetPoints)*bridgeOwnerCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(bridgeOwner.getAddress())));
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
        expect(BigInt(initBalanceBeforeConversionIn+amount-(amount*convertTokenPercentage/offsetPoints))).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt((amount*convertTokenPercentage/offsetPoints)*receiverCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(commissionReceiver.getAddress())));
        expect(BigInt((amount*convertTokenPercentage/offsetPoints)*bridgeOwnerCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(bridgeOwner.getAddress())));
    }); 

    it("Should handle token conversionIn correctly revert conversion by anavailable mint tokens for charge commission", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionIn = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        await token.pause();

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await expect(converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "ConversionMintFailed");
    }); 
});

describe("TokenConversionManagerV2 with fix amount tokens commission", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;
    // const fixedNativeTokenCommission_ = 200
    const fixedTokenCommission_ = 100
    const receiverCommissionProportion = 20
    const bridgeOwnerCommissionProportion = 80


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

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address token, 
            true, // commissionIsEnabled,
            receiverCommissionProportion, 
            bridgeOwnerCommissionProportion,
            10000000000,  // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())

        await converter.enableAndUpdateFixedTokensCommission(fixedTokenCommission_);
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

        expect(BigInt(initBalanceBeforeConversionOut - amount)).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(fixedTokenCommission_*receiverCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(await commissionReceiver.getAddress())));
        expect(BigInt(fixedTokenCommission_*bridgeOwnerCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(await bridgeOwner.getAddress())));
    }); 

    it("Should handle token conversionIn correctly with fix amount tokens commission", async function () {

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

        expect(BigInt(initBalanceBeforeConversionIn + (amount - fixedTokenCommission_))).to.equal(BigInt(await token.balanceOf(await tokenHolder.getAddress())));
        expect(BigInt(fixedTokenCommission_*receiverCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(await commissionReceiver.getAddress())));
        expect(BigInt(fixedTokenCommission_*bridgeOwnerCommissionProportion/100)).to.equal(BigInt(await token.balanceOf(await bridgeOwner.getAddress())));
    }); 
});

describe("TokenConversionManagerV2 with commission in native currency", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;
    const fixedNativeTokenCommission_ = 200 // wei
    // const fixedTokenCommission_ = 100

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          bridgeOwner,
          newAuthorizer
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");

        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), 
            true, // commissionIsEnabled,
            50, // receiverCommissionProportion
            50, // bridgeOwnerCommissionProportion
            1000000000000000,  // fixedNativeTokenCommissionLimit
            await commissionReceiver.getAddress(),
            await bridgeOwner.getAddress()
        )

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())

        await converter.enableAndUpdateFixedNativeTokensCommission(fixedNativeTokenCommission_);
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
            v, r, s, {value: fixedNativeTokenCommission_}
        )

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

    it("Should handle correctly claim commission in native currency by commission receiver", async function () {

        const [ authorizer, intruder ] = await ethers.getSigners();

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
            v, r, s, { value: fixedNativeTokenCommission_}
        )

        const balanceBeforeClaimCommission = await ethers.provider.getBalance(await converter.getAddress());

        await converter.connect(commissionReceiver).claimFixedNativeTokensCommission();

        expect(BigInt(balanceBeforeClaimCommission)-BigInt(fixedNativeTokenCommission_))
        .to
        .equal(BigInt(await ethers.provider.getBalance(await converter.getAddress())));

        await expect(
            converter.connect(commissionReceiver).claimFixedNativeTokensCommission()
        ).to.be.revertedWithCustomError(converter, "NotEnoughBalance");

        await expect(
            converter.connect(intruder).claimFixedNativeTokensCommission()
        ).to.be.revertedWithCustomError(converter, "UnauthorizedCommissionReceiver");
    }); 
});

describe("TokenConversionManagerV2 with commission in native currency reverts", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;
    const fixedNativeTokenCommission_ = 200 // wei
    // const fixedTokenCommission_ = 100

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          bridgeOwner,
          newAuthorizer
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");

        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), 
            true, // commissionIsEnabled,
            50, // receiverCommissionProportion
            50, // bridgeOwnerCommissionProportion
            1000000000000000,  // fixedNativeTokenCommissionLimit
            await commissionReceiver.getAddress(),
            await bridgeOwner.getAddress()
        )

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });

    it("Should revert at enabling zero fixed native token commission", async function () {
        let [ newOwnerContract ] = await ethers.getSigners();

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();


        await expect(
            converter.connect(newOwnerContract).enableAndUpdateFixedNativeTokensCommission(0)
        ).to.be.revertedWithCustomError(converter, "EnablingZeroFixedNativeTokenCommission");

    });

    it("Should handle token conversionOut correctly revert w/o charged native commission", async function () {

        const [ authorizer ] = await ethers.getSigners();

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
        
       
        await expect(converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithPanic(0x12)
    }); 

    it("Should handle token conversionIn correctly revert w/o charged native commission", async function () {

        const [ authorizer ] = await ethers.getSigners();

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

        await expect(converter.connect(tokenHolder).conversionIn(
            tokenHolder.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithPanic(0x12)
    });
});

describe("TokenConversionManagerV2 - Check unauthorized and invalid operations", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer,
          bridgeOwner
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            false, // commissionIsEnabled,
            0,
            100,
            100000000, // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        );

        await converter.updateConfigurations(1000000000, 1000000000000000, 10000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });
  
    it("Should handle token conversionOut correctly revert unauthorized operation", async function () {
    
        const [ authorizer, intruder ] = await ethers.getSigners();

        await token.mint(intruder.address, 100000000000);  // 1k 

        await token.connect(intruder).approve(await converter.getAddress(), 1);
        await converter.updateAuthorizer(await authorizer.getAddress())
        
        let fakeAmount = 10000000000;
        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", fakeAmount, await intruder.getAddress(),
            "0x" + Buffer.from("Attack").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await intruder.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await expect(
            converter.connect(intruder).conversionOut(
                fakeAmount,
                formatBytes32String("Attack"),
                v, r, s
            )
        ).to.be.revertedWithCustomError(converter, "InvalidRequestOrSignature");
    }); 

    it("Should handle token conversionIn correctly revert unauthorized operation", async function () {

        const [ authorizer, intruder ] = await ethers.getSigners();

        await converter.updateAuthorizer(await authorizer.getAddress())

        let fakeAmount = 10000000000;

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", fakeAmount, await intruder.getAddress(),
            "0x" + Buffer.from("Attack").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await intruder.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await expect(converter.connect(intruder).conversionIn(
            tokenHolder.getAddress(),
            fakeAmount,
            formatBytes32String("Attack"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "InvalidRequestOrSignature");
    });

    it("Should handle token conversionOut correctly revert violation of tx amount limits", async function () {
    
        const [ authorizer, user ] = await ethers.getSigners();

        await token.mint(user.getAddress(), 1000000000000000);  // 1k

        await token.connect(user).approve(await converter.getAddress(), 1000000000000000);
        await converter.updateAuthorizer(await authorizer.getAddress())
        
        let amount = 100000000;
        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await user.getAddress(),
            "0x" + Buffer.from("ConversioId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await expect(
            converter.connect(user).conversionOut(
                amount,
                formatBytes32String("ConversioId"),
                v, r, s
            )
        ).to.be.revertedWithCustomError(converter, "ViolationOfTxAmountLimits");
    });

    it("Should handle token conversionIn correctly revert minting more than max supply", async function () {

        const [ authorizer, user ] = await ethers.getSigners();

        await converter.updateAuthorizer(await authorizer.getAddress())

        let amount = 100000000000000;

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionIn", amount, await user.getAddress(),
            "0x" + Buffer.from("ConversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);

        await expect(converter.connect(user).conversionIn(
            user.getAddress(),
            amount,
            formatBytes32String("ConversionId"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "MintingMoreThanMaxSupply");
    });

    it("Should handle token conversionOut correctly revert operations with used signature", async function () {

        const [ authorizer, user ] = await ethers.getSigners();
        await token.mint(user.getAddress(), 1000000000);  // 1k
        let amount = 1000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())


        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await user.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
        await converter.connect(user).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )

        await expect(converter.connect(user).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "UsedSignature");

        await token.connect(user).burn(
            1000000000
        )
    });

    it("Should handle token conversionIn correctly revert operations with used signature", async function () {

        const [ authorizer, user ] = await ethers.getSigners();
        await token.mint(user.getAddress(), 100000000);  // 1k
        let amount = 1000000000;

        await token.connect(user).approve(await converter.getAddress(), amount);
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
            user.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        );

        await expect(converter.connect(user).conversionIn(
            user.getAddress(),
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "UsedSignature");
    }); 
});

describe("TokenConversionManagerV2", function () {
    let authorizer, tokenHolder, commissionReceiver, newAuthorizer;
    let token, converter;

    const amount = 10000000000;

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer,
          bridgeOwner
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            false, // commissionIsEnabled,
            0,
            100,
            100000000, // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });
  
    it("Should handle token conversionOut correctly revert while token paused", async function () {

        const [ authorizer ] = await ethers.getSigners();
        const initBalanceBeforeConversionOut = 1000000000000;

        await token.connect(tokenHolder).approve(await converter.getAddress(), amount);
        await converter.updateAuthorizer(await authorizer.getAddress())

        await token.pause();

        const messageHash = ethereumjsabi.soliditySHA3(
            ["string", "uint256", "address", "bytes32", "address"],
            ["__conversionOut", amount, await tokenHolder.getAddress(),
            "0x" + Buffer.from("conversionId").toString('hex'),
            await converter.getAddress()]
        );
    
        const msg = arrayify(messageHash);
        const signature = await authorizer.signMessage(msg);

        const { v, r, s } = splitSignature(signature);
        
        await expect(converter.connect(tokenHolder).conversionOut(
            amount,
            formatBytes32String("conversionId"),
            v, r, s
        )).to.be.revertedWithCustomError(converter, "ConversionFailed");
    }); 
});

describe("TokenConversionManagerV2 - Administrative functionality", function () {

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer,
          bridgeOwner,
          intruder
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            false, // commissionIsEnabled,
            0,
            100,
            100000000, // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });

    it("Administrative Operation - Update Conversion Authorizer", async function () {
        await converter.updateAuthorizer(await newAuthorizer.getAddress());
        let updatedAuthorizer = await converter.getConversionAuthorizer();
        expect(updatedAuthorizer).to.equal(await newAuthorizer.getAddress());

        await expect(
            converter.connect(intruder).updateAuthorizer(
                await newAuthorizer.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Administrative Operation - Update Conversion Configuration", async function () {

        let [ newOwnerContract ] = await ethers.getSigners();

        let minimum = 100;
        let maximum = 500;
        let maxSupply = 1000;
        await converter.updateConfigurations(minimum, maximum, maxSupply);
        let updatedConfigurations = await converter.getConversionConfigurations();
        expect(updatedConfigurations[0]).to.equal(BigInt(minimum));
        expect(updatedConfigurations[1]).to.equal(BigInt(maximum));
        expect(updatedConfigurations[2]).to.equal(BigInt(maxSupply));

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        let badMinimum = 500;
        let badMaximum = 100;
        let badMaxSupply = 0;

        await expect(
            converter.connect(newOwnerContract).updateConfigurations(badMinimum, badMaximum, badMaxSupply)
        ).to.be.revertedWithCustomError(converter, "InvalidUpdateConfigurations");

        await expect(
            converter.connect(intruder).updateConfigurations(
                minimum, maximum, maxSupply
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Administrative Operation - Update commission split proportions", async function () {
        let newCommissionReceiverProportion = 10;
        let newBridgeOwnerProportion = 90;

        let [ newOwnerContract ] = await ethers.getSigners();
        // update receiver
        await converter.updateCommissionProportions(
            newCommissionReceiverProportion,
            newBridgeOwnerProportion
        );

        let updatedReceivers = await converter.getCommissionSettings();
        expect(updatedReceivers[1]).to.equal(newCommissionReceiverProportion);
        expect(updatedReceivers[2]).to.equal(newBridgeOwnerProportion);

        await expect(
            converter.connect(intruder).updateBridgeOwner(
                await intruder.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        await expect(
            converter.connect(newOwnerContract).updateCommissionProportions(
                100,
                100
            )
        ).to.be.revertedWithCustomError(converter, "InvalidProportionSum");
    });

    it("Administrative Operation - Update Сommission Receiver", async function () {

        let [ receiverForUpdate, newOwnerContract ] = await ethers.getSigners();

        await converter.updateReceiverCommission(await receiverForUpdate.getAddress());

        let receiversData = await converter.getCommissionReceiverAddresses();
        expect(receiversData[0]).to.equal(await receiverForUpdate.getAddress());

        await expect(
            converter.connect(intruder).updateReceiverCommission(
                await intruder.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        await converter.connect(newOwnerContract).updateReceiverCommission(
                "0x0000000000000000000000000000000000000000"
        )
    });

    it("Administrative Operation - Update Bridge Owner Сommission Receiver", async function () {

        let [ newBridgeOwnerReceiver, newOwnerContract ] = await ethers.getSigners();

        await converter.updateBridgeOwner(await newBridgeOwnerReceiver.getAddress());

        let receiversData = await converter.getCommissionReceiverAddresses();
        expect(receiversData[1]).to.equal(await newBridgeOwnerReceiver.getAddress());

        await expect(
            converter.connect(intruder).updateBridgeOwner(
                await intruder.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();
        
        await expect(
            converter.connect(newOwnerContract).updateBridgeOwner(
                "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWithCustomError(converter, "ZeroAddress");
    });
});

describe("Commission Module - Administrative functionality", function () {

    beforeEach(async () => {
        [
          authorizer,
          tokenHolder,
          commissionReceiver,
          newAuthorizer,
          bridgeOwner,
          intruder
        ] = await ethers.getSigners();
        
        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        converter = await TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            false, // commissionIsEnabled,
            0,
            100,
            100000000, // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        );

        await converter.updateConfigurations(100000000, 100000000000, 1000000000000000) //!! min 1 max 1000 maxs 10000
        await converter.updateAuthorizer(await authorizer.getAddress())
        await token.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", converter.getAddress())
    });

    it("Administrative Operation - Update commission split proportions", async function () {
        let newCommissionReceiverProportion = 10;
        let newBridgeOwnerProportion = 90;

        let [ newOwnerContract ] = await ethers.getSigners();
        // update receiver
        await converter.updateCommissionProportions(
            newCommissionReceiverProportion,
            newBridgeOwnerProportion
        );

        let updatedReceivers = await converter.getCommissionSettings();
        expect(updatedReceivers[1]).to.equal(newCommissionReceiverProportion);
        expect(updatedReceivers[2]).to.equal(newBridgeOwnerProportion);

        await expect(
            converter.connect(intruder).updateBridgeOwner(
                await intruder.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        await expect(
            converter.connect(newOwnerContract).updateCommissionProportions(
                100,
                100
            )
        ).to.be.revertedWithCustomError(converter, "InvalidProportionSum");
    });

    it("Administrative Operation - Update Сommission Receiver", async function () {

        let [ receiverForUpdate, newOwnerContract ] = await ethers.getSigners();

        await converter.updateReceiverCommission(await receiverForUpdate.getAddress());

        let receiversData = await converter.getCommissionReceiverAddresses();
        expect(receiversData[0]).to.equal(await receiverForUpdate.getAddress());

        await expect(
            converter.connect(intruder).updateReceiverCommission(
                await intruder.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        await converter.connect(newOwnerContract).updateReceiverCommission(
                "0x0000000000000000000000000000000000000000"
        )
    });

    it("Administrative Operation - Update Bridge Owner Сommission Receiver", async function () {

        let [ newBridgeOwnerReceiver, newOwnerContract ] = await ethers.getSigners();

        await converter.updateBridgeOwner(await newBridgeOwnerReceiver.getAddress());

        let receiversData = await converter.getCommissionReceiverAddresses();
        expect(receiversData[1]).to.equal(await newBridgeOwnerReceiver.getAddress());

        await expect(
            converter.connect(intruder).updateBridgeOwner(
                await intruder.getAddress()
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();
        
        await expect(
            converter.connect(newOwnerContract).updateBridgeOwner(
                "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWithCustomError(converter, "ZeroAddress");
    });


    it("Administrative Operation - Should revert incorrect fixed native tokens limit", async function () {

        let [ newBridgeOwnerReceiver, newOwnerContract, intruder ] = await ethers.getSigners();

        await converter.updateBridgeOwner(await newBridgeOwnerReceiver.getAddress());

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();
        
        await expect(
            converter.connect(newOwnerContract).enableAndUpdateFixedNativeTokensCommission(
                "1000000000000000"
            )
        ).to.be.revertedWithCustomError(converter, "ViolationOfFixedNativeTokensLimit");

        await expect(
            converter.connect(intruder).enableAndUpdateFixedNativeTokensCommission(
                1
            )
        ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Administrative Operation - Should correct disable commission", async function () {

        let [ intruder ] = await ethers.getSigners();

        await converter.disableCommission();
    });

    it("Administrative Operation - Should revert incorrect fixed tokens commission setup", async function () {

        let [ newOwnerContract ] = await ethers.getSigners();

        await converter.transferOwnership(await newOwnerContract.getAddress());
        await converter.connect(newOwnerContract).acceptOwnership();

        await converter.connect(newOwnerContract).enableAndUpdateFixedNativeTokensCommission(1)
        
        await expect(
            converter.connect(newOwnerContract).enableAndUpdatePercentageTokensCommission(
                0,100
            )
        ).to.be.revertedWithCustomError(converter, "EnablingZeroTokenPercentageCommission");

        await expect(
            converter.connect(newOwnerContract).enableAndUpdatePercentageTokensCommission(
                100,0
            )
        ).to.be.revertedWithCustomError(converter, "EnablingZeroTokenPercentageCommission");

        // correct enable commission
        converter.connect(newOwnerContract).enableAndUpdatePercentageTokensCommission(
            10,10000
        )
    });

    it("Administrative Operation - Should revert incorrect fixed native limit commission setup at contract deploy", async function () {

        const Token = await ethers.getContractFactory("Token");
        token = await Token.deploy("SingularityNET Token", "AGIX");
        
        await token.mint(tokenHolder.address, 1000000000000);  // 10k      

        const TokenConversionСonverter = await ethers.getContractFactory("TokenConversionManagerV2");
        await expect(TokenConversionСonverter.deploy(
            await token.getAddress(), // address of token to convert
            false, // commissionIsEnabled,
            0,
            100,
            0, // fixedNativeTokenCommissionLimit
            commissionReceiver.getAddress(), 
            bridgeOwner.getAddress()
        )).to.be.revertedWithCustomError(TokenConversionСonverter, "ZeroFixedNativeTokensCommissionLimit");
    });
});