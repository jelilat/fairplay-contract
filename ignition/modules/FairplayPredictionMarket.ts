import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const FairplayPredictionMarketModule = buildModule(
  "FairplayPredictionMarketModule",
  (m) => {
    const fairplayPredictionMarket = m.contract("FairplayPredictionMarket");

    return { fairplayPredictionMarket };
  }
);

export default FairplayPredictionMarketModule;
