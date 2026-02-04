# META-VE Technical Handbook

**Version:** 2.0 (DELTA)  
**Date:** January 2026  
**Status:** Production - Mainnet Deployed  
**Network:** Base Mainnet (Chain ID: 8453)  
**Deployment Block:** 40,414,704  
**Source of Truth:** Smart Contract Source Code

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architectural Philosophy](#2-architectural-philosophy)
3. [Contract Separation of Concerns](#3-contract-separation-of-concerns)
4. [VeAeroSplitter - The Central Hub](#4-veaerosplitter---the-central-hub)
5. [Token Contracts](#5-token-contracts)
6. [Reward Distribution Architecture](#6-reward-distribution-architecture)
7. [Gas Optimization Strategies](#7-gas-optimization-strategies)
8. [Security Model](#8-security-model)
9. [Index-Based Accounting](#9-index-based-accounting)
10. [Epoch Mechanics](#10-epoch-mechanics)
11. [Liquidation System](#11-liquidation-system)
12. [Cross-Chain Architecture](#12-cross-chain-architecture)
13. [Contract Reference](#13-contract-reference)
14. [Deployment Addresses](#14-deployment-addresses)

---

## 1. System Overview

### 1.1 Problem Statement

Vote-escrowed (VE) tokens like Aerodrome's veAERO are powerful governance primitives but suffer from fundamental illiquidity. Users must permanently lock AERO to receive veAERO NFTs, gaining voting rights and fee claims but losing capital flexibility. META-VE solves this by decomposing the NFT into fungible components.

### 1.2 The VE Split

When a user deposits a veAERO NFT, the protocol mints two distinct ERC-20 tokens:

```
veAERO NFT (1000 AERO locked)
    |
    +---> V-AERO (900 to user, 10 to Tokenisys, 90 to Meta)
    |     [Voting rights: gauge direction, emissions voting, liquidation confirmation]
    |
    +---> C-AERO (990 to user, 10 to Tokenisys)
          [Capital rights: trading fees, rebase claims, META rewards, bribes]
```

**Why 90/10 V-AERO split?**
- 90% to user: Primary voting power
- 1% to Tokenisys: IP/protocol fee
- 9% to Meta contract: Protocol-controlled voting power for META-AERO LP incentives

**Why 99/1 C-AERO split?**
- 99% to user: Full capital rights
- 1% to Tokenisys: IP/protocol fee

### 1.3 Token Model

| Token | Symbol | Type | Transferable | Purpose |
|-------|--------|------|--------------|---------|
| Voting Token | V-AERO | ERC-20 | Yes* | Gauge voting, emissions voting |
| Capital Token | C-AERO | ERC-20 | Yes* | Fee claims, META rewards, bribes |
| Receipt Token | R-AERO | ERC-20 | Yes | Liquidation redemption claims |
| META | META | ERC-20 | Yes | Protocol incentive token |

*Subject to epoch locks when used for voting

---

## 2. Architectural Philosophy

### 2.1 Design Principles

**Principle 1: No Keepers Required**

Every protocol action is executed by parties with vested interest:
- Depositors call `depositVeAero()` to receive tokens
- Voters call `vote()` to direct emissions
- Claimants call `claimFees()` to receive rewards
- Anyone can call `executeGaugeVote()` (MEV opportunity / public good)

**Principle 2: CEI Compliance**

All functions follow Checks-Effects-Interactions pattern:
```solidity
function claimFees() external nonReentrant {
    // CHECKS
    uint256 pending = _pendingFees(msg.sender);
    if (pending == 0) revert NothingToClaim();
    
    // EFFECTS
    userFeeCheckpoint[msg.sender] = globalFeeIndex;
    
    // INTERACTIONS
    AERO_TOKEN.safeTransfer(msg.sender, pending);
}
```

**Principle 3: Immutable Core Logic**

- Fee percentages are `constant` (compile-time)
- External contract addresses are `immutable` (constructor-set)
- No proxy patterns - deployed code is final
- Admin functions limited to configuration, not logic changes

**Principle 4: Gas Efficiency Over Code Clarity**

Where trade-offs exist, gas efficiency wins:
- Bitpacked storage for vote weights
- Index-based distribution (O(1) claims)
- Lazy evaluation (update on interaction)
- Whole-token math where precision allows

### 2.2 Trust Assumptions

| Component | Trust Level | Rationale |
|-----------|-------------|-----------|
| Aerodrome VotingEscrow | Full | External dependency, audited |
| Aerodrome Voter | Full | External dependency, audited |
| META MSIG | Configuration only | Cannot extract funds |
| Tokenisys | Fee recipient | Receives protocol fees |
| Users | Adversarial | All user inputs validated |

---

## 3. Contract Separation of Concerns

### 3.1 Why Multiple Contracts?

The protocol spans 9 deployed contracts plus 2 libraries. This separation exists for:

1. **EIP-170 Compliance**: Ethereum limits contract bytecode to 24,576 bytes
2. **Single Responsibility**: Each contract handles one domain
3. **Upgrade Isolation**: Bugs in one component don't require full redeploy
4. **Gas Optimization**: Smaller contracts = cheaper deployment and calls

### 3.2 Contract Dependency Graph

```
                    +------------------+
                    |   VotingEscrow   |  (Aerodrome - External)
                    |    (veAERO)      |
                    +--------+---------+
                             |
                             | NFT custody
                             v
+-------------+    +------------------+    +-------------+
|   VToken    |<---|  VeAeroSplitter  |--->|   CToken    |
| (V-AERO)    |    |   (Central Hub)  |    |  (C-AERO)   |
+------+------+    +--------+---------+    +------+------+
       |                    |                     |
       |                    |                     |
       v                    v                     v
+-------------+    +------------------+    +-------------+
|   VoteLib   |    |      Meta        |    |   RToken    |
| (Multi-NFT) |    |   (Emissions)    |    |  (R-AERO)   |
+-------------+    +------------------+    +-------------+
                            |
       +--------------------+--------------------+
       |                    |                    |
       v                    v                    v
+-------------+    +------------------+    +-------------+
|VeAeroBribes |    |VeAeroLiquidation |    |EmissionsVote|
| (Snapshots) |    |    (Winddown)    |    |    Lib      |
+-------------+    +------------------+    +-------------+
                                                  |
                                           +------+------+
                                           | FeeSwapper  |
                                           | (Non-AERO)  |
                                           +-------------+
```

### 3.3 Contract Size Analysis

| Contract | Bytecode Size | % of Limit | Primary Concern |
|----------|---------------|------------|-----------------|
| VeAeroSplitter | 24,236 bytes | 98.6% | NFT custody, claims |
| Meta | 19,258 bytes | 78.4% | Emissions, staking |
| CToken | 9,776 bytes | 39.8% | Capital token, fees |
| VToken | 9,222 bytes | 37.5% | Voting token |
| L1ProofVerifier | 6,203 bytes | 25.2% | Cross-chain proofs |
| VeAeroBribes | 5,353 bytes | 21.8% | Bribe distribution |
| VeAeroLiquidation | 4,367 bytes | 17.8% | Liquidation phases |
| FeeSwapper | ~3,500 bytes | 14.2% | Non-AERO conversion |
| RToken | 2,383 bytes | 9.7% | Receipt token |
| VoteLib | 2,106 bytes | 8.6% | Vote calculation |
| EmissionsVoteLib | ~800 bytes | 3.3% | Fed vote tracking |

VeAeroSplitter is at 98.6% of the limit - any feature additions require extraction to libraries.

---

## 4. VeAeroSplitter - The Central Hub

### 4.1 Responsibilities

VeAeroSplitter is the protocol's nerve center, handling:

1. **NFT Custody**: Receives, holds, and consolidates veAERO NFTs
2. **Token Minting**: Calls `mint()` on VToken and CToken
3. **Fee Distribution**: Collects from Aerodrome, distributes to C-AERO holders (direct 50%) and Meta (50%)
4. **Rebase Distribution**: Claims emissions, mints new V+C tokens
5. **Vote Execution**: Aggregates votes, calls Aerodrome Voter
6. **Bribe Handling**: Collects bribes, coordinates with VeAeroBribes
7. **Transfer Settlement**: Handles C-AERO transfer hooks (re-indexing)
8. **FeeSwapper Coordination**: Routes non-AERO tokens to FeeSwapper, receives converted AERO via callback

### 4.2 NFT Consolidation Strategy

**Problem**: Aerodrome allows maximum 30 pools per vote. With multiple NFTs, voting becomes complex.

**Solution**: Consolidate all deposited NFTs into a single "master NFT":

```solidity
function depositVeAero(uint256 tokenId) external {
    // Transfer NFT to contract
    VOTING_ESCROW.safeTransferFrom(msg.sender, address(this), tokenId);
    
    if (masterNftId == 0) {
        // First deposit becomes master
        masterNftId = tokenId;
    } else {
        // Queue for consolidation
        pendingNftIds.push(tokenId);
        pendingNftBlock = block.number;
    }
    
    // Mint tokens...
}

function _consolidateAll() internal {
    for (uint256 i = 0; i < count; i++) {
        // Unlock permanent lock temporarily
        VOTING_ESCROW.unlockPermanent(nftsToMerge[i]);
        // Merge into master
        VOTING_ESCROW.merge(nftsToMerge[i], masterNftId);
    }
}
```

**Why queue consolidation?**
- Aerodrome's `merge()` requires the source NFT to have NOT voted
- Deposited NFTs may have voted in current epoch
- Queue until next block ensures Aerodrome state is settled

### 4.3 State Variables Explained

```solidity
// === NFT STATE ===
uint256 public masterNftId;           // The consolidated NFT holding all locked AERO
uint256[] public pendingNftIds;       // NFTs awaiting consolidation
uint256 public pendingNftBlock;       // Block when pending NFTs were added

// === EPOCH STATE ===
uint256 public currentEpoch;          // Monotonically increasing epoch counter
uint256 public epochEndTime;          // Thursday 00:00 UTC
uint256 public votingStartTime;       // Thursday 00:01 UTC (epoch start + 1 hour)
uint256 public votingEndTime;         // Wednesday 22:00 UTC (epoch end - 2 hours)
bool public voteExecutedThisEpoch;    // Prevents double execution
uint256 public cachedTotalVLockedForVoting;  // Snapshot for bribe calculations

// === DISTRIBUTION INDICES ===
uint256 public globalFeeIndex;        // AERO fees per C-AERO (scaled by 1e18)
uint256 public globalRebaseIndex;     // Rebase growth factor (scaled by 1e18)
// NOTE: META distribution moved to CToken in DELTA
// globalMetaIndex, userMetaCheckpoint removed from Splitter

// === USER CHECKPOINTS ===
mapping(address => uint256) public userFeeCheckpoint;     // Last claimed fee index
mapping(address => uint256) public userRebaseCheckpoint;  // Last claimed rebase index

// === FEESWAPPER ===
address public feeSwapper;            // FeeSwapper contract for non-AERO conversion
```

### 4.4 Critical Functions

**`depositVeAero(tokenId)`**
- Validates: permanent lock, not voted, minimum amount
- Transfers NFT to contract
- Mints V-AERO and C-AERO with fee splits
- Initializes user checkpoints at current global indices

**`executeGaugeVote()`**
- Aggregates all V-AERO votes (active + passive)
- Calls Aerodrome Voter with consolidated weights
- Can only be called in execution window (Wed 22:00 - Thu 00:00)
- Anyone can call (MEV opportunity)

**`collectFees(feeDistributors, tokens)`**
- Claims fee tokens from Aerodrome fee distributors
- AERO: Splits 50% to C-AERO holders (updates globalFeeIndex), 50% to Meta
- Non-AERO: Routes to FeeSwapper for conversion

**`processSwappedFees(uint256 amount)`**
- Callback from FeeSwapper only
- Receives converted AERO from FeeSwapper
- Splits 50/50 and updates globalFeeIndex, same as direct AERO

**`claimFees()`**
- Calculates user's pending: `balance * (globalIndex - userCheckpoint) / PRECISION`
- Updates checkpoint to current global
- Transfers AERO to user

---

## 5. Token Contracts

### 5.1 VToken (V-AERO)

**Purpose**: Represents voting rights in the protocol.

**Key Design Decisions**:

1. **Epoch-Based Locking**: When users vote, their tokens are locked until epoch ends
```solidity
mapping(address => uint256) public lockedAmount;
mapping(address => uint256) public lockedUntil;

function _update(address from, address to, uint256 amount) internal override {
    if (from != address(0)) {
        uint256 unlocked = balanceOf(from) - lockedAmount[from];
        if (amount > unlocked) revert InsufficientUnlockedBalance();
    }
    super._update(from, to, amount);
}
```

2. **Bitpacked Vote Storage**: Uses DynamicGaugeVoteStorage library
```solidity
// Each pool weight uses 18 bits (max 262,143 votes per pool)
// 14 pools fit in one uint256 slot
// 100 pools = 8 storage slots instead of 100
```

3. **Wei Input, Whole Token Storage**: User-facing functions accept wei, internal storage uses whole tokens
```solidity
function vote(address pool, uint256 amount) external {
    uint256 wholeTokens = amount / 1e18;  // Convert wei to whole
    if (wholeTokens * 1e18 != amount) revert MustVoteWholeTokens();
    // Store wholeTokens...
}
```

### 5.2 CToken (C-AERO)

**Purpose**: Represents capital rights (fees, rewards, bribes).

**Key Design Decisions**:

1. **Debt-Based META Accounting**: Preserves rewards across transfers
```solidity
uint256 public metaPerCToken;
mapping(address => uint256) public userMetaDebt;
mapping(address => uint256) public userClaimableMeta;

function _checkpointUser(address user) internal {
    uint256 balance = balanceOf(user);
    uint256 owed = (balance * metaPerCToken / PRECISION) - userMetaDebt[user];
    userClaimableMeta[user] += owed;
}

function _updateUserDebt(address user) internal {
    userMetaDebt[user] = balanceOf(user) * metaPerCToken / PRECISION;
}
```

2. **Debt-Based AERO Fee Accounting** (DELTA addition): Parallel to META
```solidity
IERC20 public aero;
uint256 public feePerCToken;
mapping(address => uint256) public userFeeDebt;
mapping(address => uint256) public userClaimableFee;

function _checkpointUserFee(address user) internal {
    uint256 balance = balanceOf(user);
    uint256 owed = (balance * feePerCToken / PRECISION) - userFeeDebt[user];
    userClaimableFee[user] += owed;
}

function _updateUserFeeDebt(address user) internal {
    userFeeDebt[user] = balanceOf(user) * feePerCToken / PRECISION;
}
```

3. **Transfer Hook**: Notifies Splitter for settlement
```solidity
function _update(address from, address to, uint256 amount) internal override {
    if (from != address(0)) {
        _checkpointUser(from);
        _checkpointUserFee(from);
    }
    super._update(from, to, amount);
    
    // Notify Splitter for transfer settlement
    if (from != address(0) && to != address(0) && splitter != address(0)) {
        IVeAeroSplitter(splitter).onCTokenTransfer(from, to, amount);
    }
}
```

4. **Emissions Voting**: C-AERO holders vote on Aerodrome's "Fed" emissions rate
```solidity
function voteEmissions(int8 choice, uint256 amount) external nonReentrant {
    // CHECKS
    if (choice < -1 || choice > 1) revert InvalidChoice();
    if (amount == 0) revert ZeroAmount();
    if (amount % 1e18 != 0) revert MustVoteWholeTokens();  // INPUT IS WEI

    // Timing checks
    uint256 votingStart = _splitter.votingStartTime();
    uint256 votingEnd = _splitter.votingEndTime();
    if (block.timestamp < votingStart) revert VotingNotStarted();
    if (block.timestamp > votingEnd) revert VotingEnded();

    uint256 available = unlockedBalanceOf(msg.sender);
    if (available < amount) revert InsufficientUnlockedBalance();

    // EFFECTS
    uint256 epochEnd = _splitter.epochEndTime();
    if (block.timestamp >= lockedUntil[msg.sender]) {
        lockedAmount[msg.sender] = amount;      // SETS (previous lock expired)
    } else {
        lockedAmount[msg.sender] += amount;     // ADDS to existing lock
    }
    lockedUntil[msg.sender] = epochEnd;

    // INTERACTIONS
    emissionsVoteLib.recordVote(msg.sender, choice, amount / 1e18);  // DIVIDES to whole
    emit EmissionsVoted(msg.sender, choice, amount);
}
```

**Key**: Input is **wei** that must be whole-token multiples. `recordVote` receives `amount / 1e18` (whole tokens). Lock logic checks if previous lock expired (set vs add).

### 5.3 RToken (R-AERO)

**Purpose**: Liquidation receipt token - claims on underlying NFT value.

**Simplest contract**: Only minted during liquidation approval, burned on redemption.

```solidity
// Only Splitter can mint (during approved liquidation)
function mint(address to, uint256 amount) external onlySplitter {
    _mint(to, amount);
}

// Anyone can burn their own tokens
function burn(uint256 amount) external {
    _burn(msg.sender, amount);
}
```

### 5.4 Meta

**Purpose**: Protocol incentive token with algorithmic emissions.

**DeltaForce Emission Model**:
```
Daily emission = TOTAL_SUPPLY * k * P * (1-P) * U(S)

Where:
- P = baseIndex (progress toward max supply, 0 to 1)
- k = 0.00239 (base growth rate)
- U(S) = 4 * S * (1-S) (utilization function)
- S = staking ratio (totalLockedVotes / circulating supply)
```

This creates:
- Maximum emissions at 50% staking ratio
- Natural equilibrium pressure toward 50% staking
- Emissions decay as supply approaches cap

---

## 6. Reward Distribution Architecture

### 6.1 Reward Streams

C-AERO and V-AERO holders receive rewards through distinct mechanisms:

| Reward | Token | Source | Mechanism | Who Claims |
|--------|-------|--------|-----------|------------|
| Splitter Fees | AERO | Aerodrome pools (50% direct) | Index-based (globalFeeIndex) | C-AERO holders |
| CToken Fees | AERO | Aerodrome pools (via Meta) | Debt-based (feePerCToken) | C-AERO holders |
| META Rewards | META | DeltaForce emissions | Debt-based (metaPerCToken) | C-AERO holders |
| Rebase | V+C-AERO | Aerodrome emissions | Mint on claim | C-AERO holders |
| Bribes | Various | Aerodrome bribes | Snapshot-based | V-AERO voters |
| LP Incentives | META | DeltaForce emissions | Gauge deposit | LP providers |

### 6.2 Fee Distribution Flow (DELTA)

```
Aerodrome Pools
      |
      | Trading activity generates fees
      v
+------------------+
|  Fee Distributor |
+--------+---------+
         |
         | collectFees()
         v
+------------------+
|  VeAeroSplitter  |
+--------+---------+
         |
    +----+----+--------------------+
    |         |                    |
    |     AERO tokens        Non-AERO tokens
    |         |                    |
    |    +----+----+               v
    |    |         |        +-------------+
    |   50%       50%       | FeeSwapper  |
    |    |         |        +------+------+
    |    v         v               |
    |+-------+  +------+    processSwappedFees()
    ||C-AERO |  | Meta |          |
    ||holders|  |      |     +----+----+
    ||(claim  |  +--+---+    |         |
    || via    |     |       50%       50%
    ||Splitter|+----+----+   |         |
    |+-------+|         |   v         v
    |         v         v (same as direct AERO)
    |       S * 50%  (1-S) * 50%
    |         |         |
    |         v         v
    |    +--------+  +---------+
    |    | Stakers|  | CToken  |
    |    | (Meta  |  | (claim  |
    |    |  claim)|  |  via    |
    |    +--------+  | CToken) |
    |                +---------+
```

### 6.3 Index-Based Distribution Deep Dive

**Why indices instead of iteration?**

Naive approach (O(n) per distribution):
```solidity
// DON'T DO THIS
function distributeToAll(uint256 amount) external {
    for (uint256 i = 0; i < holders.length; i++) {
        uint256 share = amount * balanceOf(holders[i]) / totalSupply();
        pendingRewards[holders[i]] += share;
    }
}
```

Index approach (O(1) per distribution, O(1) per claim):
```solidity
// DO THIS
function distribute(uint256 amount) external {
    globalIndex += amount * PRECISION / totalSupply();
}

function claim() external {
    uint256 pending = balanceOf(msg.sender) * (globalIndex - userCheckpoint[msg.sender]) / PRECISION;
    userCheckpoint[msg.sender] = globalIndex;
    transfer(msg.sender, pending);
}
```

**Mathematical Proof**:

Let `G_n` = global index after n distributions
Let `U_i` = user checkpoint when user last claimed
Let `B` = user balance

User's pending = `B * (G_n - U_i) / PRECISION`
             = `B * (sum of all distributions since U_i) / totalSupply`
             = Exact pro-rata share

---

## 7. Gas Optimization Strategies

### 7.1 Storage Packing

Meta contract packs related variables into single slots:

```solidity
// PACKED SLOT 0: Core index state (256 bits total)
uint128 public baseIndex;           // 128 bits - emission progress
uint64 public lastUpdateDay;        // 64 bits - last update timestamp
uint64 public pendingCatchupDays;   // 64 bits - days needing processing

// PACKED SLOT 1: Treasury state (256 bits total)
uint128 public treasuryBaselineIndex;  // 128 bits
uint128 public treasuryAccrued;        // 128 bits
```

Gas savings: ~20,000 gas per transaction touching multiple fields (SLOAD is 2,100 gas cold, 100 warm).

### 7.2 Bitpacked Vote Storage

DynamicGaugeVoteStorage packs multiple pool weights into single slots:

```solidity
// Configuration
uint256 constant BITS_PER_POOL = 18;      // Max 262,143 votes per pool
uint256 constant POOLS_PER_SLOT = 14;     // 14 * 18 = 252 bits used per slot

// Storage: user => slot_index => packed_weights
mapping(address => mapping(uint256 => uint256)) internal voteSlots;

function setVoteWeight(address user, uint256 poolIndex, uint256 weight) internal {
    uint256 slotIndex = poolIndex / POOLS_PER_SLOT;
    uint256 bitOffset = (poolIndex % POOLS_PER_SLOT) * BITS_PER_POOL;
    
    uint256 slot = voteSlots[user][slotIndex];
    uint256 mask = ((1 << BITS_PER_POOL) - 1) << bitOffset;
    
    slot = (slot & ~mask) | ((weight & ((1 << BITS_PER_POOL) - 1)) << bitOffset);
    voteSlots[user][slotIndex] = slot;
}
```

Storage comparison for 100 pools:
- Naive: 100 storage slots = 100 * 20,000 = 2,000,000 gas (cold writes)
- Packed: 8 storage slots = 8 * 20,000 = 160,000 gas (cold writes)

**92% gas reduction**.

### 7.3 Immutable vs Constant

```solidity
// CONSTANT: Compiled into bytecode, zero gas to read
uint256 public constant PRECISION = 1e18;

// IMMUTABLE: Set in constructor, stored in code (not storage)
// Reads cost ~3 gas vs 2,100 for storage
IERC20 public immutable AERO_TOKEN;
```

### 7.4 Whole Token Math

Where precision allows, use whole tokens to avoid division:

```solidity
// Voting uses whole tokens (no fractional votes needed)
function vote(address pool, uint256 amount) external {
    uint256 wholeTokens = amount / 1e18;
    // Store wholeTokens directly - no precision loss concerns
}

// Claims use full precision (fractional rewards matter)
function pendingFees(address user) public view returns (uint256) {
    return balanceOf(user) * (globalIndex - userCheckpoint[user]) / PRECISION;
}
```

### 7.5 Lazy Evaluation

State updates happen only when needed:

```solidity
modifier ensureCurrentEpoch() {
    if (block.timestamp >= epochEndTime) {
        _resetEpoch();  // Only called when actually stale
    }
    _;
}
```

---

## 8. Security Model

### 8.1 Access Control Matrix

| Function | Caller | Validation |
|----------|--------|------------|
| `depositVeAero()` | Anyone | NFT ownership, permanent lock, not voted |
| `vote()` | V-AERO holder | Balance check, voting window |
| `claimFees()` | C-AERO holder | Pending > 0 |
| `executeGaugeVote()` | Anyone | Execution window, not already executed |
| `collectFees()` | Anyone | None (MEV-incentivized) |
| `processSwappedFees()` | FeeSwapper only | `msg.sender == feeSwapper` |
| `setSplitter()` | Owner | One-time only (reverts if set) |
| `transferOwnership()` | Owner | Irreversible |

### 8.2 Transfer Settlement (Windfall Protection — DELTA Re-indexing)

**Problem**: When C-AERO transfers, unclaimed rewards could be "sniped":
1. Alice has 100 C-AERO with 10 AERO pending
2. Alice transfers 100 C-AERO to Bob
3. Bob immediately claims 10 AERO (Alice's rewards!)

**Solution**: `onCTokenTransfer()` hook handles two-layer settlement:

**Layer 1: CToken debt/claimable (handled in CToken._update)**
```solidity
// Before super._update():
_checkpointUser(from);      // Crystallize META owed → userClaimableMeta
_checkpointUserFee(from);   // Crystallize AERO owed → userClaimableFee
// After super._update():
_updateUserDebt(from);      // Reset debt to new balance * index
_updateUserDebt(to);        // Set debt for new balance * index
```

**Layer 2: Splitter re-indexing (DELTA)**
```solidity
function onCTokenTransfer(address from, address to, uint256 amount) external {
    if (from == to) return;  // Self-transfer guard
    
    uint256 cSupply = C_TOKEN.totalSupply();
    
    // Re-index sender's unclaimed fees to all holders
    uint256 fromFeeCheckpoint = userFeeCheckpoint[from];
    if (fromFeeCheckpoint == 0) fromFeeCheckpoint = PRECISION;
    uint256 unclaimedFees = (amount * (globalFeeIndex - fromFeeCheckpoint)) / PRECISION;
    if (unclaimedFees > 0 && cSupply > 0) {
        globalFeeIndex += (unclaimedFees * PRECISION) / cSupply;
    }
    // Sender checkpoint UNCHANGED - can still claim on remaining balance
    
    // Recipient checkpoint: blend with round-UP
    if (toBalanceBefore == 0) {
        userFeeCheckpoint[to] = globalFeeIndex;
    } else {
        uint256 toBalanceAfter = toBalanceBefore + amount;
        userFeeCheckpoint[to] = ((toBalanceBefore * tfc) + (amount * globalFeeIndex) + toBalanceAfter - 1) / toBalanceAfter;
    }
}
```

**Why re-indexing instead of sweep?** Transferred-amount unclaimed fees benefit ALL C-AERO holders proportionally, not a single recipient like Tokenisys. This is more equitable.

**Why round UP?**
Prevents dust accumulation attack:
1. Attacker sends 1 wei repeatedly
2. Each transfer slightly lowers recipient checkpoint
3. After many transfers, recipient has windfall

Round-UP ensures recipient checkpoint is always >= weighted average.

### 8.3 Reentrancy Protection

All external-facing functions with state changes use `nonReentrant`:

```solidity
function claimFees() external nonReentrant {
    // ...
}
```

Combined with CEI pattern, this provides defense-in-depth.

---

## 9. Index-Based Accounting

### 9.1 The Two Splitter Indices

| Index | Purpose | Updates When | Initial Value |
|-------|---------|--------------|---------------|
| `globalFeeIndex` | AERO per C-AERO | `collectFees()` / `processSwappedFees()` | 1e18 |
| `globalRebaseIndex` | Rebase growth factor | `updateRebaseIndex()` | 1e18 |

*Note: META distribution uses CToken's debt-based `metaPerCToken` index, not a Splitter global index.*

### 9.2 Fee Index Mathematics

```
After distribution of F fees to supply S:

globalFeeIndex_new = globalFeeIndex_old + (F * PRECISION / S)

User pending = balance * (globalIndex_new - userCheckpoint) / PRECISION
            = balance * (F * PRECISION / S) / PRECISION
            = balance * F / S
            = user's pro-rata share
```

### 9.3 Rebase Index Mathematics

Rebase is different - it represents growth of the underlying NFT:

```
NFT locked amount grows from L_old to L_new due to Aerodrome emissions

growth = L_new - L_old
globalRebaseIndex_new = globalRebaseIndex_old * L_new / L_old

User claim = C_balance * (globalRebaseIndex_new - userRebaseCheckpoint) / PRECISION
```

This mints NEW V-AERO and C-AERO tokens proportional to existing C-AERO balance.

---

## 10. Epoch Mechanics

### 10.1 Timeline (UTC)

```
Thursday 00:00    |<-- Epoch Start / Tokens Unlock
Thursday 00:01    |<-- Voting Opens / Deposits Open
   ...            |    [Voting Window: ~167 hours]
Wednesday 21:00   |<-- META pushVote() window starts
Wednesday 21:45   |<-- Deposits Close
Wednesday 22:00   |<-- Voting Ends / Execution Window Opens
Wednesday 22:00   |<-- Bribe Snapshot Window Opens
Wednesday 23:00   |<-- Bribe Claim Deadline
Wednesday 23:00   |<-- Tokenisys Sweep Window Opens
Wednesday 23:59   |<-- Sweep Window Closes
Thursday 00:00    |<-- Next Epoch Starts
```

### 10.2 Why These Windows?

**Deposits close at 21:45**: Ensures all NFTs can be consolidated before vote execution.

**Voting ends at 22:00**: Gives 2 hours for execution and snapshot before epoch flip.

**Bribe deadline at 23:00**: Prevents indefinite bribe lockup while giving 1 hour to claim.

**Sweep window 23:00-23:59**: Tokenisys can sweep unclaimed bribes to prevent permanent lockup.

---

## 11. Liquidation System

### 11.1 Purpose

Liquidation allows protocol wind-down when stakeholders consent. It's deliberately slow and requires supermajority from both C and V holders.

### 11.2 Phases

| Phase | Name | Entry Condition | Actions Available |
|-------|------|-----------------|-------------------|
| 0 | Normal | Default | All normal operations |
| 1 | CLock | Any C locked | `voteLiquidation()` |
| 2 | CVote | 25% C locked | 90-day voting period |
| 3 | VConfirm | 75% C voted | `confirmLiquidation()` by V holders |
| 4 | Approved | 50% V confirmed | `claimRTokens()` within 7 days |
| 5 | Closed | 7 days after approval | NFT withdrawal by MSIG |

### 11.3 Thresholds

- **25% C-AERO**: Required to start formal voting
- **75% C-AERO**: Required to move to V-AERO confirmation
- **50% V-AERO**: Required to approve liquidation
- **90 days**: Voting period prevents flash governance
- **7 days**: R-AERO claim window

---

## 12. Cross-Chain Architecture

### 12.1 Base as Hub

All governance and staking occurs on Base. Remote chains (Optimism, Arbitrum, etc.) are consumers that receive allocations.

### 12.2 L1 Proof Verification

Remote chains verify Base state via L1 state proofs:

```
1. L1Block predeploy --> L1 block hash
2. L1 block header --> state root
3. L2OutputOracle proof --> Base state root
4. Account proof --> Meta contract exists
5. Storage proof --> Read storage slot value
```

---

## 13. Contract Reference

### 13.1 VeAeroSplitter Functions

| Function | Access | Purpose |
|----------|--------|---------|
| `depositVeAero(tokenId)` | Public | Deposit veAERO NFT |
| `consolidatePending()` | Public | Merge pending NFTs |
| `vote(pool, amount)` | V-AERO holder | Vote for gauge |
| `votePassive(amount)` | V-AERO holder | Follow active voters |
| `executeGaugeVote()` | Public | Submit votes to Aerodrome |
| `collectFees(dists, tokens)` | Public | Claim fees from Aerodrome |
| `claimFees()` | C-AERO holder | Claim AERO fees (Splitter direct share) |
| `processSwappedFees(amount)` | FeeSwapper only | Process converted AERO from FeeSwapper |
| `collectRebase()` | Public | Claim emissions from Aerodrome |
| `claimRebase()` | C-AERO holder | Mint rebase V+C tokens |
| `collectBribes(bribes, tokens)` | Public | Claim bribes from Aerodrome |
| `resetEpoch()` | Public | Advance to next epoch |
| `setFeeSwapper(address)` | Owner | Set FeeSwapper address |

### 13.2 CToken Functions

| Function | Access | Purpose |
|----------|--------|---------|
| `collectMeta()` | Public | Pull META from Meta contract |
| `claimMeta()` | Holder | Claim META rewards |
| `collectFees()` | Public | Pull AERO from Meta contract |
| `claimFees()` | Holder | Claim AERO fees (Meta share) |
| `voteEmissions(choice, amount)` | Holder | Vote on Fed emissions (wei input) |
| `voteLiquidation(amount)` | Holder | Vote for liquidation |
| `pendingFees(user)` | View | Preview pending AERO (includes uncollected) |
| `pendingMeta(user)` | View | Preview pending META (includes uncollected) |

### 13.3 FeeSwapper Functions

| Function | Access | Purpose |
|----------|--------|---------|
| `swap()` | Public | Convert all pending non-AERO to AERO |
| `swapSingle(token)` | Public | Convert single token to AERO |
| `setRoute(token, routes)` | Owner | Configure swap route |
| `disableToken(token)` | Owner | Disable token for swapping |
| `enableToken(token)` | Owner | Re-enable disabled token |
| `setSplitter(address)` | Owner | Set Splitter callback |
| `setSlippage(uint256)` | Owner | Set slippage tolerance |
| `sweepDust(tokens, to)` | Owner | Recover stuck dust |

---

## 14. Deployment Addresses

### 14.1 META-VE Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| VeAeroSplitter | `0xC12F5D7ebce4bB34f5D88b49f1dd7d78f210C644` |
| VToken (V-AERO) | `0x88898d9874bF5c5537DDe4395694abCC6D8Ede52` |
| CToken (C-AERO) | `0xB2EDF371E436E2F8dF784a1AFe36B6f16c01573D` |
| RToken (R-AERO) | `0x6A7B717Cbc314D3fe6102cc37d3B064BD3ccA3D8` |
| Meta | `0x776b081bF1B6482422765381b66865043dbA877D` |
| VeAeroLiquidation | `0xa3957D4557f71e2C20015D4B17987D1BF62f8e08` |
| VeAeroBribes | `0x472Fe0ddfA0C0bA6ff4b0c5a4DC2D7f13A646420` |
| VoteLib | `0xFaCf7D32906150594E634c0D6bf70312235c0a33` |
| EmissionsVoteLib | `0xA2633aa2f3cBAa9289597A1824355bc28c58804a` |
| FeeSwapper | `0xa295BC5C11C1B0D49cc242d9fBFD86fE05Dc7cD2` |

### 14.2 Aerodrome Contracts (External)

| Contract | Address |
|----------|---------|
| AERO Token | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` |
| VotingEscrow | `0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4` |
| Voter | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` |
| EpochGovernor | `0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497` |

### 14.3 Role Addresses

| Role | Address | Capabilities |
|------|---------|--------------|
| META MSIG | `0xA50b0109E44233721e427CFB8485F2254E652636` | Configuration only |
| Liquidation MSIG | `0xCF4b81611228ec9bD3dCF264B4bD0BF37283D24D` | Post-liquidation NFT custody |
| Tokenisys | `0x432E67d6adF9bD3d42935947E00bF519ecCaA5cB` | Fee recipient |
| Treasury | `0xF25a1bB1c463df34E3258ac090e8Fc0895AEC528` | Emission recipient |

### 14.4 Deployment Info

| Parameter | Value |
|-----------|-------|
| Deployment Block | 40,414,704 |
| Chain ID | 8453 |
| Genesis Time | 1767571200 (Jan 4, 2026 00:00 UTC) |
| Deployment TX | `0x1c63aa1f145dda7b45f3ce87c41d5d429fae9184a424c1b2bee737aebc2314a0` |

---

Copyright 2026 Tokenisys. All rights reserved.
