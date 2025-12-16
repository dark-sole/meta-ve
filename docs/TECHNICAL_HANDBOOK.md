# V8 Technical Handbook

**META Ecosystem Smart Contract Architecture**

**Version:** 8.0 (December 2025)  
**Status:** Production - Mainnet Deployed  
**Network:** Base Mainnet (Chain ID: 8453)  
**Test Suite:** 341 tests passing (100%)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [VeAeroSplitter](#3-veaerosplitter)
4. [VToken (V-AERO)](#4-vtoken-v-aero)
5. [CToken (C-AERO)](#5-ctoken-c-aero)
6. [RToken (R-AERO)](#6-rtoken-r-aero)
7. [VeAeroBribes](#7-veaerobribes)
8. [VeAeroLiquidation](#8-veaeroliquidation)
9. [Meta Token](#9-meta-token)
10. [Support Libraries](#10-support-libraries)
11. [Economic Mechanics](#11-economic-mechanics)
12. [Security Model](#12-security-model)
13. [Test Coverage](#13-test-coverage)
14. [Appendix](#14-appendix)

---

## 1. Executive Summary

### 1.1 Purpose

The Tokenisys META protocol decomposes Aerodrome's veAERO NFTs into fungible tokens, creating liquid capital markets while preserving voting rights. The system mints two derivative tokens per deposit:

| Token | Purpose | Rights |
|-------|---------|--------|
| **V-AERO** | Voting rights | Gauge voting, emissions voting |
| **C-AERO** | Capital rights | Fee claims, rebase claims, META rewards, bribes |

These form part of a "Super-system" (META-VE) designed to support multiple Vote Escrow (VE) liquidity systems across Ethereum L2s.

### 1.2 V8 Key Changes

| Component | V7 | V8 |
|-----------|------|-----|
| **Meta.addVEPool** | Requires gauge address | **Gauge optional (address(0))** |
| **META Staking** | Blocked until gauge | **Enabled immediately** |
| **LP Rewards** | Required gauge | **Accumulate until gauge set** |

### 1.3 Design Philosophy

| Principle | Implementation |
|-----------|----------------|
| **Separation of Concerns** | Voting (V) separate from Capital (C) |
| **CEI Pattern** | Checks-Effects-Interactions throughout |
| **Index-Based Distribution** | O(1) gas for claims regardless of holder count |
| **Checkpoint-On-Transfer** | Automatic reward settlement on token movements |
| **DeltaForce Emissions** | Logistic growth curve for META issuance |
| **Gas Optimization** | Bitpacked vote storage, packed structs |

---

## 2. Architecture Overview

### 2.1 Contract Dependency Graph

```
                              AERODROME PROTOCOL
                    ┌─────────────────────────────────┐
                    │  VotingEscrow  →  Voter  →  Gauges  │
                    └────────────────┬────────────────┘
                                     │ NFT Deposits
                                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         TOKENISYS V6                                  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                      VeAeroSplitter                              │ │
│  │  • Master NFT custody & consolidation                           │ │
│  │  • V/C token minting (90/1/9 and 99/1 splits)                  │ │
│  │  • Fee collection (50/50 C-holders / Meta)                     │ │
│  │  • Rebase tracking & settlement                                 │ │
│  │  • Gauge vote execution (reads from VToken)                    │ │
│  └───────────────────────────┬─────────────────────────────────────┘ │
│                              │                                        │
│    ┌───────────┬─────────────┼─────────────┬────────────┐            │
│    │           │             │             │            │            │
│    ▼           ▼             ▼             ▼            ▼            │
│ ┌──────┐  ┌──────┐    ┌───────────┐   ┌──────┐   ┌────────────┐     │
│ │VToken│  │CToken│    │VeAeroBribes│  │RToken│   │VeAeroLiq.  │     │
│ │V-AERO│  │C-AERO│    │           │   │R-AERO│   │            │     │
│ └──┬───┘  └──┬───┘    └─────┬─────┘   └──────┘   └────────────┘     │
│    │         │              │                                        │
│    │ VOTE    │              │ Bribe snapshots                        │
│    │ AGGR.   │              │ & claims                               │
│    │         ▼              ▼                                        │
│    │    ┌─────────────────────┐                                      │
│    │    │        META         │                                      │
│    │    │  • DeltaForce Emit  │                                      │
│    │    │  • Staking/Locking  │                                      │
│    │    │  • VE Pool Voting   │                                      │
│    └────┤  • LP Gauge Rewards │                                      │
│         └─────────────────────┘                                      │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐│
│  │                    SUPPORT LIBRARIES                              ││
│  │  • DynamicGaugeVoteStorage (bitpacking)                          ││
│  │  • DynamicPoolRegistry (pool indexing)                           ││
│  │  • VoteLib (multi-NFT distribution)                              ││
│  └──────────────────────────────────────────────────────────────────┘│
│                                                                       │
│  Treasury ◄── 5% META emissions                                      │
│  Tokenisys ◄── 1% deposit fees + swept bribes                        │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow: Wei vs Whole Tokens

```
                    USER INTERFACE
                         │
                         │ 50e18 (WEI)
                         ↓
    ╔════════════════════════════════════════════╗
    ║         VToken.sol - PUBLIC API            ║
    ║                                            ║
    ║  • vote(pool, amount)         [Wei input]  ║
    ║  • votePassive(amount)        [Wei input]  ║
    ║  • totalPassiveVotes()        [Wei out]    ║
    ║  • getPoolVotes(pool)         [Wei out]    ║
    ╚════════════════════════════════════════════╝
                         │
                         │ Converts: 50e18 → 50
                         ↓
    ╔════════════════════════════════════════════╗
    ║      VToken.sol - INTERNAL STORAGE         ║
    ║                                            ║
    ║  • _totalPassiveVotes = 50    [Whole]      ║
    ║  • currentWeights[pool] = 50  [Whole]      ║
    ║  • DynamicGaugeVoteStorage    [Bitpacked]  ║
    ╚════════════════════════════════════════════╝
                         │
                         │ 50 (WHOLE TOKENS)
                         ↓
    ╔════════════════════════════════════════════╗
    ║         VeAeroSplitter.sol                 ║
    ║                                            ║
    ║  getAggregatedVotes()         [Whole out]  ║
    ║  executeGaugeVote()           [Whole]      ║
    ╚════════════════════════════════════════════╝
                         │
                         │ [50] (WHOLE TOKENS ARRAY)
                         ↓
    ╔════════════════════════════════════════════╗
    ║        Aerodrome Voter.vote()              ║
    ║                                            ║
    ║  vote(nftId, pools, [50])     [Whole in]   ║
    ╚════════════════════════════════════════════╝
```

**Rationale:**
- **User APIs:** Wei (ERC20 convention, prevents confusion)
- **Internal Storage:** Whole tokens (gas efficient bitpacking)
- **Aerodrome:** Whole tokens (their API requirement)

---

## 3. VeAeroSplitter

### 3.1 Purpose & Responsibilities

The VeAeroSplitter is the central coordinator and NFT custodian for the protocol. It handles:

1. **NFT Custody:** Receives veAERO NFTs, consolidates into master NFT
2. **Token Minting:** Issues V-AERO and C-AERO on deposits/rebases
3. **Fee Distribution:** Collects Aerodrome trading fees, distributes 50/50
4. **Rebase Tracking:** Monitors veAERO growth, enables minting claims
5. **Vote Execution:** Reads aggregated votes from VToken, submits to Aerodrome
6. **Bribe Coordination:** Collects bribes, allows VeAeroBribes to pull tokens

### 3.2 Design Decisions

**Why Splitter holds NFTs (not users):**
- Aerodrome requires single NFT for voting
- Consolidation enables maximum voting power
- Users get fungible tokens instead

**Why 50/50 fee split:**
- 50% to C-AERO holders (direct capital reward)
- 50% to META (stakers + LP incentives)
- Balances capital vs governance incentives

**Why deposits disabled Wed 21:45:**
- 15 minutes before voting closes
- Prevents last-second deposits gaming vote weights
- Ensures snapshot consistency

### 3.3 State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `masterNftId` | uint256 | Consolidated veAERO NFT ID |
| `pendingNftIds` | uint256[] | NFTs awaiting consolidation |
| `currentEpoch` | uint256 | Current Aerodrome epoch |
| `globalFeeIndex` | uint256 | Fee distribution index (PRECISION scaled) |
| `globalRebaseIndex` | uint256 | Rebase distribution index |
| `adjustedRebaseBacking` | uint256 | Total AERO backing after rebases |
| `voteExecutedThisEpoch` | bool | Whether vote has been submitted |

### 3.4 Timing Windows (V6)

```solidity
// All times relative to Aerodrome epoch (Thursday 00:00 UTC)
votingStartTime  = epochStart + 1 second     // Thu 00:01 UTC
votingEndTime    = epochEnd - 2 hours        // Wed 22:00 UTC
depositCloseTime = votingEndTime - 15 min    // Wed 21:45 UTC
epochEndTime     = epochStart + 7 days       // Thu 00:00 UTC
```

### 3.5 Key Functions

```solidity
// DEPOSITS
depositVeAero(uint256 tokenId)           // Deposit NFT, receive V+C tokens
consolidatePending()                      // Merge pending NFTs into master

// VOTING (V6: Reads from VToken)
executeGaugeVote()                       // Submit aggregated votes to Aerodrome

// FEE DISTRIBUTION
collectFees(address[] pools, ...)        // Claim AERO from Aerodrome gauges
claimFees()                              // User claims their AERO share

// REBASE
updateRebaseIndex()                      // Track veAERO growth
claimRebase()                            // User claims new V+C from rebase

// EPOCH
resetEpoch()                             // Advance to new epoch
```

### 3.6 Gas Costs

| Operation | Gas | Notes |
|-----------|-----|-------|
| `depositVeAero` (first) | ~350,000 | Sets master NFT |
| `depositVeAero` (subsequent) | ~280,000 | Adds to pending |
| `consolidatePending` (10 NFTs) | ~500,000 | Batch merge |
| `executeGaugeVote` (30 pools) | ~450,000 | Max pools |
| `claimFees` | ~65,000 | Index-based |
| `claimRebase` | ~120,000 | With minting |

---

## 4. VToken (V-AERO)

### 4.1 Purpose & Responsibilities

VToken is the **voting rights token** and the **vote aggregation layer** (new in V6). It:

1. **Represents Voting Rights:** 1 V-AERO = 1 vote weight
2. **Aggregates Votes:** Collects all user votes in bitpacked storage
3. **Validates Gauges:** Ensures pools have valid Aerodrome gauges
4. **Manages Locks:** Prevents transfers while votes are active
5. **Distributes Passive:** Proportionally allocates passive votes

### 4.2 Design Decisions

**Why vote aggregation moved to VToken (V6):**
- **Gas Efficiency:** Bitpacking reduces storage costs 8-10x
- **Single Source of Truth:** All vote data in one contract
- **Simplified Splitter:** Splitter just reads and executes
- **Better Separation:** Voting logic separate from custody logic

**Why whole-token voting only:**
- Aerodrome expects integer weights
- Prevents dust attacks (1 wei votes)
- Simplifies bitpacking math

**Why lock-until-epoch-end:**
- Prevents vote-then-transfer gaming
- Ensures vote weight remains locked
- Transfers allowed after epoch ends

### 4.3 Bitpacked Vote Storage

VToken uses `DynamicGaugeVoteStorage` for gas-efficient vote tracking:

```
┌─────────────────────────────────────────────────────────────────┐
│                    256-bit Storage Slot                          │
├─────────────────────────────────────────────────────────────────┤
│ Pool 0 │ Pool 1 │ Pool 2 │ Pool 3 │ Pool 4 │ Pool 5 │ Pool 6 │ │
│ 28 bits│ 28 bits│ 28 bits│ 28 bits│ 28 bits│ 28 bits│ 28 bits│...│
│  Max   │  Max   │  Max   │  Max   │  Max   │  Max   │  Max   │   │
│  268M  │  268M  │  268M  │  268M  │  268M  │  268M  │  268M  │   │
└─────────────────────────────────────────────────────────────────┘
```

**Configuration (calculated at deployment):**
```solidity
struct Config {
    uint32 maxPools;       // Maximum pool index + 1
    uint32 bitsPerPool;    // Bits per weight (28 for 100M supply)
    uint32 poolsPerSlot;   // 256 / bitsPerPool = 9
    uint32 numSlots;       // ceil(maxPools / poolsPerSlot)
    uint256 mask;          // Bitmask for extraction
    uint256 maxWeight;     // Maximum value per pool
}
```

**Example:**
```
Supply: 100M AERO
Bits needed: ceil(log2(100M)) + 1 = 28 bits
Pools per slot: 256 / 28 = 9 pools
For 200 pools: ceil(200 / 9) = 23 slots
Total storage: 23 × 32 bytes = 736 bytes
```

**Without bitpacking:** 200 pools × 32 bytes = 6,400 bytes (8.7x more!)

### 4.4 Vote Flow

```solidity
// User calls vote() with wei
function vote(address pool, uint256 amount) external {
    // CHECKS
    require(amount % 1e18 == 0);           // Whole tokens only
    require(gauge exists && isAlive);       // Valid Aerodrome gauge
    require(inVotingWindow);                // Thu 00:01 - Wed 22:00
    require(unlockedBalance >= amount);     // Has available tokens
    
    // EFFECTS
    lockedAmount[user] += amount;           // Lock tokens
    lockedUntil[user] = epochEnd;           // Until epoch ends
    
    // STORAGE (bitpacked)
    uint256 wholeTokens = amount / 1e18;
    uint256 poolIndex = poolRegistry.getOrRegister(pool);
    currentWeights.addWeight(config, poolIndex, wholeTokens);
}
```

### 4.5 Passive Vote Distribution

Passive votes are distributed proportionally to active votes:

```
Active votes: Pool1=60, Pool2=40 (total=100)
Passive: 100 tokens

Distribution:
- Pool1: 60 + (100 × 60/100) = 60 + 60 = 120
- Pool2: 40 + (100 × 40/100) = 40 + 40 = 80

Total: 200 (100 active + 100 passive)
```

**Rounding:** Integer division may lose 1-2 tokens (acceptable).

### 4.6 State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `lockedAmount` | mapping(address => uint256) | Tokens locked for voting |
| `lockedUntil` | mapping(address => uint256) | Lock expiry timestamp |
| `totalGaugeVotedThisEpoch` | uint256 | Total V-AERO voted this epoch |
| `_totalPassiveVotes` | uint256 | Passive votes (whole tokens) |
| `currentWeights` | PackedWeights | Bitpacked pool weights |
| `poolRegistry` | Registry | Pool address ↔ index mapping |

### 4.7 Key Functions

```solidity
// VOTING
vote(address pool, uint256 amount)        // Vote for specific pool
votePassive(uint256 amount)               // Passive vote (follows majority)

// QUERIES (for Splitter)
getAggregatedVotes()                      // Returns (pools[], weights[])
totalPassiveVotes()                       // Returns total passive (wei)
getPoolVotes(address pool)                // Returns pool weight (wei)

// BALANCE
unlockedBalanceOf(address user)           // Balance available for transfer
lockedAmount(address user)                // Currently locked for voting
```

### 4.8 Test Coverage

```
test_VToken_PassiveVotes_ReturnsWei         ✓ PASS
test_VToken_PoolVotes_ReturnsWei            ✓ PASS
test_VToken_AggregatedVotes_ReturnsWholeTokens  ✓ PASS
test_GaugeVote_MustBeWholeTokens            ✓ PASS
test_GaugeVote_FailsInvalidGauge            ✓ PASS
test_PassiveVote_ProportionalDistribution   ✓ PASS
```

---

## 5. CToken (C-AERO)

### 5.1 Purpose & Responsibilities

CToken is the **capital rights token** representing economic claims:

1. **Fee Claims:** 50% of Aerodrome trading fees (via Splitter)
2. **Rebase Claims:** Pro-rata share of veAERO growth
3. **META Rewards:** S/2 portion of META emissions
4. **Bribe Claims:** Snapshot-based bribe distribution
5. **Emissions Voting:** Vote on AERO emission rate

### 5.2 Design Decisions

**Why separate from VToken:**
- Different use cases (capital vs governance)
- Enables separate markets/pricing
- Users can hold one without the other
- Liquidation affects C and V differently

**Why checkpoint-on-transfer:**
- Prevents fee sniping (buy before claim, sell after)
- Automatic settlement with no user action
- Fair distribution to actual holders

### 5.3 META Distribution Integration

CToken integrates with META for reward distribution:

```solidity
function collectMeta() external {
    // Pull META from Meta contract (CToken is whitelisted VE pool)
    uint256 metaClaimed = meta.claimForVEPool();
    
    if (metaClaimed > 0 && totalSupply() > 0) {
        // Update index
        metaPerCToken += (metaClaimed * PRECISION) / totalSupply();
    }
}

function claimMeta() external {
    _checkpointUser(msg.sender);
    uint256 claimable = userClaimableMeta[msg.sender];
    userClaimableMeta[msg.sender] = 0;
    IERC20(meta).safeTransfer(msg.sender, claimable);
}
```

**Setup Requirement:** CToken must be whitelisted as a VE pool in Meta before it can pull rewards:

```solidity
// MSIG must call on Meta contract:
Meta.addVEPool(CToken, address(0))  // lpGauge can be address(0) in V8
```

This enables:
- `CToken.collectMeta()` → calls `Meta.claimForVEPool()` → pulls META incentives
- `CToken.collectFees()` → calls `Meta.claimFeesForVEPool()` → pulls AERO fees

Without whitelisting, CToken cannot pull rewards from Meta.

### 5.4 Emissions Voting

C-AERO holders vote on AERO emission rate:

| Choice | Effect |
|--------|--------|
| -1 | Vote for decreased emissions |
| 0 | Vote to hold emissions constant |
| +1 | Vote for increased emissions |

```solidity
function voteEmissions(int8 choice, uint256 amount) external {
    require(choice >= -1 && choice <= 1);
    require(amount % 1e18 == 0);  // Whole tokens
    
    // Lock tokens, record vote
    lockedAmount[msg.sender] += amount;
    lockedUntil[msg.sender] = epochEnd;
    
    // Call Splitter to record choice
    splitter.recordEmissionsVote(msg.sender, choice, amount);
}
```

### 5.5 State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `metaPerCToken` | uint256 | META per C-AERO (PRECISION scaled) |
| `userMetaDebt` | mapping | User's META debt for distribution |
| `userClaimableMeta` | mapping | Accumulated claimable META |
| `lockedAmount` | mapping | Tokens locked for voting |
| `lockedUntil` | mapping | Lock expiry timestamp |

---

## 6. RToken (R-AERO)

### 6.1 Purpose

RToken is the **liquidation receipt token**, issued during the liquidation process:

1. **Receipt:** Represents claim on underlying AERO after liquidation
2. **7-Day Window:** Must be claimed within 7 days of liquidation approval
3. **1:1 Backing:** Each R-AERO redeemable for 1 AERO

### 6.2 Design Decisions

**Why separate token:**
- Clean separation of liquidation state
- Transferable receipts (can sell claim)
- Time-bounded claims (unclaimed swept)

**Why 7-day claim window:**
- Prevents indefinite claims blocking capital
- Unclaimed tokens sweep to Tokenisys
- Encourages prompt action

### 6.3 Flow

```
Liquidation Approved
        │
        ▼
  R-AERO Minted → User
        │
        │ (7 days)
        ▼
   User Claims → AERO
        │
  OR (if unclaimed)
        ▼
  Tokenisys Sweep
```

---

## 7. VeAeroBribes

### 7.1 Purpose & Responsibilities

VeAeroBribes handles bribe distribution with snapshot mechanics:

1. **Snapshot Capture:** Records user's locked V-AERO at snapshot time
2. **Pro-Rata Claims:** Distribute bribes proportional to snapshot
3. **Token Filtering:** Blocks AERO (goes to fees instead)
4. **Unclaimed Sweep:** Routes unclaimed bribes to Tokenisys

### 7.2 Design Decisions

**Why separated from Splitter:**
- Gas optimization (separate storage)
- Clean snapshot logic
- Simpler audit surface

**Why snapshot-based:**
- Prevents vote-then-claim gaming
- Fair to voters who held all epoch
- One snapshot per user per epoch

**Why AERO blocked:**
- AERO bribes should go to fee pool
- Prevents double-counting
- Clearer revenue separation

### 7.3 Snapshot Window

```
Wed 22:00 ────────────────────────── Thu 00:00
    │                                    │
    │◄──── SNAPSHOT WINDOW ─────────────►│
    │                                    │
    │  • User calls snapshotForBribes()  │
    │  • Records locked V-AERO           │
    │  • One snapshot per user           │
    │                                    │
```

### 7.4 Key Functions

```solidity
// USER ACTIONS
snapshotForBribes()                      // Record vote power for claims
claimBribes(address[] tokens)            // Claim pro-rata share

// ADMIN
sweepUnclaimedBribes(address[] tokens)   // Route unclaimed to Tokenisys

// INTERNAL (called by Splitter)
pullBribeToken(address token, uint256 amount)  // Pull tokens from Splitter
```

### 7.5 State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `userBribeSnapshot` | mapping(address => uint256) | User's locked V-AERO at snapshot |
| `totalBribeSnapshot` | uint256 | Total locked at epoch snapshot |
| `userSnapshotEpoch` | mapping(address => uint256) | Epoch of user's snapshot |
| `userClaimEpoch` | mapping(address => uint256) | Epoch of last claim |

---

## 8. VeAeroLiquidation

### 8.1 Purpose

VeAeroLiquidation manages the protocol liquidation process through phases:

### 8.2 Liquidation Phases

```
┌─────────────────────────────────────────────────────────────────┐
│                    LIQUIDATION STATE MACHINE                     │
└─────────────────────────────────────────────────────────────────┘

  NONE ──► CLock ──► CVote ──► VConfirm ──► Approved ──► Closed
    │        │         │          │            │           │
    │        │         │          │            │           │
    │     25% C     75% C      50% V        MSIG        7 days
    │     lock      vote      confirm      executes     claim
    │                                                  window
```

| Phase | Threshold | Duration | Description |
|-------|-----------|----------|-------------|
| **CLock** | 25% of C-AERO | Instant trigger | C-holders request liquidation |
| **CVote** | 75% of C-AERO | 90 days | C-holders vote to proceed |
| **VConfirm** | 50% of V-AERO | 90 days | V-holders confirm liquidation |
| **Approved** | - | - | MSIG can execute withdrawal |
| **Closed** | - | 7 days | R-AERO claim window |

### 8.3 Design Decisions

**Why multi-phase:**
- Prevents hostile takeovers
- Both capital AND voting must agree
- 90-day periods allow deliberation

**Why different thresholds:**
- CLock (25%): Low bar to signal concern
- CVote (75%): High bar to actually proceed
- VConfirm (50%): Majority of voters must agree

**Why MSIG executes:**
- Human oversight on NFT withdrawal
- Prevents automated attacks
- Final security check

---

## 9. Meta Token

### 9.1 Purpose & Responsibilities

The META token is the protocol's governance and incentive token:

1. **Governance:** Stakers vote on VE pool allocations
2. **Fee Sharing:** Stakers receive portion of all VE fees
3. **LP Incentives:** Emissions to META-VE liquidity pools
4. **Cross-Chain:** Future multi-VE coordination (Phase 2)

### 9.2 DeltaForce Emission Model

META uses the **Tokenisys DeltaForce** logistic growth curve for emissions:

```
                 LOGISTIC GROWTH CURVE
                 
    1.0 ─────────────────────────────────────────
        │                               ▄▄████████
        │                          ▄▄███▀▀▀▀▀▀
        │                     ▄▄███▀▀
        │                ▄▄███▀▀
  Index │           ▄▄███▀▀
        │       ▄███▀▀
        │    ▄██▀▀
        │  ▄██
    0.0 ─▄█─────────────────────────────────────
        Genesis                              Time
```

**Mathematical Formula:**

```
dP/dt = P × (1 - P) × k × U

Where:
  P = Progress index (0 to 1)
  k = Base growth rate (K_BASE = 2.394e15)
  U = Utilization factor (4 × S × (1-S))
  S = Staking ratio (staked / total supply)
```

**Daily Processing:**

```solidity
function _processDays(uint64 daysToProcess, uint256 U) internal {
    uint128 P = baseIndex;
    
    for (uint64 i = 0; i < daysToProcess; ) {
        // Logistic growth: dP = P × (1-P) × k
        uint256 oneMinusP = PRECISION - uint256(P);
        uint256 baseDelta = (uint256(P) * oneMinusP * K_BASE) / (PRECISION * PRECISION);
        
        // Adjust by utilization: U = 4 × S × (1-S)
        uint256 adjustedDelta = (baseDelta * U) / PRECISION;
        
        // Mint tokens
        uint256 tokensToMint = (TOTAL_SUPPLY * adjustedDelta) / PRECISION;
        _mint(address(this), tokensToMint);
        
        // Update index
        P = uint128(uint256(P) + adjustedDelta);
        if (P >= PRECISION) break;  // Cap at 100%
        
        unchecked { ++i; }
    }
}
```

### 9.3 Utilization Function: 4×S×(1-S)

The utilization function creates a "sweet spot" for staking:

```
    1.0 ─────────────────────────────────────────
        │          ▄▄▄▄▄▄▄▄▄▄▄▄
        │       ▄██▀          ▀██▄
        │     ▄█▀                ▀█▄
   U    │    █▀                    ▀█
        │   █                        █
        │  █                          █
        │ █                            █
    0.0 ─█──────────────────────────────█────────
        0%           50%              100%
                 Staking Ratio (S)
```

| S | U = 4×S×(1-S) | Emissions Rate |
|---|---------------|----------------|
| 0% | 0 | 0% (no stakers = no emissions) |
| 25% | 0.75 | 75% of maximum |
| **50%** | **1.0** | **100% (maximum)** |
| 75% | 0.75 | 75% of maximum |
| 100% | 0 | 0% (all staked = no incentive) |

**Rationale:**
- **S = 0%:** No stakers → no point emitting
- **S = 50%:** Balanced ecosystem → maximum reward
- **S = 100%:** Everyone staked → no liquidity → reduce emissions

### 9.4 Emission Distribution

```
Daily Emissions (95% of minted)
           │
           ├──► 5% Treasury
           │
           ├──► (1-S) × 95% → META Stakers
           │
           ├──► S/2 × 95% → C-Token Holders
           │         │
           │         ├─ Phase 1: All to C-AERO
           │         └─ Phase 2: Split by VOTE_AERO
           │
           └──► S/2 × 95% → LP Incentives
                     │
                     ├─ Phase 1: All to META-AERO gauge
                     └─ Phase 2: Split by VOTE_AERO
```

### 9.5 Fee Distribution

```
Trading Fees (AERO from Aerodrome)
           │
           ├──► 50% → C-AERO holders (direct)
           │
           └──► 50% → META
                     │
                     ├──► S × 50% → META Stakers
                     │
                     └──► (1-S) × 50% → C-AERO (Phase 1)
                                       or FeeContract (Phase 2)
```

### 9.6 Staking Mechanics

```solidity
function lockAndVote(uint256 amount, address vePool) external {
    require(isWhitelistedVEPool[vePool]);
    require(existingLock == 0 || userVotedPool[msg.sender] == vePool);
    
    // CHECKPOINT
    _checkpointUser(msg.sender);
    
    // LOCK
    userLockedAmount[msg.sender] += amount;
    userVotedPool[msg.sender] = vePool;
    poolVotes[vePool] += amount;
    totalLockedVotes += amount;
    
    // TRANSFER
    _transfer(msg.sender, address(this), amount);
}
```

### 9.7 Unlock Mechanics (24-48hr Cooldown)

```
lockAndVote() ─────► Staked/Locked
                         │
                         │ initiateUnlock()
                         ▼
                    Unlocking (24hr minimum)
                         │
                         │ completeUnlock() (after 24hr)
                         ▼
                    Available for transfer
```

**Why 24-48hr:**
- Prevents vote manipulation
- Discourages short-term staking
- Aligns incentives with protocol

### 9.8 pushVote() - V6 Timing Fix

```solidity
function pushVote() external {
    // V6 FIX: Window is 21:00-22:00 (BEFORE voting closes)
    uint256 votingEnd = epochEnd - 2 hours;  // Wed 22:00
    uint256 metaWindowStart = votingEnd - 1 hours;  // Wed 21:00
    
    require(block.timestamp >= metaWindowStart);  // After 21:00
    require(block.timestamp < votingEnd);          // Before 22:00
    
    // Vote Meta's V-tokens for META-AERO LP
    IV_TOKEN.vote(lpPool, totalLockedVotes * 1e18);
}
```

**V5.3 Bug:** Window was 23:00-00:00 (AFTER VToken stopped accepting votes at 22:00)

**V6 Fix:** Window is 21:00-22:00 (within VToken voting window)

### 9.9 State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `baseIndex` | uint128 | DeltaForce progress (0 to 1e18) |
| `lastUpdateDay` | uint64 | Day of last index update |
| `remainingSupply` | uint256 | Unminted META remaining |
| `totalLockedVotes` | uint256 | Total META staked |
| `feeRewardIndex` | uint128 | Fee distribution index |
| `poolVotes` | mapping | Votes per VE pool |
| `userLockedAmount` | mapping | User staked balance |
| `userVotedPool` | mapping | User's voted VE pool |

---

## 10. Support Libraries

### 10.1 DynamicGaugeVoteStorage

**Purpose:** Gas-efficient bitpacked storage for gauge vote weights.

**Key Features:**
- Dynamic configuration based on supply and pool count
- O(1) read/write for individual pool weights
- Automatic slot management

**Configuration Algorithm:**

```solidity
function calculateConfig(uint256 totalSupply, uint256 poolCount, ...) {
    // Calculate bits needed: ceil(log2(supply)) + 1
    uint256 bitsNeeded = log2Ceil(totalSupply) + 1;  // e.g., 28 bits for 100M
    
    // Pools per 256-bit slot
    uint256 poolsPerSlot = 256 / bitsNeeded;  // e.g., 9 pools
    
    // Total slots needed
    uint256 numSlots = (poolCount + poolsPerSlot - 1) / poolsPerSlot;
    
    // Build mask
    uint256 mask = (1 << bitsNeeded) - 1;  // e.g., 0xFFFFFFF for 28 bits
}
```

**Bit Operations:**

```solidity
function addWeight(uint256 poolIndex, uint256 amount) {
    uint256 slot = poolIndex / poolsPerSlot;
    uint256 position = poolIndex % poolsPerSlot;
    uint256 offset = position * bitsPerPool;
    
    // Read, modify, write
    uint256 slotValue = slots[slot];
    uint256 currentWeight = (slotValue >> offset) & mask;
    uint256 newWeight = currentWeight + amount;
    
    slotValue = slotValue & ~(mask << offset);  // Clear
    slotValue = slotValue | (newWeight << offset);  // Set
    
    slots[slot] = slotValue;
}
```

### 10.2 DynamicPoolRegistry

**Purpose:** Maps pool addresses to sequential indices for bitpacking.

**Key Features:**
- O(1) address-to-index lookup
- Auto-registration of new pools
- Sequential index assignment

```solidity
struct Registry {
    mapping(address => uint256) poolToIndex;
    mapping(uint256 => address) indexToPool;
    uint256 nextIndex;
}

function getOrRegister(address pool) returns (uint256 index, bool isNew) {
    index = poolToIndex[pool];
    if (index == 0 && indexToPool[0] != pool) {
        // New pool - assign next index
        index = nextIndex++;
        poolToIndex[pool] = index;
        indexToPool[index] = pool;
        isNew = true;
    }
}
```

### 10.3 VoteLib

**Purpose:** Distributes votes across multiple NFTs when >30 pools are voted.

**Algorithm:**
```
100 pools voted → Need 4 NFTs
NFT 1: Pools 0-29 (highest weights)
NFT 2: Pools 30-59
NFT 3: Pools 60-89
NFT 4: Pools 90-99

Each NFT gets proportional voting power based on weight sum.
```

**Key Functions:**

```solidity
function distributeVotes(address[] pools, uint256[] weights) 
    returns (NFTVote[] memory nftVotes);

function calculateNFTsNeeded(uint256 numPools) returns (uint256);

function previewDistribution(uint256 numPools) returns (uint256[] memory);
```

**Note:** VoteLib integration requires Splitter to be whitelisted for NFT splitting by Aerodrome. Currently, votes are truncated to top 30 pools.

---

## 11. Economic Mechanics

### 11.1 Deposit Splits

| Deposit | V-AERO | C-AERO | Tokenisys | META |
|---------|--------|--------|-----------|------|
| 100 AERO | 90 | 99 | 1 | 9 |

**Rationale:**
- **90% to V:** Voting rights (slightly diluted to fund protocol)
- **99% to C:** Capital rights (near-full economic exposure)
- **1% to Tokenisys:** Protocol sustainability fee
- **9% to META:** Fund staker rewards

### 11.2 Fee Distribution (50/50)

```
Aerodrome Trading Fees
         │
         ├──► 50% C-AERO Holders
         │         │
         │         └─► Index-based distribution
         │
         └──► 50% META Contract
                   │
                   ├──► S portion → Stakers
                   │
                   └──► (1-S) portion → C-AERO (Phase 1)
```

### 11.3 Rebase Distribution

When veAERO grows from 1000 to 1050 AERO (5% rebase):

```
Initial State:
- Master NFT: 1000 AERO locked
- V-AERO supply: 900
- C-AERO supply: 990

After Rebase:
- Master NFT: 1050 AERO locked (+50)
- Rebase amount: 50 AERO

New Minting (for 50 AERO rebase):
- V-AERO: 50 × 0.90 = 45 new tokens
- C-AERO: 50 × 0.99 = 49.5 new tokens
- Tokenisys: 50 × 0.01 = 0.5 AERO equivalent
- META: 50 × 0.09 = 4.5 META rewards
```

### 11.4 Bribe Distribution

```
Bribe Collection (e.g., 1000 USDC)
         │
         │ Wednesday 22:00+
         ▼
   VeAeroBribes holds tokens
         │
         │ Users snapshot their locked V-AERO
         │ Total snapshot: 10,000 V-AERO
         │
         │ User with 1,000 V-AERO snapshot:
         │ Share = 1,000 / 10,000 = 10%
         │ Claim = 1,000 × 10% = 100 USDC
         │
         │ After 7 days:
         ▼
   Unclaimed swept to Tokenisys
```

---

## 12. Security Model

### 12.1 Access Control

| Function | Access | Contract |
|----------|--------|----------|
| `mint` / `burn` | Only Splitter | VToken, CToken |
| `resetEpoch` | Keeper | Splitter |
| `executeGaugeVote` | Keeper | Splitter |
| `pause` / `unpause` | MSIG | Splitter |
| `withdrawNFT` | MSIG + Approved | Splitter |
| `setLPPool` | Owner | Meta |

### 12.2 Reentrancy Protection

All state-changing functions use OpenZeppelin's `ReentrancyGuard`:

```solidity
function claimFees() external nonReentrant {
    // Safe from reentrancy via malicious ERC20
}

function depositVeAero(uint256 tokenId) external nonReentrant {
    // Safe from reentrancy via onERC721Received
}
```

### 12.3 CEI Pattern

All functions follow Checks-Effects-Interactions:

```solidity
function claimBribes(address[] tokens) external {
    // CHECKS
    require(hasSnapshot);
    require(!alreadyClaimed);
    
    // EFFECTS (state changes BEFORE external calls)
    userClaimEpoch[msg.sender] = currentEpoch;
    
    // INTERACTIONS (external calls LAST)
    for (token in tokens) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
```

### 12.4 Flash Loan Resistance

Voting requires **locked tokens**:

```solidity
function vote(address pool, uint256 amount) external {
    // Lock tokens BEFORE recording vote
    lockedAmount[msg.sender] += amount;
    lockedUntil[msg.sender] = epochEnd;
    
    // Vote recorded
}
```

A flash loan cannot:
1. Borrow V-AERO
2. Vote (would lock the borrowed tokens)
3. Return the loan (tokens are locked until epoch end)

### 12.5 Invariants

| Invariant | Test |
|-----------|------|
| V-AERO supply == C-AERO supply × ratio | `test_Invariant_SupplyEquality` |
| Fee index monotonically increasing | `test_Invariant_FeeIndexMonotonic` |
| Locked ≤ Balance for all users | `test_Invariant_CheckpointBound` |
| Sum of balances == total supply | `test_Invariant_SupplyEquality` |

---

## 13. Test Coverage

### 13.1 Test Suite Summary

| Test File | Tests | Coverage |
|-----------|-------|----------|
| VotingTest | 25 | Gauge voting, passive voting |
| BribeTest | 18 | Snapshots, claims, filtering |
| SecurityTest | 19 | Access control, reentrancy |
| AdversarialTest | 22 | Attack vectors |
| VoteConsistencyTest | 21 | Wei/integer conversions |
| MetaTest | 30 | DeltaForce, staking |
| LiquidationTest | 24 | Phase transitions |
| **Total** | **341** | **100% pass rate** |

### 13.2 VoteConsistencyTest Results

```
test_VToken_PassiveVotes_ReturnsWei        ✓ PASS
test_VToken_PoolVotes_ReturnsWei           ✓ PASS
test_Splitter_TotalVLocked_ReturnsWholeTokens  ✓ PASS
test_Bribes_Snapshot_StoresWholeTokens     ✓ PASS
test_VToken_AggregatedVotes_ReturnsWholeTokens  ✓ PASS
test_VoteLib_SingleNFT_Under30Pools        ✓ PASS
test_VoteLib_FourNFTs_100Pools             ✓ PASS
test_VotingPattern_PassiveDistribution     ✓ PASS
```

### 13.3 Security Test Results

```
test_Reentrancy_Deposit_ERC721Callback     ✓ PASS
test_Reentrancy_ClaimFees                  ✓ PASS
test_FlashLoan_VotingPower                 ✓ PASS
test_AccessControl_OnlyMultisig            ✓ PASS
test_Invariant_SupplyEquality              ✓ PASS
test_Adversarial_TimingBoundary            ✓ PASS
test_Adversarial_ProtocolTokenBypass       ✓ PASS
```

---

## 14. Appendix

### 14.1 Error Reference

#### VeAeroSplitter

| Error | Cause |
|-------|-------|
| `NotNFTOwner` | Caller doesn't own the NFT |
| `NFTAlreadyVoted` | NFT has voted this epoch |
| `OnlyPermanentLocksAccepted` | NFT must be permanent lock |
| `DepositsDisabled` | Outside deposit window |
| `VotingNotEnded` | executeGaugeVote called too early |
| `ExecutionWindowClosed` | executeGaugeVote called too late |

#### VToken

| Error | Cause |
|-------|-------|
| `VotingEnded` | Vote after Wed 22:00 |
| `VotingNotStarted` | Vote before Thu 00:01 |
| `MustVoteWholeTokens` | Fractional token vote |
| `InvalidGauge` | Pool has no valid Aerodrome gauge |
| `InsufficientUnlockedBalance` | Amount exceeds unlocked balance |

#### Meta

| Error | Cause |
|-------|-------|
| `MustUnlockToChangePool` | Trying to vote different pool while locked |
| `CooldownNotElapsed` | completeUnlock before 24hr |
| `PoolNotWhitelisted` | Vote for non-whitelisted VE pool |

### 14.2 Event Reference

```solidity
// VeAeroSplitter
event Deposit(address indexed user, uint256 nftId, uint256 vAmount, uint256 cAmount);
event FeesCollected(uint256 amount, uint256 newFeeIndex);
event GaugeVoteExecuted(uint256 epoch, address[] pools, uint256[] weights);
event EpochReset(uint256 newEpoch, uint256 votingStart, uint256 votingEnd);

// VToken
event Voted(address indexed user, address indexed pool, uint256 amount);
event VotedPassive(address indexed user, uint256 amount);
event EpochVotesReset(uint256 newEpoch);

// Meta
event IndexUpdated(uint128 newIndex, uint256 tokensMinted);
event StakeLocked(address indexed user, uint256 amount, address indexed vePool);
event UnlockInitiated(address indexed user, uint256 amount, uint256 unlockTime);
```

### 14.3 Gas Benchmarks

| Operation | Gas | USD @ 20 gwei |
|-----------|-----|---------------|
| `depositVeAero` (first) | 350,000 | $14.00 |
| `depositVeAero` (subsequent) | 280,000 | $11.20 |
| `vote` | 95,000 | $3.80 |
| `votePassive` | 85,000 | $3.40 |
| `executeGaugeVote` (30 pools) | 450,000 | $18.00 |
| `claimFees` | 65,000 | $2.60 |
| `claimRebase` | 120,000 | $4.80 |
| `snapshotForBribes` | 55,000 | $2.20 |
| `Meta.lockAndVote` | 180,000 | $7.20 |
| `Meta.updateIndex` (1 day) | 49,000 | $1.96 |

### 14.4 V6 Timing Quick Reference

| Event | Time (UTC) | Day |
|-------|------------|-----|
| Epoch Start | 00:00 | Thursday |
| Voting Opens | 00:01 | Thursday |
| Deposit Closes | 21:45 | Wednesday |
| Meta Vote Window | 21:00-22:00 | Wednesday |
| Voting Closes | 22:00 | Wednesday |
| Execution Window | 22:00-00:00 | Wed-Thu |
| Aerodrome Deadline | 23:00 | Wednesday |
| Epoch End | 00:00 | Thursday |

### 14.5 Contract Addresses (Mainnet)

| Contract | Address | Verified |
|----------|---------|----------|
| VToken (V-AERO) | `0x56b1c70EC3e5751F513Bb4E1C1B041398413246A` | ✅ |
| CToken (C-AERO) | `0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E` | ✅ |
| RToken (R-AERO) | `0x3dB3fF66d9188694f5b6FA8ccdfF9c3921b77832` | ✅ |
| Meta | `0x24408894b6C34ed11a609db572d5a2d7e7b187C6` | ✅ |
| VeAeroLiquidation | `0x289d982DA03d7DA73EE88F0de8799eBF5B7672cc` | ✅ |
| VeAeroBribes | `0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E` | ✅ |
| VoteLib | `0x16a6359d45386eD4a26458558A0542B826Bb72c0` | ✅ |
| VeAeroSplitter | `0xf47Ece65481f0709e78c58f802d8e76B20fd4361` | ✅ |

### 14.5.1 Key Addresses

| Role | Address |
|------|---------|
| META MSIG (Owner) | `0xA50b0109E44233721e427CFB8485F2254E652636` |
| Liquidation MSIG | `0xCF4b81611228ec9bD3dCF264B4bD0BF37283D24D` |
| Tokenisys | `0x432E67d6adF9bD3d42935947E00bF519ecCaA5cB` |
| Treasury | `0xF25a1bB1c463df34E3258ac090e8Fc0895AEC528` |

### 14.5.2 LP Pool

| Pool | Address |
|------|---------|
| META-AERO LP | `0x0d104dcc18004ebdab2cad67acacbf6986d8a5d5` |
| LP Gauge | Not yet created (Aerodrome governance) |

### 14.6 External Dependencies (Aerodrome)

| Contract | Address | Purpose |
|----------|---------|---------|
| AERO Token | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` | Underlying asset |
| VotingEscrow | `0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4` | veAERO NFTs |
| Voter | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` | Gauge voting |
| EpochGovernor | `0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497` | Emissions voting |

---

*Document Version: 8.0*  
*Deployed: December 16, 2025*  
*Block: 39530457*  
*Test Suite: 341/341 passing*
