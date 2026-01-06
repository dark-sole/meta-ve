<div align="center">

# META-VE Protocol

### Liquid Vote-Escrowed Positions for Aerodrome Finance

[![Network: Base Mainnet](https://img.shields.io/badge/Network-Base%20Mainnet-0052FF)](https://basescan.org)
[![Version: 1.0](https://img.shields.io/badge/Version-1.0-00D395)](https://github.com/dark-sole/meta-ve)
[![Tests: 833 Passing](https://img.shields.io/badge/Tests-833%20Passing-00D395)](docs/TEST_RESULTS.md)
[![Formal Verification: 62/62](https://img.shields.io/badge/Formal%20Verification-62%2F62-00D395)](docs/TEST_RESULTS.md)
[![License: Proprietary](https://img.shields.io/badge/License-Proprietary-red)](LICENSE)

[**Documentation**](docs/PROTOCOL_GUIDE.md) • [**Technical Handbook**](docs/TECHNICAL_HANDBOOK.md) • [**Contract Explorer**](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Performance](#performance)
- [Architecture](#architecture)
- [Security](#security)
- [Deployed Contracts](#deployed-contracts)
- [Documentation](#documentation)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

META-VE is a fully autonomous protocol that transforms Aerodrome's permanently locked veAERO NFTs into liquid, fungible tokens. By decomposing vote-escrowed positions into separate voting and capital rights, META-VE unlocks DeFi composability while preserving the core mechanics of vote-escrowed governance.

### The Problem

Vote-escrowed tokens like veAERO create a fundamental liquidity trap:

- **Permanent Lock**: AERO locked forever, no exit strategy
- **Illiquid Positions**: Cannot be sold, transferred, or used as collateral
- **All-or-Nothing**: Voting power and yield rights are inseparable
- **Single Wallet Constraint**: Cannot delegate voting to specialized managers
- **Manual Claims**: Must track and claim bribes from each gauge individually

### The Solution

META-VE splits each veAERO NFT into two fungible ERC-20 tokens:

| Token | Allocation | Rights |
|-------|-----------|---------|
| **V-AERO** | 90% to user | Voting rights on Aerodrome gauges, emissions voting, liquidation governance |
| **C-AERO** | 99% to user | Capital rights including trading fees, rebase rewards, META incentives, and bribes |

Both tokens are freely tradeable, enabling:
- **Liquidity**: Exit your position anytime by selling V-AERO and C-AERO
- **Specialization**: Transfer V-AERO to professional vote managers, keep C-AERO for yield
- **Composability**: Use tokens as collateral in lending markets
- **Diversification**: Sell voting rights, keep yield rights (or vice versa)

---

## Features

### Core Innovations

- **🔀 Vote-Escrow Decomposition**
  First protocol to cleanly separate voting rights from capital rights in veTokens

- **⚡ DeltaForce Emissions**
  Algorithmic emission curve with real-time utilization feedback, computed entirely on-chain (~47K gas)

- **🔒 Epoch Locking**
  Anti-manipulation mechanism prevents vote-and-dump attacks via epoch-aligned transfer locks

- **🤖 Keeper-Free Operation**
  All protocol actions executed by incentivized participants—no off-chain bots required

- **🛡️ Hardened Transfers**
  Advanced checkpoint system prevents gaming via round-UP accounting and sweep-on-transfer

- **💨 Gas Optimized**
  Bitpacked storage (92% reduction), O(1) claims, sub-50K gas for most operations

### META Token: The Governance Layer

META operates one level above traditional VE systems—a "meta-escrow" that governs allocation across multiple vote-escrowed protocols:

| Level | Lock Asset | Vote On | Earn |
|-------|-----------|---------|------|
| **Layer 1: veAERO** | AERO | Liquidity gauges | Pool-specific fees + bribes |
| **Layer 2: META** | META | VE protocols | Aggregated fees across all VE systems |

**Multi-Phase Vision:**
- **Phase 1** (Live): META directs incentives to veAERO on Base
- **Phase 2** (2026): Expand to veVELO, veRAM, veTHENA
- **Phase 3** (2026): Cross-chain VE aggregation

META holders become **allocators of allocators**—directing incentives to the most capital-efficient vote-escrowed systems.

---

## How It Works

### 1. Deposit veAERO NFT

```solidity
// Approve NFT transfer
IVotingEscrow(VOTING_ESCROW).approve(VE_AERO_SPLITTER, tokenId);

// Deposit and receive V-AERO + C-AERO
IVeAeroSplitter(VE_AERO_SPLITTER).depositVeAero(tokenId);
// User receives: 900 V-AERO + 990 C-AERO (for 1000 veAERO NFT)
```

### 2. Vote with V-AERO

**Active Voting** (you choose gauges):
```solidity
IVToken(V_AERO).vote(gaugeAddress, amountWei);
```

**Passive Voting** (follow active voters):
```solidity
IVToken(V_AERO).votePassive(amountWei);
```

Locked until next epoch (Thursday 00:00 UTC).

### 3. Claim Rewards with C-AERO

```solidity
ICToken cToken = ICToken(C_AERO);

// Claim trading fees (AERO)
cToken.collectFees();  // Protocol pulls from Aerodrome
cToken.claimFees();    // You claim your proportional share

// Claim rebase rewards (mints new V-AERO + C-AERO)
cToken.collectRebase();
cToken.claimRebase();

// Claim META incentives
cToken.collectMeta();
cToken.claimMeta();

// Claim bribes (various tokens)
cToken.claimBribes(bribeTokenAddress);
```

### 4. Trade or Exit

```solidity
// Exit: Sell both tokens on DEX
IUniswapV2Router(ROUTER).swapExactTokensForTokens(
    vAeroBalance, 0, [V_AERO, WETH], msg.sender, deadline
);
IUniswapV2Router(ROUTER).swapExactTokensForTokens(
    cAeroBalance, 0, [C_AERO, WETH], msg.sender, deadline
);

// Specialize: Keep C-AERO, delegate voting by selling V-AERO
// Or keep V-AERO for governance, sell C-AERO for upfront capital
```

---

## Performance

### Gas Efficiency

| Operation | META-VE | Naive Implementation | Improvement |
|-----------|---------|---------------------|-------------|
| Gauge vote | ~45,000 gas | ~200,000 gas | **77% reduction** |
| Reward claim | ~65,000 gas | ~150,000+ gas | **57% reduction** |
| DeltaForce calc | ~47,000 gas | Off-chain oracle | **On-chain** |

### Storage Optimization

| Metric | META-VE | Standard Approach | Improvement |
|--------|---------|------------------|-------------|
| 100 gauge votes | 8 storage slots | 100 storage slots | **92% reduction** |
| Claim complexity | O(1) per user | O(n) iterations | **Constant time** |
| Max gauges supported | 100+ gauges | Gas-limited (~30) | **3x capacity** |

**Technical Achievement**: DeltaForce emissions use a sophisticated non-linear logistic curve with real-time staking utilization feedback, computed entirely on-chain in ~47K gas. Most protocols require off-chain computation or simplified linear models.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AERODROME PROTOCOL                         │
│                                                                 │
│   VotingEscrow → Voter → Gauges → Rewards                      │
└────────────────────────────┬────────────────────────────────────┘
                             │ NFT Deposits
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      META-VE PROTOCOL                           │
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │VeAeroSplitter│────►│    VToken    │────►│   VoteLib    │    │
│  │  (custody)   │     │  (V-AERO)    │     │ (multi-NFT)  │    │
│  └──────┬───────┘     └──────────────┘     └──────────────┘    │
│         │                                                       │
│         ├──────────────►┌──────────────┐     ┌──────────────┐  │
│         │               │    CToken    │────►│     Meta     │  │
│         │               │  (C-AERO)    │     │ (emissions)  │  │
│         │               └──────────────┘     └──────────────┘  │
│         │                                                       │
│         └──────────────►┌──────────────┐     ┌──────────────┐  │
│                         │ VeAeroBribes │     │VeAeroLiquid  │  │
│                         │ (snapshots)  │     │ (winddown)   │  │
│                         └──────────────┘     └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Responsibilities

| Contract | Purpose |
|----------|---------|
| **VeAeroSplitter** | Central hub: NFT custody, token minting, fee/rebase distribution |
| **VToken (V-AERO)** | Voting token with epoch locks and gauge vote tracking |
| **CToken (C-AERO)** | Capital token with fee/META/bribe claim logic |
| **RToken (R-AERO)** | Receipt token issued during liquidation phase |
| **Meta** | META token with DeltaForce emissions and staking |
| **VeAeroBribes** | Bribe snapshot system and proportional distribution |
| **VeAeroLiquidation** | Manages winddown phase and NFT redemption |
| **VoteLib** | Multi-NFT vote aggregation and gauge distribution |
| **EmissionsVoteLib** | Tracks emissions voting on federated pools |

---

## Security

### Formal Verification

| Method | Count | Status |
|--------|-------|--------|
| Unit Tests | 692 | ✅ All passing |
| Fork Tests (Base Mainnet) | 141 | ✅ All passing |
| Halmos Symbolic Proofs | 17 | ✅ Formally proven |
| Echidna Fuzzing Invariants | 21 | ✅ No violations |
| Certora Formal Verification | 24 | ✅ All verified |
| **Total Validations** | **895** | **✅ 100% pass rate** |

See [Test Results](docs/TEST_RESULTS.md) for detailed reports.

### Security Features

- **Transfer Windfall Protection**: Rewards swept based on transfer amount, not balance
- **Round-UP Checkpointing**: Prevents dust accumulation attacks
- **Self-Transfer Guards**: No-op on self-transfers to prevent accounting exploits
- **Bribe Claim Deadline**: Wednesday 23:00 UTC cutoff prevents late claims
- **Cached Vote Totals**: Snapshot consistency guarantees for bribe distribution
- **Reentrancy Guards**: All external calls protected by OpenZeppelin ReentrancyGuard
- **Integer Overflow Protection**: Solidity 0.8+ checked arithmetic

### Admin Model

Two-tier multisig structure with **zero asset extraction capability**:

**META MSIG** (Configuration Only)
- Can: Adjust emission parameters, set fee recipients, pause/unpause
- Cannot: Withdraw user funds, transfer NFTs, modify token balances

**LIQUIDATION MSIG** (Emergency Winddown)
- Can: Initiate liquidation phase (requires V-AERO supermajority vote)
- Cannot: Extract funds during normal operation
- Activates: Only if supermajority (67%+) of V-AERO holders vote to liquidate

See [Admin Rights](docs/MSIG_ADMIN_RIGHTS.md) for complete security model.

---

## Deployed Contracts

**Network**: Base Mainnet (Chain ID: 8453)
**Deployment Block**: [40,414,704](https://basescan.org/block/40414704)
**Deployment Date**: January 4, 2026

| Contract | Address | Explorer |
|----------|---------|----------|
| **VeAeroSplitter** | `0x341f394086D6877885fD2cC966904BDFc2620aBf` | [View →](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf) |
| **V-AERO** (VToken) | `0x2B214E99050db935FBF3479E8629B2E3078DF61a` | [View →](https://basescan.org/address/0x2B214E99050db935FBF3479E8629B2E3078DF61a) |
| **C-AERO** (CToken) | `0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD` | [View →](https://basescan.org/address/0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD) |
| **R-AERO** (RToken) | `0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908` | [View →](https://basescan.org/address/0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908) |
| **META** | `0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051` | [View →](https://basescan.org/address/0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051) |
| **VeAeroBribes** | `0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB` | [View →](https://basescan.org/address/0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB) |
| **VeAeroLiquidation** | `0xad608ecD3b506EB35f706bBb67D817aCe873B8eB` | [View →](https://basescan.org/address/0xad608ecD3b506EB35f706bBb67D817aCe873B8eB) |
| **VoteLib** | `0x2dE16D98569c6CB352F80fc6024F5C86F3Ef47c5` | [View →](https://basescan.org/address/0x2dE16D98569c6CB352F80fc6024F5C86F3Ef47c5) |
| **EmissionsVoteLib** | `0x5a301a802B0C4BD5389E3Dc31eeB54cf37c65324` | [View →](https://basescan.org/address/0x5a301a802B0C4BD5389E3Dc31eeB54cf37c65324) |

### Integration

```javascript
// Contract ABIs available in /abi directory
const VeAeroSplitter = "0x341f394086D6877885fD2cC966904BDFc2620aBf";
const V_AERO = "0x2B214E99050db935FBF3479E8629B2E3078DF61a";
const C_AERO = "0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD";
const META = "0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051";
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [**Protocol Guide**](docs/PROTOCOL_GUIDE.md) | User-facing guide with examples and best practices |
| [**Technical Handbook**](docs/TECHNICAL_HANDBOOK.md) | Complete technical specification (180+ pages) |
| [**Test Results**](docs/TEST_RESULTS.md) | Detailed test coverage and formal verification reports |
| [**Reward Claim Paths**](docs/REWARD_CLAIM_PATHS.md) | Step-by-step reward flow documentation |
| [**Admin Rights**](docs/MSIG_ADMIN_RIGHTS.md) | MSIG permissions and security guarantees |

---

## Roadmap

### Phase 1: veAERO on Base ✅ (Live)

**Completed January 2026**

- [x] Core protocol deployment
- [x] V-AERO and C-AERO token launch
- [x] META token and DeltaForce emissions
- [x] VeAeroBribes snapshot system
- [x] 895 tests and formal verifications
- [x] Base mainnet deployment

### Phase 2: Multi-VE Expansion 🔨 (In Development)

**Target: Q2 2026**

- [ ] veVELO integration (Velodrome on Optimism)
- [ ] veRAM integration (Ramses on Arbitrum)
- [ ] veTHENA integration (Thena on BNB Chain)
- [ ] Cross-protocol fee aggregation
- [ ] META governance for VE pool allocation
- [ ] Multi-VE LP incentives

### Phase 3: Cross-Chain Infrastructure 📐 (Architecture Complete)

**Target: Q3-Q4 2026**

- [ ] L1ProofVerifier deployment
- [ ] Cross-chain V-AERO bridging
- [ ] Unified voting across chains
- [ ] LayerZero/Hyperlane integration
- [ ] Cross-chain bribe aggregation
- [ ] Omnichain META staking

### Future Enhancements 💡 (Planned)

- [ ] Concentrated liquidity pools for V-AERO/C-AERO
- [ ] Automated market making strategies
- [ ] Integration with major lending protocols
- [ ] DAO treasury management tools
- [ ] Analytics dashboard and API

---

## Community & Support

### Get Involved

- **Documentation**: [docs/PROTOCOL_GUIDE.md](docs/PROTOCOL_GUIDE.md)
- **GitHub**: [github.com/dark-sole/meta-ve](https://github.com/dark-sole/meta-ve)
- **Smart Contracts**: [basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf)

### Contributing

This is a proprietary protocol. For partnership and integration inquiries, contact **contact@tokenisys.xyz**

---

## License

**Proprietary License**

Copyright © 2026 Tokenisys. All rights reserved.

This software and its associated documentation are proprietary and confidential. Unauthorized copying, modification, distribution, or use is strictly prohibited without explicit written permission from Tokenisys.

The protocol is available for partnership, integration, and licensing opportunities.

### Contact

**Tokenisys** — Architects of tokenized economic systems

📧 **Email**: contact@tokenisys.xyz
🌐 **Protocol**: [META-VE on Base](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf)
📚 **Documentation**: [Technical Handbook](docs/TECHNICAL_HANDBOOK.md)

---

<div align="center">

**Built for the Aerodrome ecosystem on Base**

[![Base](https://img.shields.io/badge/Built%20on-Base-0052FF)](https://base.org)
[![Aerodrome](https://img.shields.io/badge/Integrated%20with-Aerodrome-00D395)](https://aerodrome.finance)

*Transforming vote-escrowed governance into liquid DeFi primitives*

</div>
