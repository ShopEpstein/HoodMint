// Deploys HoodMintFactory. Run:
//   npx hardhat run scripts/deploy.js --network robinhoodTestnet   (test first!)
//   npx hardhat run scripts/deploy.js --network robinhood
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const bal = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Deployer:", deployer.address);
  console.log("Balance :", hre.ethers.formatEther(bal), "ETH");
  console.log("Network :", hre.network.name, "chainId", (await hre.ethers.provider.getNetwork()).chainId);

  const Factory = await hre.ethers.getContractFactory("HoodMintFactory");
  const factory = await Factory.deploy(deployer.address); // deployer = factory owner
  await factory.waitForDeployment();
  const addr = await factory.getAddress();

  console.log("\n✅ HoodMintFactory deployed:", addr);
  console.log("\nNext:");
  console.log("  1) Put this address in web/index.html  ->  FACTORY_ADDRESS");
  console.log("  2) Verify on Blockscout:");
  console.log(`     npx hardhat verify --network ${hre.network.name} ${addr} ${deployer.address}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
