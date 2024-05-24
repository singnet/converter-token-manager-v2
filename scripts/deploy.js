async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);


  const tokenAddress = "0x0";
  const commissionIsEnabled = false;
  const receiverCommissionProportion = 50;
  const bridgeOwnerCommissionProportion = 50;
  const fixedNativeTokenCommissionLimit = 10000000000;
  const commissionReceiver = "0x0";
  const bridgeOwner = "0x0";

  const TokenConversionManager = await ethers.getContractFactory("TokenConversionManagerV2");

  const tokenConversionManager = await TokenConversionManager.deploy(
      tokenAddress,
      commissionIsEnabled,
      receiverCommissionProportion,
      bridgeOwnerCommissionProportion,
      fixedNativeTokenCommissionLimit,
      commissionReceiver,
      bridgeOwner
  );

  console.log("TokenConversionManagerV2 deployed to:", await tokenConversionManager.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
      console.error(error);
      process.exit(1);
  });