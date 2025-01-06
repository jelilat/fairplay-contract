import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

import "@matterlabs/hardhat-zksync";

const config: HardhatUserConfig = {
  solidity: "0.8.28",

  zksolc: {
    version: "latest",
    settings: {},
  },

  networks: {
    lensTestnet: {
      chainId: 37111,
      ethNetwork: "sepolia",
      url: "https://rpc.testnet.lens.dev",
      verifyURL:
        "https://block-explorer-verify.testnet.lens.dev/contract_verification",
      zksync: true,
    },

    hardhat: {
      zksync: true,
    },
  },
};

export default config;
