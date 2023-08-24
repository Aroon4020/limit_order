const { ethers } = require("hardhat");

async function main() {
  const ESCROW = await ethers.getContractFactory("Escrow");
  const escrow = await ESCROW.deploy("0xdbfa076edbfd4b37a86d1d7ec552e3926021fb97");

  await escrow.deployed();

  console.log(`deployed to ${escrow.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
