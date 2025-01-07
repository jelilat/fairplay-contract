# Fairplay: No-Loss Prediction Markets

## Overview
Fairplay is a decentralized no-loss prediction market protocol where users can stake on market outcomes without risking their principal. The reward pool is generated from platform fees, which are distributed to winning participants.

## Core Components

### 1. Markets
- **Market Creation**: Anyone can create a market by specifying:
  - Question (e.g., "Will ETH price be above $3000 on Dec 31?")
  - Category (e.g., "Crypto", "Sports", "Politics")
  - End Time
  - Initial Seed (GRASS): The market creator must provide an initial seed amount, which is split equally between the `YES` and `NO` outcomes to ensure balanced initial stakes.

### 2. Automated Market Maker (AMM)
- **Staking**: Users can stake on market outcomes (`YES` or `NO`). The AMM model automatically adjusts the odds based on the current stakes.
- **Unit Calculation**: The number of units received for a stake is calculated based on the current probability of the chosen outcome, ensuring fair price discovery.

### 3. Fee Structure
- **Platform Fee**: 1% of each stake
- **Distribution**:
  - 80% to winning stakers
  - 10% to market creator
  - 10% to protocol

### 4. Resolution Mechanism
1. **Market End**: Trading stops at predetermined end time
2. **Proposal Phase**: Anyone can propose an outcome by posting a bond
3. **Challenge Period**: Others can challenge the proposed outcome
4. **Resolution**: Market resolves to final outcome
5. **Distribution**: 
   - Principal returned to all participants
   - Rewards distributed to winning side

## Key Features

### No-Loss Design
- Principal is always returned to participants
- Only platform fees are used for rewards
- Zero-risk participation model

### Fair Price Discovery
- AMM ensures efficient price discovery
- Prevents last-minute manipulation
- Transparent staking mechanism

### Decentralized Resolution
- Bond-based outcome proposal system
- Challenge mechanism for dispute resolution
- Economic incentives for honest reporting

## Technical Architecture

### Smart Contracts
1. **FairplayPredictionMarket.sol**
   - Market creation and management
   - AMM-based staking operations
   - Stake handling
   - Resolution mechanism
   - Reward distribution

### Key Parameters
- Platform Fee: 1%
- Staker Reward: 80% of platform fees
- Creator Reward: 10% of platform fees
- Protocol Fee: 10% of platform fees
- Challenge Period: 3 days
- Proposal Bond: 0.1 GRASS
- Challenge Bond: 0.1 GRASS

## Security Considerations
- Reentrancy protection
- Time-based attack prevention
- Economic incentive alignment
- Principal protection guarantees

## Future Extensions
- Multiple resolution mechanisms
- Additional market types
- Enhanced AMM algorithms
- Governance system