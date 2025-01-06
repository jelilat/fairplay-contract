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
        uint256 creatorReward; // Reward for the market creator
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
    uint256 public marketCount; // Counter for market IDs

    // Events for logging actions
    event MarketCreated(uint256 marketId, string question, uint256 endTime);
    event StakePlaced(
        uint256 marketId,
        address user,
        uint256 amount,
        uint256 units,
        Outcome outcome
    );
    event OutcomeProposed(
        uint256 marketId,
        Outcome proposedOutcome,
        address proposer
    );
    event ProposalChallenged(uint256 marketId, address challenger);
    event ProposalResolved(uint256 marketId, Outcome outcome);
    event RewardsDistributed(uint256 marketId);

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
    ) external {
        require(_endTime > block.timestamp, "End time must be in the future");

        marketCores[marketCount] = MarketCore({
            question: _question,
            category: _category,
            endTime: _endTime,
            creator: msg.sender,
            resolutionTime: 0
        });

        marketStates[marketCount] = MarketState({
            totalStake: 0,
            yesStake: 0,
            noStake: 0,
            rewardPool: 0,
            creatorReward: 0,
            resolved: false,
            outcome: Outcome.UNRESOLVED,
            challenged: false,
            challengeStake: 0,
            challenger: address(0),
            totalYesUnits: 0,
            totalNoUnits: 0
        });

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
            return amount * 2; // 50/50 probability
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

        stakes[marketId][outcome].push(
            Stake({
                amount: netStake,
                units: units,
                staker: msg.sender,
                claimed: false
            })
        );

        emit StakePlaced(marketId, msg.sender, netStake, units, outcome);
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
        // require(market.resolved, "Market not resolved yet");
        // require(!market.challenged, "Market resolution is under challenge");

        uint256 rewardableAmount = (market.rewardPool * stakerReward) / 100;
        Stake[] storage winners = stakes[marketId][market.outcome];

        // Use stored total units instead of loop
        uint256 totalUnits = market.outcome == Outcome.YES
            ? market.totalYesUnits
            : market.totalNoUnits;

        // Distribute rewards based on units
        for (uint256 i = 0; i < winners.length; i++) {
            if (!winners[i].claimed) {
                uint256 reward = (winners[i].units * rewardableAmount) /
                    totalUnits;
                winners[i].claimed = true;

                (bool sent, ) = payable(winners[i].staker).call{
                    value: winners[i].amount + reward
                }("");
                require(sent, "Transfer to staker failed");
            }
        }

        // Handle creator reward
        uint256 creatorRewardAmount = (market.rewardPool * creatorReward) / 100;
        (bool success, ) = payable(marketCores[marketId].creator).call{
            value: creatorRewardAmount
        }("");
        require(success, "Transfer to creator failed");

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
            (bool success, ) = payable(proposal.proposer).call{
                value: proposal.bond + challengeBond
            }("");
            require(success, "Transfer failed");
        } else {
            // Return the challenge bond to the challenger
            (bool success, ) = payable(marketStates[marketId].challenger).call{
                value: challengeBond
            }("");
            require(success, "Transfer to challenger failed");

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

        (bool success, ) = payable(proposal.proposer).call{
            value: proposal.bond
        }("");
        require(success, "Bond transfer failed to proposer");

        emit ProposalResolved(marketId, proposal.proposedOutcome);

        // Call distributeRewards immediately after finalizing
        distributeRewards(marketId);
    }
}
