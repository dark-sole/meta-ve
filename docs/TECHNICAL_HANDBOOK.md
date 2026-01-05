<![CDATA[# META-VE Technical Handbook

**Version:** 1.0  
**Date:** January 2026  
**Status:** Production - Mainnet Deployed  
**Network:** Base Mainnet (Chain ID: 8453)  
**Deployment Block:** 40,414,704  
**Source of Truth:** Smart Contract Source Code

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Smart Contract Architecture](#2-smart-contract-architecture)
3. [Design Principles](#3-design-principles)
4. [Core Contracts](#4-core-contracts)
5. [Reward Distribution Contracts](#5-reward-distribution-contracts)
6. [Support Libraries](#6-support-libraries)
7. [Cross-Chain Infrastructure](#7-cross-chain-infrastructure)
8. [Reward Claim Paths](#8-reward-claim-paths)
9. [User Flows](#9-user-flows)
10. [Economic Mechanics](#10-economic-mechanics)
11. [Security Model](#11-security-model)
12. [Epoch Timeline](#12-epoch-timeline)
13. [Contract Addresses](#13-contract-addresses)
14. [Error Reference](#14-error-reference)
15. [Event Reference](#15-event-reference)

---

## 1. Executive Summary

### 1.1 Purpose

META-VE is a fully autonomous token economic system that decomposes Aerodrome's veAERO NFTs into fungible, tradeable tokens. The protocol creates liquid capital markets while preserving voting rights through a multi-token model.

### 1.2 Token Model

| Token | Symbol | Purpose | Rights |
|-------|--------|---------|--------|
| **Voting Token** | V-AERO | Voting rights | Gauge voting, emissions voting, liquidation confirmation |
| **Capital Token** | C-AERO | Capital rights | Trading fees, rebase claims, META rewards, bribe claims |
| **Receipt Token** | R-AERO | Liquidation receipt | Claims on liquidated NFT value |
| **META** | META | Governance & incentives | Staking rewards, VE pool voting, LP incentives |

### 1.3 Contract Inventory

| Contract | File | Size | Purpose |
|----------|------|------|---------|
| VeAeroSplitter | VeAeroSplitter.sol | 24,236 bytes | NFT custody, token minting, fee/rebase distribution |
| Meta | Meta.sol | 19,258 bytes | META token, DeltaForce emissions, staking |
| CToken | CToken.sol | 9,776 bytes | Capital rights token, fee/META claims |
| VToken | VToken.sol | 9,222 bytes | Voting rights token, gauge voting |
| L1ProofVerifier | L1ProofVerifier.sol | 6,203 bytes | Cross-L2 state proofs |
| VeAeroBribes | VeAeroBribes.sol | 5,353 bytes | Bribe snapshot and claims |
| VeAeroLiquidation | VeAeroLiquidation.sol | 4,367 bytes | Liquidation phase management |
| RToken | RToken.sol | 2,383 bytes | Liquidation receipt token |
| VoteLib | VoteLib.sol | 2,106 bytes | Multi-NFT vote distribution |
| EmissionsVoteLib | EmissionsVoteLib.sol | ~800 bytes | Fed emissions vote tracking |
| DynamicGaugeVoteStorage | DynamicGaugeVoteStorage.sol | Library | Bitpacked vote storage |
| DynamicPoolRegistry | DynamicPoolRegistry.sol | Library | Pool index management |

### 1.4 Key Features

| Feature | Description |
|---------|-------------|
| **Transfer Windfall Protection** | Sweep on `amount` transferred (not balance), round-UP checkpoints |
| **Bribe Deadline** | Users must claim bribes before Wed 23:00 UTC |
| **Auto-Rebase Collection** | `resetEpoch()` attempts rebase collection automatically |
| **Cached Vote Totals** | Bribe snapshots use cached `totalVLockedForVoting` |
| **EmissionsVoteLib** | Fed emissions voting in separate library |
| **141 Fork Tests** | Live mainnet verification on Base |

---

## 13. Contract Addresses

### 13.1 META-VE Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| **VeAeroSplitter** | `0x341f394086D6877885fD2cC966904BDFc2620aBf` |
| **VToken (V-AERO)** | `0x2B214E99050db935FBF3479E8629B2E3078DF61a` |
| **CToken (C-AERO)** | `0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD` |
| **RToken (R-AERO)** | `0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908` |
| **Meta** | `0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051` |
| **VeAeroLiquidation** | `0xad608ecD3b506EB35f706bBb67D817aCe873B8eB` |
| **VeAeroBribes** | `0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB` |
| **VoteLib** | `0x2dE16D98569c6CB352F80fc6024F5C86F3Ef47c5` |
| **EmissionsVoteLib** | `0x5a301a802B0C4BD5389E3Dc31eeB54cf37c65324` |

### 13.2 Aerodrome Contracts (External)

| Contract | Address |
|----------|---------|
| AERO Token | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` |
| VotingEscrow | `0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4` |
| Voter | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` |
| EpochGovernor | `0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497` |

### 13.3 Role Addresses

| Role | Address |
|------|---------|
| META MSIG (Owner) | `0xA50b0109E44233721e427CFB8485F2254E652636` |
| Liquidation MSIG | `0xCF4b81611228ec9bD3dCF264B4bD0BF37283D24D` |
| Tokenisys | `0x432E67d6adF9bD3d42935947E00bF519ecCaA5cB` |
| Treasury | `0xF25a1bB1c463df34E3258ac090e8Fc0895AEC528` |

### 13.4 Deployment Info

| Parameter | Value |
|-----------|-------|
| Deployment Block | 40,414,704 |
| Chain ID | 8453 |
| Genesis Time | 1767571200 (Jan 4, 2026 00:00 UTC) |
| Deployment TX | `0x1c63aa1f145dda7b45f3ce87c41d5d429fae9184a424c1b2bee737aebc2314a0` |

---

*For complete technical details, see the full handbook in the project repository.*

---

© 2026 Tokenisys. All rights reserved.
]]>