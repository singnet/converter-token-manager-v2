async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);


  const tokenAddress = "0xTokenAddress";
  const commissionIsEnabled = true;
  const convertTokenPercentage = 30;
  const receiverCommissionProportion = 50;
  const bridgeOwnerCommissionProportion = 50;
  const pointShitfer = 10000;
  const commissionType = 0;
  const fixedNativeTokenCommission = 0;
  const fixedNativeTokenCommissionLimit = 10000000000;
  const fixedTokenCommission = 0;
  const commissionReceiver = "0xCommissionReceiver";
  const bridgeOwner = "0xBridgeOwnerAddress";

  const TokenConversionManager = await ethers.getContractFactory("TokenConversionManagerV2");

  const tokenConversionManager = await TokenConversionManager.deploy(
      tokenAddress,
      commissionIsEnabled,
      convertTokenPercentage,
      receiverCommissionProportion,
      bridgeOwnerCommissionProportion,
      pointShitfer,
      commissionType,
      fixedNativeTokenCommission,
      fixedNativeTokenCommissionLimit,
      fixedTokenCommission,
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