require("@nomicfoundation/hardhat-toolbox");

const ONE_KEY = "0x0000000000000000000000000000000000000000000000000000000000000001";
const { INFURA_PROJECT_ID, PRIVATE_KEY } = process.env;

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.4.18",
      },
      {
        version: "0.8.17",
        settings: {},
      },
    ],
  },
  
  networks: {
    hardhat: {
      forking: {
        url:  `https://eth-goerli.g.alchemy.com/v2/ihAB5lCuRIlF0IFJgv0eWbMbbr6Smqzs`,
        blockNumber: 9499031, //29036648

      },
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${INFURA_PROJECT_ID}`,
      accounts: [PRIVATE_KEY ?? ONE_KEY],
    },
  },
};
