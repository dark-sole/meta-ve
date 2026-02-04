
# META-VE Protocol

### Liquid Vote-Escrowed Positions for Aerodrome Finance

[![Network: Base Mainnet](https://img.shields.io/badge/Network-Base%20Mainnet-0052FF)](https://basescan.org)
[![Deployment: DELTA](https://img.shields.io/badge/Deployment-DELTA-00D395)](https://basescan.org/address/0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644)
[![Tests: 895 Passing](https://img.shields.io/badge/Tests-895%20Passing-00D395)](docs/TEST_RESULTS.md)
[![Formal Verification: 62/62](https://img.shields.io/badge/Formal%20Verification-62%2F62-00D395)](docs/TEST_RESULTS.md)
[![License: Proprietary](https://img.shields.io/badge/License-Proprietary-red)](LICENSE)

[**Documentation**](docs/PROTOCOL_GUIDE.md) · [**Technical Handbook**](docs/TECHNICAL_HANDBOOK.md) · [**Contract Explorer**](https://basescan.org/address/0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644)



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
- **Single Wallet Constraint**: Cannot delegate voting to specialised managers
- **Manual Claims**: Must track and claim bribes from each gauge individually

### The Solution

META-VE splits each veAERO NFT into two fungible ERC-20 tokens:

| Token | Allocation | Rights |
|-------|-----------|---------|
| **V-AERO** | 90% to user | Voting rights on Aerodrome gauges, emissions voting, liquidation governance |
| **C-AERO** | 99% to user | Capital rights including trading fees, rebase rewards, META incentives, and bribes |

> The remaining 1% V-AERO goes to Tokenisys; 9% V-AERO to the META contract for protocol voting; 1% C-AERO to Tokenisys.

Both tokens are freely tradeable, enabling:
- **Liquidity**: Exit your position anytime by selling V-AERO and C-AERO
- **Specialisation**: Transfer V-AERO to professional vote managers, keep C-AERO for yield
- **Composability**: Use tokens as collateral in lending markets
- **Diversification**: Sell voting rights, keep yield rights (or vice versa)

---

## Features

### Core Innovations

- **🔀 Vote-Escrow Decomposition**
  First protocol to cleanly separate voting rights from capital rights in veTokens

- **⚡ DeltaForce Emissions**
  Algorithmic emission curve with real-time utilisation feedback, computed entirely on-chain (~47K gas)

- **🔒 Epoch Locking**
  Anti-manipulation mechanism prevents vote-and-dump attacks via epoch-aligned transfer locks

- **🤖 Keeper-Free Operation**
  All protocol actions executed by incentivised participants—no off-chain bots required

- **🔄 FeeSwapper**
  Converts non-AERO fee tokens (USDC, WETH, etc.) to AERO via MSIG-configured routes with `processSwappedFees()` callback for immediate index updates

- **🛡️ Re-Indexing Transfers**
  On C-AERO transfer, unclaimed Splitter fees are redistributed to all holders via `globalFeeIndex`—no value extracted, round-UP checkpoint blending prevents dust attacks

- **💨 Gas Optimised**
  Bitpacked storage (92% reduction), O(1) claims via four independent index systems, sub-50K gas for most operations

### META Token: The VE Selector Layer

META operates one level above traditional VE systems—a "meta-escrow" that governs allocation across multiple vote-escrowed protocols:

| Level | Lock Asset | Vote On | Earn |
|-------|-----------|---------|------|
| **Layer 1: veAERO** | AERO | Liquidity gauges | Pool-specific fees + bribes |
| **Layer 2: META** | META | VE protocols | Aggregated fees across all VE systems |

**Staker Yield**: Locked META earns from two sources:
- $(1 - S) \times 92.2\%$ of META emissions (via `_checkpointUser`)
- $50\% \times S$ of AERO trading fees (via `feeRewardIndex`)

**Multi-Phase Vision:**
- **Phase 1** (Live): META directs incentives to veAERO on Base
- **Phase 2** (2026): Expand to additional VE protocols (Hydrex integration in progress)
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

**Emissions Voting** (Fed-style rate policy):
```solidity
ICToken(C_AERO).voteEmissions(choice, amountWei); // choice: -1, 0, or +1
```

Tokens locked until next epoch (Thursday 00:00 UTC).

### 3. Claim Rewards

C-AERO holders earn from **multiple contracts**. All must be claimed separately.

```solidity
// ── Path A: Trading fees from Splitter (50% of all AERO fees) ──
IVeAeroSplitter(SPLITTER).claimFees();

// ── Path B: Trading fees routed through Meta ──
ICToken(C_AERO).collectFees();   // Pull AERO from Meta → updates feePerCToken
ICToken(C_AERO).claimFees();     // Claim your proportional AERO

// ── META incentives ──
ICToken(C_AERO).collectMeta();   // Pull META from Meta → updates metaPerCToken
ICToken(C_AERO).claimMeta();     // Claim your proportional META

// ── Rebase rewards (mints new V-AERO + C-AERO) ──
IVeAeroSplitter(SPLITTER).collectRebase();  // Claim rebase from Aerodrome
IVeAeroSplitter(SPLITTER).claimRebase();    // Mint your 90/1/9 V + 99/1 C share

// ── Bribes (snapshot-based, claimed from VeAeroBribes) ──
// Step 1: During epoch N, after gauge vote executes:
IVeAeroBribes(BRIBES).snapshotForBribes();
// Step 2: During epoch N+1:
address[] memory tokens = new address[](1);
tokens[0] = bribeTokenAddress;
IVeAeroBribes(BRIBES).claimBribes(tokens);
```

### 4. META Staker Rewards

```solidity
// Lock META to earn both META emissions and AERO trading fees
IMeta(META).lockTokens(amount);

// Claim both reward types in a single call
(uint256 metaAmt, uint256 aeroAmt) = IMeta(META).claimRewards();
```

### 5. Trade or Exit

```solidity
// Exit: Sell both tokens on Aerodrome DEX
// Specialise: Keep C-AERO for yield, delegate voting by selling V-AERO
// Or: Keep V-AERO for governance, sell C-AERO for upfront capital
```

---

## Performance

### Gas Efficiency

| Operation | META-VE | Naive Implementation | Improvement |
|-----------|---------|---------------------|-------------|
| Gauge vote | ~45,000 gas | ~200,000 gas | **77% reduction** |
| Reward claim | ~65,000 gas | ~150,000+ gas | **57% reduction** |
| DeltaForce calc | ~47,000 gas | Off-chain oracle | **On-chain** |

### Storage Optimisation

| Metric | META-VE | Standard Approach | Improvement |
|--------|---------|------------------|-------------|
| 100 gauge votes | 8 storage slots | 100 storage slots | **92% reduction** |
| Claim complexity | O(1) per user | O(n) iterations | **Constant time** |
| Max gauges supported | 100+ gauges | Gas-limited (~30) | **3x capacity** |

**Technical Achievement**: DeltaForce emissions use a non-linear logistic curve with real-time staking utilisation feedback, computed entirely on-chain in ~47K gas. Most protocols require off-chain computation or simplified linear models.

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
│                    META-VE PROTOCOL (DELTA)                      │
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │VeAeroSplitter│────►│    VToken    │────►│   VoteLib    │    │
│  │  (custody,   │     │  (V-AERO)    │     │ (multi-NFT)  │    │
│  │   fees,      │     └──────────────┘     └──────────────┘    │
│  │   rebase)    │                                               │
│  └──────┬───────┘     ┌──────────────┐     ┌──────────────┐    │
│         │             │  FeeSwapper  │     │EmissionsVote │    │
│         ├────────────►│  (non-AERO   │     │    Lib       │    │
│         │             │   → AERO)    │     └──────────────┘    │
│         │             └──────────────┘                          │
│         │                                                       │
│         ├──────────────►┌──────────────┐     ┌──────────────┐  │
│         │               │    CToken    │◄───►│     Meta     │  │
│         │               │  (C-AERO)    │     │ (emissions,  │  │
│         │               └──────────────┘     │  staking,    │  │
│         │                                     │  fee split)  │  │
│         │                                     └──────────────┘  │
│         └──────────────►┌──────────────┐     ┌──────────────┐  │
│                         │ VeAeroBribes │     │VeAeroLiquid  │  │
│                         │ (snapshots)  │     │ (winddown)   │  │
│                         └──────────────┘     └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Responsibilities

| Contract | Purpose |
|----------|---------|
| **VeAeroSplitter** | Central hub: NFT custody, token minting, fee collection/distribution (globalFeeIndex), rebase tracking, FeeSwapper integration |
| **VToken (V-AERO)** | Voting token with epoch locks, gauge vote tracking, passive voting |
| **CToken (C-AERO)** | Capital token with debt-model META/AERO fee claims, emissions voting |
| **RToken (R-AERO)** | Receipt token issued during liquidation phase |
| **Meta** | META token: DeltaForce emissions, staking, fee routing (receiveFees), multi-VE architecture |
| **FeeSwapper** | Converts non-AERO fee tokens to AERO via MSIG-configured Aerodrome routes, calls processSwappedFees() callback |
| **VeAeroBribes** | Bribe snapshot system and proportional distribution |
| **VeAeroLiquidation** | Manages winddown phase and NFT redemption |
| **VoteLib** | Multi-NFT vote aggregation and gauge distribution |
| **EmissionsVoteLib** | Tracks emissions voting on federated pools |

### Fee Flow (DELTA)

```
Aerodrome Fee Distributors
    │
    ▼
Splitter.collectFees()
    ├── AERO tokens ──► 50% globalFeeIndex (Splitter.claimFees)
    │                   50% Meta.receiveFees()
    │                       ├── poolFeeAccrued → CToken.claimFees
    │                       └── feeRewardIndex → Meta.claimRewards (stakers)
    │
    └── Non-AERO tokens ──► FeeSwapper
                                │
                            swap() via Aerodrome Router
                                │
                            processSwappedFees() callback
                                ├── 50% globalFeeIndex
                                └── 50% Meta.receiveFees()
```

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

- **Re-Indexing Transfers (DELTA)**: Unclaimed fees on transferred C-AERO are redistributed to all holders via `globalFeeIndex`—no value extracted from system
- **Round-UP Checkpointing**: Recipient checkpoint blending uses ceiling division to prevent dust accumulation attacks
- **Self-Transfer Guards**: No-op on self-transfers prevents accounting exploits
- **Debt-Model Distribution**: CToken uses checkpoint-then-update-debt pattern preserving `userClaimable` across transfers
- **Bribe Claim Deadline**: `epochEndTime - CLAIM_WINDOW_BUFFER` cutoff prevents late claims
- **Cached Vote Totals**: Snapshot consistency guarantees for bribe distribution
- **FeeSwapper Access Control**: Only MSIG-configured routes; `processSwappedFees()` restricted to FeeSwapper contract
- **Reentrancy Guards**: All external calls protected by OpenZeppelin ReentrancyGuard
- **Integer Overflow Protection**: Solidity 0.8+ checked arithmetic
- **CEI Compliance**: All state changes follow Checks-Effects-Interactions pattern

### Admin Model

Two-tier multisig structure with **zero asset extraction capability**:

**META MSIG** (Configuration Only)
- Can: Adjust emission parameters, set fee recipients, configure FeeSwapper routes, pause/unpause
- Cannot: Withdraw user funds, transfer NFTs, modify token balances

**LIQUIDATION MSIG** (Emergency Winddown)
- Can: Initiate liquidation phase (requires V-AERO supermajority vote)
- Cannot: Extract funds during normal operation
- Activates: Only if supermajority (67%+) of V-AERO holders vote to liquidate

See [Admin Rights](docs/MSIG_ADMIN_RIGHTS.md) for complete security model.

---

## Deployed Contracts

**Network**: Base Mainnet (Chain ID: 8453)
**Deployment**: DELTA
**Deployment Date**: January 22, 2026

| Contract | Address | Explorer |
|----------|---------|----------|
| **VeAeroSplitter** | `0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644` | [View →](https://basescan.org/address/0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644) |
| **V-AERO** (VToken) | `0x88898d9874bF5c5537DDe4395694abCC6D8Ede52` | [View →](https://basescan.org/address/0x88898d9874bF5c5537DDe4395694abCC6D8Ede52) |
| **C-AERO** (CToken) | `0xB2EDF371E436E2F8dF784a1AFe36B6f16c01573D` | [View →](https://basescan.org/address/0xB2EDF371E436E2F8dF784a1AFe36B6f16c01573D) |
| **R-AERO** (RToken) | `0x6A7B717Cbc314D3fe6102cc37d3B064BD3ccA3D8` | [View →](https://basescan.org/address/0x6A7B717Cbc314D3fe6102cc37d3B064BD3ccA3D8) |
| **META** | `0x776b081bF1B6482422765381b66865043dbA877D` | [View →](https://basescan.org/address/0x776b081bF1B6482422765381b66865043dbA877D) |
| **FeeSwapper** | `0xa295BC5C11C1B0D49cc242d9fBFD86fE05Dc7cD2` | [View →](https://basescan.org/address/0xa295BC5C11C1B0D49cc242d9fBFD86fE05Dc7cD2) |
| **VeAeroBribes** | `0x472Fe0ddfA0C0bA6ff4b0c5a4DC2D7f13A646420` | [View →](https://basescan.org/address/0x472Fe0ddfA0C0bA6ff4b0c5a4DC2D7f13A646420) |
| **VeAeroLiquidation** | `0xa3957D4557f71e2C20015D4B17987D1BF62f8e08` | [View →](https://basescan.org/address/0xa3957D4557f71e2C20015D4B17987D1BF62f8e08) |
| **VoteLib** | `0xFaCf7D32906150594E634c0D6bf70312235c0a33` | [View →](https://basescan.org/address/0xFaCf7D32906150594E634c0D6bf70312235c0a33) |
| **EmissionsVoteLib** | `0xA2633aa2f3cBAa9289597A1824355bc28c58804a` | [View →](https://basescan.org/address/0xA2633aa2f3cBAa9289597A1824355bc28c58804a) |

### Integration

```javascript
// Contract ABIs available in /abi directory
const VeAeroSplitter = "0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644";
const V_AERO         = "0x88898d9874bF5c5537DDe4395694abCC6D8Ede52";
const C_AERO         = "0xB2EDF371E436E2F8dF784a1AFe36B6f16c01573D";
const META           = "0x776b081bF1B6482422765381b66865043dbA877D";
const FeeSwapper     = "0xa295BC5C11C1B0D49cc242d9fBFD86fE05Dc7cD2";
const VeAeroBribes   = "0x472Fe0ddfA0C0bA6ff4b0c5a4DC2D7f13A646420";
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [**Protocol Guide**](docs/PROTOCOL_GUIDE.md) | User-facing guide with examples and best practices |
| [**Technical Handbook**](docs/TECHNICAL_HANDBOOK.md) | Complete technical specification |
| [**Test Results**](docs/TEST_RESULTS.md) | Detailed test coverage and formal verification reports |
| [**Reward Claim Paths**](docs/REWARD_CLAIM_PATHS.md) | Step-by-step reward flow documentation |
| [**Keeper Guide**](docs/DELTA_KEEPER_GUIDE.md) | Epoch operations and keeper responsibilities |
| [**Admin Rights**](docs/MSIG_ADMIN_RIGHTS.md) | MSIG permissions and security guarantees |

---

## Roadmap

### Phase 1: veAERO on Base ✅ (Live — DELTA)

**Deployed January 2026**

- [x] Core protocol deployment (BETA → GAMMA → DELTA iterations)
- [x] V-AERO and C-AERO token launch
- [x] META token and DeltaForce emissions
- [x] FeeSwapper for non-AERO fee token conversion
- [x] Dual fee claim paths (Splitter + CToken)
- [x] META staker rewards (emissions + AERO fees)
- [x] VeAeroBribes snapshot system
- [x] Re-indexing transfer settlement
- [x] 895 tests and formal verifications
- [x] Base mainnet deployment

### Phase 2: Multi-VE Expansion 🔨 (In Development)

**Target: 2026**

- [ ] Second VE protocol integration (partnership discussions underway)
- [ ] Multi-VE fee routing (Phase 2 of Meta.receiveFees)
- [ ] Vote-weighted distribution across VE pools
- [ ] Cross-protocol fee aggregation
- [ ] META governance for VE pool allocation

### Phase 3: Cross-Chain Infrastructure 📐 (Architecture Complete)

**Target: 2026**

- [ ] L1ProofVerifier deployment
- [ ] Cross-chain V-AERO bridging
- [ ] Unified voting across chains
- [ ] Cross-chain bribe aggregation
- [ ] Omnichain META staking

### Future Enhancements 💡 (Planned)

- [ ] FeeSwapper V2: On-chain route optimisation
- [ ] Concentrated liquidity pools for V-AERO/C-AERO
- [ ] Integration with major lending protocols
- [ ] DAO treasury management tools

---

## Community & Support

### Get Involved

- **Documentation**: [docs/PROTOCOL_GUIDE.md](docs/PROTOCOL_GUIDE.md)
- **Smart Contracts**: [basescan.org](https://basescan.org/address/0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644)

### Contributing

This is a proprietary protocol. For partnership and integration enquiries, contact **contact@tokenisys.xyz**

---

## License

**Proprietary License**

Copyright © 2026 Tokenisys. All rights reserved.

This software and its associated documentation are proprietary and confidential. Unauthorised copying, modification, distribution, or use is strictly prohibited without explicit written permission from Tokenisys.

The protocol is available for partnership, integration, and licensing opportunities.

### Contact

**Tokenisys** — Architects of tokenised economic systems

📧 **Email**: contact@tokenisys.xyz
🌐 **Protocol**: [META-VE on Base](https://basescan.org/address/0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644)
📚 **Documentation**: [Technical Handbook](docs/TECHNICAL_HANDBOOK.md)

---


**Built for the Aerodrome ecosystem on Base**

[![Base](https://img.shields.io/badge/Built%20on-Base-0052FF)](https://base.org)
[![Aerodrome](https://img.shields.io/badge/Integrated%20with-Aerodrome-00D395)](https://aerodrome.finance)

*Transforming vote-escrowed governance into liquid DeFi primitives*


