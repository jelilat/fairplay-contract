import { expect } from "chai";
import { type WalletClient, createWalletClient, http } from "viem";
import type { GetContractReturnType } from "@nomicfoundation/hardhat-viem/types";
import hre from "hardhat";

describe("FairplayPredictionMarket", () => {
  let fairplay: GetContractReturnType;
  let owner: WalletClient;
  let addr1: WalletClient;
  let addr2: WalletClient;

  beforeEach(async () => {
    [owner, addr1, addr2] = await hre.viem.getWalletClients();
    fairplay = await hre.viem.deployContract("FairplayPredictionMarket");
  });

  describe("Market Creation", () => {
    it("Should create a market", async () => {
      const question = "Will it rain tomorrow?";
      const category = "Weather";
      const endTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

      await expect(fairplay.write.createMarket([question, category, endTime]));
      //   .to.emit(fairplay, "MarketCreated")
      //   .withArgs(0, question, endTime);

      const market = await fairplay.read.marketCores([0]);
      console.log(market);
      expect(market[0]).to.equal(question);
      expect(market[1]).to.equal(category);
      expect(market[2]).to.equal(BigInt(endTime));
      expect((market[3] as Address).toLowerCase()).to.equal(
        owner.account?.address.toLowerCase()
      );
    });

    it("Should not allow market creation with past end time", async () => {
      const question = "Will it rain tomorrow?";
      const category = "Weather";
      const endTime = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago

      await expect(
        fairplay.write.createMarket([question, category, endTime])
      ).to.be.rejectedWith("End time must be in the future");
    });
  });

  //   describe("Staking", () => {
  //     beforeEach(async () => {
  //       const question = "Will it rain tomorrow?";
  //       const category = "Weather";
  //       const endTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  //       await fairplay.write.createMarket([question, category, endTime]);
  //     });

  //     it("Should allow placing a stake", async () => {
  //       const stakeAmount = provider.utils.parseEther("1.0");
  //       await expect(
  //         fairplay.write.placeStake([0, 1, { value: stakeAmount }])
  //       )
  //         .to.emit(fairplay, "StakePlaced")
  //         .withArgs(0, addr1.account?.address, stakeAmount.sub(stakeAmount.div(100)), 1);

  //       const marketState = await fairplay.read.marketStates([0]);
  //       expect(marketState.totalStake).to.equal(
  //         stakeAmount.sub(stakeAmount.div(100))
  //       );
  //     });

  //     it("Should not allow placing a stake after market end", async () => {
  //       const stakeAmount = provider.utils.parseEther("1.0");
  //       await provider.send("evm_increaseTime", [3600]); // Fast forward 1 hour
  //       await provider.send("evm_mine", []);
  //       await expect(
  //         fairplay.connect(addr1).placeStake(0, 1, { value: stakeAmount })
  //       ).to.be.revertedWith("Market has ended");
  //     });
  //   });

  //   describe("Proposing and Challenging Outcomes", () => {
  //     beforeEach(async () => {
  //       const question = "Will it rain tomorrow?";
  //       const category = "Weather";
  //       const endTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  //       await fairplay.createMarket(question, category, endTime);
  //       await provider.send("evm_increaseTime", [3600]); // Fast forward 1 hour
  //       await provider.send("evm_mine", []);
  //     });

  //     it("Should allow proposing an outcome", async () => {
  //       const bondAmount = provider.utils.parseEther("0.1");
  //       await expect(
  //         fairplay.connect(addr1).proposeOutcome(0, 1, { value: bondAmount })
  //       )
  //         .to.emit(fairplay, "OutcomeProposed")
  //         .withArgs(0, 1, addr1.address);
  //     });

  //     it("Should allow challenging a proposal", async () => {
  //       const bondAmount = provider.utils.parseEther("0.1");
  //       await fairplay.connect(addr1).proposeOutcome(0, 1, { value: bondAmount });

  //       await expect(
  //         fairplay.connect(addr2).challengeProposal(0, { value: bondAmount })
  //       )
  //         .to.emit(fairplay, "ProposalChallenged")
  //         .withArgs(0, addr2.address);
  //     });
  //   });

  //   describe("Resolving and Finalizing Proposals", () => {
  //     beforeEach(async () => {
  //       const question = "Will it rain tomorrow?";
  //       const category = "Weather";
  //       const endTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  //       await fairplay.createMarket(question, category, endTime);
  //       await provider.send("evm_increaseTime", [3600]); // Fast forward 1 hour
  //       await provider.send("evm_mine", []);
  //       const bondAmount = provider.utils.parseEther("0.1");
  //       await fairplay.connect(addr1).proposeOutcome(0, 1, { value: bondAmount });
  //     });

  //     it("Should resolve a proposal correctly", async () => {
  //       await expect(fairplay.resolveProposal(0, true))
  //         .to.emit(fairplay, "ProposalResolved")
  //         .withArgs(0, 1);

  //       const marketState = await fairplay.marketStates(0);
  //       expect(marketState.outcome).to.equal(1);
  //     });

  //     it("Should finalize a proposal after liveness period", async () => {
  //       await provider.send("evm_increaseTime", [86400]); // Fast forward 1 day
  //       await provider.send("evm_mine", []);

  //       await expect(fairplay.finalizeProposal(0))
  //         .to.emit(fairplay, "ProposalResolved")
  //         .withArgs(0, 1);

  //       const marketState = await fairplay.marketStates(0);
  //       expect(marketState.outcome).to.equal(1);
  //     });
  //   });

  //   describe("Distributing Rewards", () => {
  //     beforeEach(async () => {
  //       const question = "Will it rain tomorrow?";
  //       const category = "Weather";
  //       const endTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  //       await fairplay.createMarket(question, category, endTime);
  //       await provider.send("evm_increaseTime", [3600]); // Fast forward 1 hour
  //       await provider.send("evm_mine", []);
  //       const bondAmount = provider.utils.parseEther("0.1");
  //       await fairplay.connect(addr1).proposeOutcome(0, 1, { value: bondAmount });
  //       await fairplay.resolveProposal(0, true);
  //     });

  //     it("Should distribute rewards correctly", async () => {
  //       await provider.send("evm_increaseTime", [3 * 86400]); // Fast forward 3 days
  //       await provider.send("evm_mine", []);

  //       await expect(fairplay.distributeRewards(0))
  //         .to.emit(fairplay, "RewardsDistributed")
  //         .withArgs(0);
  //     });
  //   });
});
