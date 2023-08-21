const { ethers } = require("hardhat");

const SETTLEMENT = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41";

async function main() {
  const GATOrders = await ethers.getContractFactory("Escrow");
  const orders = await GATOrders.deploy();

  await orders.deployed();

  console.log(`GAT orders deployed to ${orders.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
