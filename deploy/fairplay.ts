import { Deployer } from "@matterlabs/hardhat-zksync";
import type { HardhatRuntimeEnvironment } from "hardhat/types";
import { Wallet } from "zksync-ethers";
import dotenv from "dotenv";

dotenv.config();

export default async function (hre: HardhatRuntimeEnvironment) {
  // Initialize the wallet.
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY as string);

  // Create deployer object and load the artifact of the contract we want to deploy.
  const deployer = new Deployer(hre, wallet);

  // Load contract
  const artifact = await deployer.loadArtifact("FairplayPredictionMarket");

  const fairplayContract = await deployer.deploy(artifact, []);

  // Show the contract info.
  console.log(
    `${
      artifact.contractName
    } was deployed to ${await fairplayContract.getAddress()}`
  );
}
