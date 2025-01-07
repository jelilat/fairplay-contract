// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title FairplayPredictionMarket
 * @dev A decentralized prediction market contract allowing users to create markets, place stakes, propose outcomes, and challenge proposals.
 *
 * DISCLAIMER: This smart contract has not been audited. Use at your own risk.
 * The authors and maintainers of this contract are not responsible for any loss of funds or other damages resulting from its use.
 *
 * Author: Jelilat Anofiu
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FairplayPredictionMarket is Ownable, ReentrancyGuard {
    // Enum representing possible outcomes of a market
    enum Outcome {
        UNRESOLVED,
        YES,
        NO
    }

    // Core details of a market
    struct MarketCore {
        string question; // The question being predicted
        string category; // Category of the market
        uint256 endTime; // Time when the market ends
        address creator; // Address of the market creator
        uint256 resolutionTime; // Time when the market is resolved
    }

    // State details of a market
    struct MarketState {
        uint256 totalStake; // Total amount staked in the market
        uint256 yesStake; // Total amount staked on 'YES'
        uint256 noStake; // Total amount staked on 'NO'
        uint256 rewardPool; // Total reward pool
        bool resolved; // Whether the market is resolved
        Outcome outcome; // Outcome of the market
        bool challenged; // Whether the proposal is challenged
        uint256 challengeStake; // Total amount staked for challenges
        address challenger; // Address of the challenger
        uint256 totalYesUnits; // Total units for 'YES' outcome
        uint256 totalNoUnits; // Total units for 'NO' outcome
    }

    // Details of a proposal for market resolution
    struct Proposal {
        Outcome proposedOutcome; // Proposed outcome of the market
        address proposer; // Address of the proposer
        uint256 bond; // Bond amount for the proposal
        uint256 livenessDeadline; // Deadline for proposal liveness
        bool resolved; // Whether the proposal is resolved
    }

    // Details of a stake placed in the market
    struct Stake {
        uint256 amount; // Original stake amount
        uint256 units; // Units received based on probability at time of stake
        address staker; // Address of the staker
        bool claimed; // Whether the stake has been claimed
    }

    // Constants for handling fees and rewards
    uint256 public constant PRECISION = 1e18; // For handling decimals
    uint256 public immutable platformFee = 1; // 1% of stake
    uint256 public immutable creatorReward = 10; // 10% of platform fee
    uint256 public immutable stakerReward = 80; // 80% of platform fee
    uint256 public immutable challengePeriod = 3 days; // Challenge period after resolution
    uint256 public immutable proposalBond = 0.1 ether; // Bond for proposing an outcome
    uint256 public immutable challengeBond = 0.1 ether; // Bond for challenging a proposal

    // Mappings to store market data
    mapping(uint256 => MarketCore) public marketCores;
    mapping(uint256 => MarketState) public marketStates;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(Outcome => Stake[])) public stakes;
    mapping(address => uint256) public balances; // Track user balances
    uint256 public marketCount; // Counter for market IDs

    // Events for logging actions
    event MarketCreated(uint256 marketId, string question, uint256 endTime);
    event StakePlaced(
        uint256 marketId,
        address user,
        uint256 amount,
        uint256 units,
        Outcome outcome,
        uint256 index
    );
    event OutcomeProposed(
        uint256 marketId,
        Outcome proposedOutcome,
        address proposer
    );
    event ProposalChallenged(uint256 marketId, address challenger);
    event ProposalResolved(uint256 marketId, Outcome outcome);
    event RewardsDistributed(uint256 marketId);
    event StakeRestaked(
        uint256 oldMarketId,
        uint256 newMarketId,
        address staker,
        uint256 amount
    );
    event Withdrawal(address indexed user, uint256 amount);

    /**
     * @dev Constructor to initialize the contract with the owner.
     */
    constructor() Ownable(msg.sender) {}

    // Modifiers to enforce function execution conditions
    modifier onlyBeforeEnd(uint256 marketId) {
        require(
            block.timestamp < marketCores[marketId].endTime,
            "Market has ended"
        );
        _;
    }

    modifier onlyAfterEnd(uint256 marketId) {
        require(
            block.timestamp >= marketCores[marketId].endTime,
            "Market has not ended"
        );
        _;
    }

    modifier onlyAfterChallengePeriod(uint256 marketId) {
        require(
            block.timestamp >=
                marketCores[marketId].resolutionTime + challengePeriod,
            "Challenge period not over"
        );
        _;
    }

    /**
     * @dev Creates a new prediction market.
     * @param _question The question being predicted.
     * @param _category The category of the market.
     * @param _endTime The time when the market ends.
     */
    function createMarket(
        string memory _question,
        string memory _category,
        uint256 _endTime
    ) external payable {
        require(_endTime > block.timestamp, "End time must be in the future");
        require(msg.value > 0, "Initial seed must be greater than 0");

        uint256 halfSeed = msg.value / 2;
        require(halfSeed > 0, "Initial seed too small");

        marketCores[marketCount] = MarketCore({
            question: _question,
            category: _category,
            endTime: _endTime,
            creator: msg.sender,
            resolutionTime: 0
        });

        marketStates[marketCount] = MarketState({
            totalStake: msg.value,
            yesStake: halfSeed,
            noStake: halfSeed,
            rewardPool: 0,
            resolved: false,
            outcome: Outcome.UNRESOLVED,
            challenged: false,
            challengeStake: 0,
            challenger: address(0),
            totalYesUnits: 0,
            totalNoUnits: 0
        });

        // Add initial stakes to the stakes mapping
        stakes[marketCount][Outcome.YES].push(
            Stake({
                amount: halfSeed,
                units: halfSeed, // Assuming 1:1 units for initial stake
                staker: msg.sender,
                claimed: false
            })
        );

        stakes[marketCount][Outcome.NO].push(
            Stake({
                amount: halfSeed,
                units: halfSeed, // Assuming 1:1 units for initial stake
                staker: msg.sender,
                claimed: false
            })
        );

        emit MarketCreated(marketCount, _question, _endTime);
        marketCount++;
    }

    /**
     * @dev Calculates the units received for a given stake amount.
     * @param amount The amount being staked.
     * @param currentStake The current stake on the chosen outcome.
     * @param oppositeStake The current stake on the opposite outcome.
     * @return The number of units received.
     */
    function calculateUnits(
        uint256 amount,
        uint256 currentStake,
        uint256 oppositeStake
    ) public pure returns (uint256) {
        // If no stakes yet, return 2 units per token (50/50 probability)
        if (currentStake == 0 && oppositeStake == 0) {
            return amount * 1; // 50/50 probability
        }

        // Calculate probability and units
        uint256 totalStake = currentStake + oppositeStake;
        uint256 probability = (currentStake * PRECISION) / totalStake;

        // More units when probability is lower
        // Units = amount * (1/probability)
        return (amount * PRECISION) / probability;
    }

    /**
     * @dev Places a stake on a market outcome.
     * @param marketId The ID of the market.
     * @param outcome The outcome being staked on.
     */
    function placeStake(
        uint256 marketId,
        Outcome outcome
    ) external payable onlyBeforeEnd(marketId) nonReentrant {
        require(
            outcome == Outcome.YES || outcome == Outcome.NO,
            "Invalid outcome"
        );
        require(msg.value > 0, "Stake must be greater than 0");
        require(marketId < marketCount, "Market does not exist");

        MarketState storage state = marketStates[marketId];

        uint256 fee = (msg.value * platformFee) / 100;
        uint256 netStake = msg.value - fee;

        // Calculate units based on current probabilities
        uint256 units = calculateUnits(
            netStake,
            outcome == Outcome.YES ? state.yesStake : state.noStake,
            outcome == Outcome.YES ? state.noStake : state.yesStake
        );

        // Update market state
        state.totalStake += netStake;
        state.rewardPool += fee;

        if (outcome == Outcome.YES) {
            state.yesStake += netStake;
            state.totalYesUnits += units;
        } else {
            state.noStake += netStake;
            state.totalNoUnits += units;
        }

        // Add the stake to the array and get the index
        uint256 index = stakes[marketId][outcome].length;
        stakes[marketId][outcome].push(
            Stake({
                amount: netStake,
                units: units,
                staker: msg.sender,
                claimed: false
            })
        );

        emit StakePlaced(marketId, msg.sender, netStake, units, outcome, index);
    }

    /**
     * @dev Proposes an outcome for a market.
     * @param marketId The ID of the market.
     * @param proposedOutcome The proposed outcome.
     */
    function proposeOutcome(
        uint256 marketId,
        Outcome proposedOutcome
    ) external payable onlyAfterEnd(marketId) {
        require(msg.value >= proposalBond, "Insufficient bond for proposal");
        MarketState storage market = marketStates[marketId];
        require(!market.resolved, "Market already resolved");

        proposals[marketId] = Proposal({
            proposedOutcome: proposedOutcome,
            proposer: msg.sender,
            bond: msg.value,
            livenessDeadline: block.timestamp + 1 days,
            resolved: false
        });

        emit OutcomeProposed(marketId, proposedOutcome, msg.sender);
    }

    /**
     * @dev Challenges a proposed outcome.
     * @param marketId The ID of the market.
     */
    function challengeProposal(uint256 marketId) external payable {
        Proposal storage proposal = proposals[marketId];
        require(
            block.timestamp < proposal.livenessDeadline,
            "Proposal liveness expired"
        );
        require(!proposal.resolved, "Proposal already resolved");
        require(msg.value >= challengeBond, "Insufficient bond for challenge");

        marketStates[marketId].challenged = true;
        marketStates[marketId].challengeStake += msg.value;
        marketStates[marketId].challenger = msg.sender;

        emit ProposalChallenged(marketId, msg.sender);
    }

    /**
     * @dev Distributes rewards to the winning stakers and the market creator.
     * @param marketId The ID of the market.
     */
    function distributeRewards(
        uint256 marketId
    ) internal onlyAfterChallengePeriod(marketId) nonReentrant {
        MarketState storage market = marketStates[marketId];
        market.resolved = true;

        uint256 creatorRewardAmount = (market.rewardPool * creatorReward) / 100;
        balances[marketCores[marketId].creator] += creatorRewardAmount;
        balances[owner()] += creatorRewardAmount;

        emit RewardsDistributed(marketId);
    }

    /**
     * @dev Resolves a proposal based on its correctness.
     * @param marketId The ID of the market.
     * @param isProposalCorrect Whether the proposal is correct.
     */
    function resolveProposal(
        uint256 marketId,
        bool isProposalCorrect
    ) external onlyOwner {
        Proposal storage proposal = proposals[marketId];
        require(!proposal.resolved, "Proposal already resolved");

        if (isProposalCorrect) {
            marketStates[marketId].outcome = proposal.proposedOutcome;
            balances[proposal.proposer] += proposal.bond + challengeBond;
        } else {
            // Return the challenge bond to the challenger
            balances[marketStates[marketId].challenger] += challengeBond;
            marketStates[marketId].rewardPool += proposal.bond;
        }

        proposal.resolved = true;

        emit ProposalResolved(marketId, marketStates[marketId].outcome);

        // distributeRewards immediately after resolving
        distributeRewards(marketId);
    }

    /**
     * @dev Finalizes a proposal if no challenge exists.
     * @param marketId The ID of the market.
     */
    function finalizeProposal(uint256 marketId) external {
        Proposal storage proposal = proposals[marketId];
        require(
            block.timestamp >= proposal.livenessDeadline,
            "Liveness period not yet expired"
        );
        require(!proposal.resolved, "Proposal already resolved");
        require(!marketStates[marketId].challenged, "Proposal is challenged");

        marketStates[marketId].outcome = proposal.proposedOutcome;
        proposal.resolved = true;

        balances[proposal.proposer] += proposal.bond;

        emit ProposalResolved(marketId, proposal.proposedOutcome);

        // Call distributeRewards immediately after finalizing
        distributeRewards(marketId);
    }

    /**
     * @dev Allows users to claim their stake and rewards.
     * @param marketId The ID of the market.
     * @param outcome The outcome the user staked on.
     * @param stakeIndex The index of the stake in the market's stake array.
     */
    function unstake(
        uint256 marketId,
        Outcome outcome,
        uint256 stakeIndex
    ) external nonReentrant {
        MarketState storage market = marketStates[marketId];
        require(market.resolved, "Market not resolved yet");

        Stake storage userStake = stakes[marketId][outcome][stakeIndex];
        require(userStake.staker == msg.sender, "Not the stake owner");
        require(!userStake.claimed, "Stake already claimed");

        uint256 reward = 0;
        if (market.outcome == outcome) {
            uint256 rewardableAmount = (market.rewardPool * stakerReward) / 100;
            uint256 totalUnits = outcome == Outcome.YES
                ? market.totalYesUnits
                : market.totalNoUnits;
            reward = (userStake.units * rewardableAmount) / totalUnits;
        }

        userStake.claimed = true;
        balances[msg.sender] += userStake.amount + reward;
    }

    /**
     * @dev Allows users to withdraw a specific amount from their balance.
     * @param amount The amount to withdraw.
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Allows users to restake their unclaimed stakes into a new market.
     * @param oldMarketId The ID of the market from which the stake is being restaked.
     * @param newMarketId The ID of the market to which the stake is being restaked.
     * @param outcome The outcome being staked on in the new market.
     * @param stakeIndex The index of the stake in the old market's stake array.
     */
    function restake(
        uint256 oldMarketId,
        uint256 newMarketId,
        Outcome outcome,
        uint256 stakeIndex
    ) external onlyBeforeEnd(newMarketId) nonReentrant {
        require(newMarketId < marketCount, "New market does not exist");
        require(
            outcome == Outcome.YES || outcome == Outcome.NO,
            "Invalid outcome"
        );

        Stake storage userStake = stakes[oldMarketId][
            marketStates[oldMarketId].outcome
        ][stakeIndex];
        require(userStake.staker == msg.sender, "Not the stake owner");
        require(!userStake.claimed, "Stake already claimed or restaked");

        uint256 restakeAmount = userStake.amount;
        require(restakeAmount > 0, "No restakable stake found");

        userStake.claimed = true; // Mark as claimed to prevent double restaking

        MarketState storage newState = marketStates[newMarketId];

        uint256 units = calculateUnits(
            restakeAmount,
            outcome == Outcome.YES ? newState.yesStake : newState.noStake,
            outcome == Outcome.YES ? newState.noStake : newState.yesStake
        );

        newState.totalStake += restakeAmount;

        if (outcome == Outcome.YES) {
            newState.yesStake += restakeAmount;
            newState.totalYesUnits += units;
        } else {
            newState.noStake += restakeAmount;
            newState.totalNoUnits += units;
        }

        stakes[newMarketId][outcome].push(
            Stake({
                amount: restakeAmount,
                units: units,
                staker: msg.sender,
                claimed: false
            })
        );

        emit StakeRestaked(oldMarketId, newMarketId, msg.sender, restakeAmount);
    }

    function getTotalYesStakes(uint256 marketId) public view returns (uint256) {
        return stakes[marketId][Outcome.YES].length;
    }

    function getTotalNoStakes(uint256 marketId) public view returns (uint256) {
        return stakes[marketId][Outcome.NO].length;
    }
}
