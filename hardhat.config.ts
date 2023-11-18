import dotenv from 'dotenv';
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      { version: "0.8.19", settings: {} },
      { version: "0.8.9", settings: {} },
    ]
  },
  networks: {
    hardhat: {
      chainId: 1,
      initialBaseFeePerGas: 0,
      forking: {
        url: process.env.AlchemyApiEndpoint as string,
        blockNumber: 18070582
      }
    }
  }
};

export default config;
