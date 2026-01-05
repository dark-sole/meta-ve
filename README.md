<![CDATA[<div align="center">

# META-VE Protocol

**Liquid veAERO on Base**

[![Network](https://img.shields.io/badge/Network-Base%20Mainnet-0052FF)](https://basescan.org)
[![Version](https://img.shields.io/badge/Version-1.0-00D395)](https://github.com/tokenisys/meta-ve)
[![Tests](https://img.shields.io/badge/Tests-833%20Passing-00D395)](docs/TEST_RESULTS.md)
[![Formal Verification](https://img.shields.io/badge/Formal%20Verification-62%2F62-00D395)](docs/TEST_RESULTS.md)
[![License](https://img.shields.io/badge/License-Proprietary-red)](LICENSE)

[Documentation](docs/PROTOCOL_GUIDE.md) · [Technical Reference](docs/TECHNICAL_HANDBOOK.md) · [Test Results](docs/TEST_RESULTS.md) · [Basescan](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf)

</div>

---

## Overview

META-VE is a fully autonomous protocol that decomposes Aerodrome's vote-escrowed NFTs into liquid, tradeable tokens. Convert your permanently locked veAERO into fungible assets while retaining voting power and earning rewards.

### The VE Split

| Deposit | Receive | Purpose |
|---------|---------|---------|
| veAERO NFT | **V-AERO** (90%) | Voting rights for Aerodrome gauges |
| | **C-AERO** (99%) | Capital rights: fees, bribes, META rewards |

### Key Innovations

- **🔀 VE Decomposition** — Separates voting rights from capital claims
- **📈 DeltaForce Emissions** — Algorithmic logistic curve responding to staking participation  
- **🔒 Epoch Locking** — Vote-and-dump prevention via epoch-aligned locks
- **🤖 No Keepers** — All actions executed by vested interest holders
- **🛡️ Hardened Transfers** — Windfall protection with round-UP checkpoints
- **⚡ Gas Optimized** — Bitpacked vote storage, index-based claims

---

## Deployed Contracts (Base Mainnet)

| Contract | Address | Basescan |
|----------|---------|----------|
| **VeAeroSplitter** | `0x341f394086D6877885fD2cC966904BDFc2620aBf` | [↗](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf) |
| **V-AERO** (VToken) | `0x2B214E99050db935FBF3479E8629B2E3078DF61a` | [↗](https://basescan.org/address/0x2B214E99050db935FBF3479E8629B2E3078DF61a) |
| **C-AERO** (CToken) | `0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD` | [↗](https://basescan.org/address/0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD) |
| **R-AERO** (RToken) | `0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908` | [↗](https://basescan.org/address/0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908) |
| **Meta** | `0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051` | [↗](https://basescan.org/address/0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051) |
| **VeAeroBribes** | `0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB` | [↗](https://basescan.org/address/0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB) |
| **VeAeroLiquidation** | `0xad608ecD3b506EB35f706bBb67D817aCe873B8eB` | [↗](https://basescan.org/address/0xad608ecD3b506EB35f706bBb67D817aCe873B8eB) |
| **VoteLib** | `0x2dE16D98569c6CB352F80fc6024F5C86F3Ef47c5` | [↗](https://basescan.org/address/0x2dE16D98569c6CB352F80fc6024F5C86F3Ef47c5) |
| **EmissionsVoteLib** | `0x5a301a802B0C4BD5389E3Dc31eeB54cf37c65324` | [↗](https://basescan.org/address/0x5a301a802B0C4BD5389E3Dc31eeB54cf37c65324) |

**Deployment Block:** [40,414,704](https://basescan.org/block/40414704) · **Chain ID:** 8453 · **Genesis:** January 4, 2026

---

## Quick Start

### Deposit veAERO

```solidity
// 1. Approve NFT transfer
VotingEscrow(0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4).approve(
    0x341f394086D6877885fD2cC966904BDFc2620aBf,  // Splitter
    tokenId
);

// 2. Deposit and receive V-AERO + C-AERO
VeAeroSplitter(0x341f394086D6877885fD2cC966904BDFc2620aBf).depositVeAero(tokenId);
```

### Vote with V-AERO

```solidity
// Active vote for specific gauge
VToken(0x2B214E99050db935FBF3479E8629B2E3078DF61a).vote(gaugeAddress, amountWei);

// Passive vote (follows active voters)
VToken(0x2B214E99050db935FBF3479E8629B2E3078DF61a).votePassive(amountWei);
```

### Claim Rewards (C-AERO holders)

```solidity
CToken cToken = CToken(0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD);

// Trading fees (AERO)
cToken.collectFees();   // Pull from Meta
cToken.claimFees();     // Claim your share

// META rewards
cToken.collectMeta();   // Pull from Meta
cToken.claimMeta();     // Claim your share
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [**Protocol Guide**](docs/PROTOCOL_GUIDE.md) | User-facing quick reference |
| [**Technical Handbook**](docs/TECHNICAL_HANDBOOK.md) | Complete technical specification |
| [**Test Results**](docs/TEST_RESULTS.md) | 833 tests, 62 formal verification properties |
| [**Reward Claim Paths**](docs/REWARD_CLAIM_PATHS.md) | Detailed reward flow documentation |
| [**Admin Rights**](docs/MSIG_ADMIN_RIGHTS.md) | MSIG capabilities and limitations |
| [**Comprehensive Guide (PDF)**](docs/Meta_0126_GUIDE.pdf) | 27-page protocol deep-dive |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AERODROME PROTOCOL                         │
│   VotingEscrow ──► Voter ──► Gauges ──► Rewards                │
└───────────────────────────┬─────────────────────────────────────┘
                            │ NFT Deposits
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      META-VE PROTOCOL                           │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │VeAeroSplitter│───►│   VToken    │───►│  VoteLib    │         │
│  │  (custody)   │    │  (voting)   │    │ (multi-NFT) │         │
│  └──────┬───────┘    └─────────────┘    └─────────────┘         │
│         │                                                       │
│         ├────────────►┌─────────────┐    ┌─────────────┐        │
│         │             │   CToken    │───►│    Meta     │        │
│         │             │  (capital)  │    │ (emissions) │        │
│         │             └─────────────┘    └─────────────┘        │
│         │                                                       │
│         └────────────►┌─────────────┐    ┌─────────────┐        │
│                       │VeAeroBribes │    │VeAeroLiquid │        │
│                       │ (snapshots) │    │  (winddown) │        │
│                       └─────────────┘    └─────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Security

### Verification

| Method | Count | Status |
|--------|-------|--------|
| Unit Tests | 692 | ✅ Pass |
| Fork Tests (Mainnet) | 141 | ✅ Pass |
| Halmos Proofs | 17 | ✅ Proven |
| Echidna Invariants | 21 | ✅ Pass |
| Certora Rules | 24 | ✅ Verified |
| **Total Validations** | **895** | ✅ |

### Security Features

- **Transfer Windfall Protection** — Sweep on `amount` transferred, not balance
- **Round-UP Checkpoints** — Prevents dust accumulation attacks
- **Self-Transfer Guard** — No-op on self-transfers
- **Bribe Claim Deadline** — Wednesday 23:00 UTC cutoff
- **Cached Vote Totals** — Snapshot consistency guarantee

### Admin Model

The protocol uses a **two-tier admin structure** with no asset extraction capability:

- **META MSIG** — Configuration only, cannot withdraw user funds
- **LIQUIDATION MSIG** — Only active during liquidation (supermajority required)

See [Admin Rights](docs/MSIG_ADMIN_RIGHTS.md) for complete details.

---

## Epoch Timeline

| Time (UTC) | Event |
|------------|-------|
| **Thursday 00:00** | Epoch starts, tokens unlock |
| Thu 00:01 - Wed 21:44 | Deposit & voting window |
| **Wednesday 21:00-22:00** | META pushVote() window |
| **Wednesday 22:00** | Voting ends, executeGaugeVote() |
| Wednesday 22:00-23:00 | Bribe snapshot window |
| **Wednesday 23:00** | Bribe claim deadline |
| Wednesday 23:00-23:59 | Tokenisys sweep window |

---

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Base RPC endpoint

### Build

```bash
forge build
```

### Test

```bash
# Unit tests
forge test --no-match-path "test/fork/*" -vvv

# Fork tests (requires BASE_RPC_URL)
forge test --match-path "test/fork/comprehensive/*.sol" --fork-url $BASE_RPC_URL -vvv

# Gas report
forge test --gas-report
```

---

## License

**Proprietary** — © 2026 Tokenisys. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, distribution, or use is strictly prohibited.

---

## Contact

**Tokenisys**  
📧 ds@tokenisys.com

---

<div align="center">

**Built for the Aerodrome ecosystem on Base**

</div>
]]>