require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-etherscan");
//require("@nomicfoundation/hardhat-verify");

const ONE_KEY = "0x0000000000000000000000000000000000000000000000000000000000000001";
const { INFURA_PROJECT_ID, PRIVATE_KEY } = process.env;

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {},
      },
    ],
  },
  
  networks: {
    hardhat: {
      forking: {
        url:  `https://eth-goerli.g.alchemy.com/v2/UhpuznU9sEL8E-127qaU1-4yuVP9Hy1w`,
        blockNumber: 9499031, //29036648

      },
    },
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/UhpuznU9sEL8E-127qaU1-4yuVP9Hy1w`,
      accounts: [ONE_KEY],
    },
  },
  etherscan:{
    apiKey: "CR4EWIE9X5C5H75C5K3SVP9QW7FZ49PPFN",
  }


};
