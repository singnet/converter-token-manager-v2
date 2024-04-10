async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const conversionManager = await ethers.getContractFactory("TokenConversionManager");
  const deployedConversionManager = await conversionManager.deploy();

  console.log("Deployed token contract address:", await deployedConversionManager.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });