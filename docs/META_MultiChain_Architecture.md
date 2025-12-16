# META Multi-Chain Architecture

## Overview

META is a multi-VE aggregator where:
- **Staking & Voting** happen only on Base
- **Fees** stay local on each chain (distributed in native VE token)
- **META Emissions** are distributed across all chains via L1 proofs

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              BASE (Hub Chain)                                │
│                                                                              │
│  Meta.sol                        VeAeroSplitter                             │
│  ├── META token (real)           ├── Wraps veAERO                           │
│  ├── Staking (lockAndVote)       ├── C-AERO + V-AERO                        │
│  ├── Voting (for any VE)         └── AERO fees → Meta.receiveFees()         │
│  ├── Emissions (updateIndex)                                                 │
│  └── Fee distribution (local)                                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                          L1 Ethereum (Trust Anchor)
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           OPTIMISM (Remote Chain)                            │
│                                                                              │
│  LocalMeta.sol                   LocalSplitter (VeVeloSplitter)             │
│  ├── LOCAL META token            ├── Wraps veVELO                           │
│  └── Mint via proof              ├── C-VELO + V-VELO                        │
│                                  └── VELO fees → local distribution         │
│                                                                              │
│  LocalIncentiveClaimer           LocalStakerClaimer                         │
│  ├── Claims C-VELO allocation    ├── Claims staker fee allocation          │
│  └── Claims LP allocation        └── Proves Base stake via L1              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Fee Flow (Local Per Chain)

### Principle
**Fees stay in native token on each chain. No bridging.**

### Base (AERO System)

```
VeAeroSplitter.collectFees()
         │
         ▼
    AERO fees
         │
         ├── 50% → VeAeroSplitter (for veAERO rebase, etc.)
         │
         └── 50% → Meta.receiveFees(amount)
                          │
                          ├── 50% ────────► poolFeeAccrued[C-AERO]
                          │                 C-AERO.claimFeesForVEPool() → AERO
                          │
                          ├── 50% × S ────► feeRewardIndex
                          │                 Stakers claimRewards() → AERO
                          │
                          └── 50% × (1-S) ► poolLPAccruedAero[C-AERO]
                                            pushToLPGauge() → META-AERO gauge
```

### Optimism (VELO System)

```
LocalSplitter.collectFees()
         │
         ▼
    VELO fees
         │
         ├── 50% → LocalSplitter (for veVELO rebase, etc.)
         │
         └── 50% → LocalSplitter.distributeFees(amount)
                          │
                          ├── 50% ────────► C-VELO contract
                          │                 Direct VELO distribution
                          │
                          ├── 50% × S ────► localFeeRewardIndex
                          │                 Stakers claim VELO (with Base proof)
                          │
                          └── 50% × (1-S) ► META-VELO gauge
                                            Direct VELO via notifyRewardAmount()
```

### Staker Fee Claims on Remote Chains

Stakers lock META on Base but earn fees on ALL chains they vote for.

```
User stakes 1000 META on Base, votes for C-VELO

On Optimism:
1. VELO fees accumulate in LocalSplitter.localFeeRewardIndex
2. User calls LocalSplitter.checkpointStake(proof)
   - Proof verifies: "User has 1000 META locked on Base voting for C-VELO"
   - LocalSplitter accrues user's share of VELO fees
3. User calls LocalSplitter.claimFees() → receives VELO

┌─────────────────────────────────────────────────────────────────────────────┐
│ LocalSplitter.sol (Optimism)                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  uint128 public localFeeRewardIndex;    // VELO per staked META             │
│                                                                              │
│  mapping(address => uint128) userFeeBaseline;                               │
│  mapping(address => uint256) userFeeAccrued;                                │
│  mapping(address => uint256) userProvenStake;  // Cached from proof         │
│                                                                              │
│  function checkpointStake(                                                  │
│      address user,                                                          │
│      uint256 lockedAmount,                                                  │
│      address votedPool,                                                     │
│      bytes calldata proof                                                   │
│  ) external {                                                               │
│      // Verify proof of Base Meta state                                     │
│      require(votedPool == C_VELO, "Not voting for this pool");             │
│      require(l1ProofVerifier.verifyBaseStake(user, lockedAmount, proof));  │
│                                                                              │
│      // Accrue fees                                                         │
│      _accrueUserFees(user, lockedAmount);                                   │
│      userProvenStake[user] = lockedAmount;                                  │
│  }                                                                          │
│                                                                              │
│  function claimFees() external returns (uint256 amount) {                   │
│      amount = userFeeAccrued[msg.sender];                                   │
│      userFeeAccrued[msg.sender] = 0;                                        │
│      VELO.transfer(msg.sender, amount);                                     │
│  }                                                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Incentive Flow (META Emissions)

### Principle
**META emissions calculated on Base, distributed by vote share, claimed via L1 proofs.**

### On Base (updateIndex)

```
Meta.updateIndex()
         │
         ▼
    Mint META emissions
         │
         ├── 5% ──────────► Treasury
         │
         ├── (1-S) × 95% ──► Stakers (userAccrued via checkpoint)
         │                   Claimed on Base: claimRewards()
         │
         ├── S/2 × 95% ────► VE Pools by vote share
         │                   ├── poolData[C-AERO].accrued (local)
         │                   └── poolData[C-VELO].accrued (remote)
         │
         └── S/2 × 95% ────► LP Gauges by vote share
                             ├── poolLPAccruedMeta[C-AERO] (local)
                             └── poolLPAccruedMeta[C-VELO] (remote)
```

### Local Claims (Base)

```
C-AERO.claimForVEPool()
         │
         ▼
    META transferred from Meta.sol to C-AERO contract
         │
         ▼
    C-AERO distributes to C-AERO holders

META-AERO Gauge:
    Meta.pushToLPGauge(C-AERO)
         │
         ▼
    gauge.notifyRewardAmount(META, amount)
         │
         ▼
    LP stakers claim from gauge
```

### Remote Claims (Optimism via L1 Proof)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Step 1: Wait for Base output root on L1 (~1-2 hours)                         │
│                                                                              │
│ Step 2: Generate proof of Base state                                         │
│         - Meta.poolData[C-VELO].accrued = X                                 │
│         - Meta.poolLPAccruedMeta[C-VELO] = Y                                │
│                                                                              │
│ Step 3: Submit proof to LocalIncentiveClaimer on Optimism                   │
└─────────────────────────────────────────────────────────────────────────────┘

LocalIncentiveClaimer.claimVEPoolIncentives(proof)
         │
         ├── Verify proof against L1 state root
         │
         ├── Check: amount not already claimed for this epoch
         │
         └── LocalMeta.mint(C-VELO, amount)
                    │
                    ▼
             C-VELO distributes LOCAL META to holders


LocalIncentiveClaimer.claimLPIncentives(proof)
         │
         ├── Verify proof
         │
         └── LocalMeta.mint(META-VELO gauge, amount)
                    │
                    ▼
             gauge.notifyRewardAmount(LOCAL_META, amount)
```

---

## Remote Contract Suite

### Required Contracts (per remote chain)

| Contract | Purpose |
|----------|---------|
| **LocalMeta.sol** | ERC20 with controlled mint (1:1 with Base META allocation) |
| **LocalSplitter.sol** | Wrap local VE, distribute local fees |
| **LocalCToken.sol** | C-token for local VE (e.g., C-VELO) |
| **LocalVToken.sol** | V-token for local VE (e.g., V-VELO) |
| **L1ProofVerifier.sol** | Verify Base state via L1 |
| **LocalIncentiveClaimer.sol** | Claim META emissions with proof |

### LocalMeta.sol

```solidity
contract LocalMeta is ERC20 {
    mapping(address => bool) public isMinter;
    
    modifier onlyMinter() {
        require(isMinter[msg.sender], "Not minter");
        _;
    }
    
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }
    
    // Minters: LocalSplitter, LocalIncentiveClaimer
}
```

### LocalSplitter.sol

```solidity
contract LocalSplitter {
    IERC20 public immutable VELO;
    IERC20 public immutable veVELO;
    LocalMeta public immutable localMeta;
    IL1ProofVerifier public immutable l1ProofVerifier;
    
    address public cToken;      // C-VELO
    address public vToken;      // V-VELO
    address public lpGauge;     // META-VELO gauge
    
    uint128 public localFeeRewardIndex;
    uint256 public totalProvenStake;
    
    mapping(address => uint128) public userFeeBaseline;
    mapping(address => uint256) public userFeeAccrued;
    mapping(address => uint256) public userProvenStake;
    
    // Fee distribution (called after collecting VELO fees)
    function distributeFees(uint256 amount) external {
        uint256 S = _getProvenS();  // Based on proven stakes
        
        uint256 toCToken = amount / 2;
        uint256 remaining = amount - toCToken;
        uint256 toStakers = (remaining * S) / PRECISION;
        uint256 toLP = remaining - toStakers;
        
        // C-VELO gets VELO direct
        VELO.transfer(cToken, toCToken);
        
        // Stakers accrue via index
        if (toStakers > 0 && totalProvenStake > 0) {
            localFeeRewardIndex += uint128((toStakers * PRECISION) / totalProvenStake);
        }
        
        // LP gauge gets VELO direct
        VELO.approve(lpGauge, toLP);
        IGauge(lpGauge).notifyRewardAmount(address(VELO), toLP);
    }
    
    // Checkpoint with L1 proof
    function checkpointStake(
        address user,
        uint256 lockedAmount,
        address votedPool,
        bytes calldata proof
    ) external {
        require(votedPool == cToken, "Wrong pool");
        require(l1ProofVerifier.verifyUserStake(user, lockedAmount, votedPool, proof));
        
        // Accrue pending
        uint256 oldStake = userProvenStake[user];
        if (oldStake > 0) {
            uint128 baseline = userFeeBaseline[user];
            if (localFeeRewardIndex > baseline) {
                uint256 delta = localFeeRewardIndex - baseline;
                userFeeAccrued[user] += (delta * oldStake) / PRECISION;
            }
        }
        
        // Update proven stake
        totalProvenStake = totalProvenStake - oldStake + lockedAmount;
        userProvenStake[user] = lockedAmount;
        userFeeBaseline[user] = localFeeRewardIndex;
    }
    
    function claimFees() external returns (uint256 amount) {
        // Accrue first
        uint256 stake = userProvenStake[msg.sender];
        if (stake > 0) {
            uint128 baseline = userFeeBaseline[msg.sender];
            if (localFeeRewardIndex > baseline) {
                uint256 delta = localFeeRewardIndex - baseline;
                userFeeAccrued[msg.sender] += (delta * stake) / PRECISION;
            }
            userFeeBaseline[msg.sender] = localFeeRewardIndex;
        }
        
        amount = userFeeAccrued[msg.sender];
        userFeeAccrued[msg.sender] = 0;
        VELO.transfer(msg.sender, amount);
    }
}
```

### LocalIncentiveClaimer.sol

```solidity
contract LocalIncentiveClaimer {
    LocalMeta public immutable localMeta;
    IL1ProofVerifier public immutable l1ProofVerifier;
    
    address public cToken;
    address public lpGauge;
    
    mapping(uint256 => bool) public epochClaimed;        // epoch => claimed
    mapping(uint256 => bool) public epochLPClaimed;      // epoch => LP claimed
    
    /**
     * @notice Claim C-token META allocation for an epoch
     */
    function claimVEPoolIncentives(
        uint256 epoch,
        uint256 amount,
        bytes calldata proof
    ) external {
        require(!epochClaimed[epoch], "Already claimed");
        
        // Verify proof of Meta.poolData[cToken].accrued at epoch snapshot
        require(l1ProofVerifier.verifyPoolAccrued(cToken, epoch, amount, proof));
        
        epochClaimed[epoch] = true;
        localMeta.mint(cToken, amount);
    }
    
    /**
     * @notice Claim LP gauge META allocation for an epoch
     */
    function claimLPIncentives(
        uint256 epoch,
        uint256 amount,
        bytes calldata proof
    ) external {
        require(!epochLPClaimed[epoch], "Already claimed");
        
        // Verify proof of Meta.poolLPAccruedMeta[cToken] at epoch snapshot
        require(l1ProofVerifier.verifyLPAccrued(cToken, epoch, amount, proof));
        
        epochLPClaimed[epoch] = true;
        localMeta.mint(address(this), amount);
        localMeta.approve(lpGauge, amount);
        IGauge(lpGauge).notifyRewardAmount(address(localMeta), amount);
    }
}
```

---

## Deployment Checklist

### Phase 1: Base Setup

```
□ Deploy Meta.sol (V8.1)
□ Deploy VeAeroSplitter
□ Deploy C-AERO, V-AERO
□ MSIG: meta.setSplitter(splitter)
□ MSIG: meta.setVToken(vToken)
□ MSIG: meta.addVEPool(cAero, metaAeroGauge)
□ Verify fee distribution works
```

### Phase 2: Prepare for Multi-Chain

```
□ Deploy L1ProofVerifier on Base
□ MSIG: meta.setL1ProofVerifier(verifier)
□ Test proof verification
```

### Phase 3: Add Remote Chain (Optimism)

**On Base:**
```
□ MSIG: meta.whitelistChain(10)  // Optimism
□ MSIG: meta.addVEPool(cVeloAddress, 10, metaVeloGaugeAddress)
```

**On Optimism:**
```
□ Deploy LocalMeta
□ Deploy L1ProofVerifier (verifies Base state)
□ Deploy LocalSplitter
□ Deploy C-VELO, V-VELO
□ Deploy LocalIncentiveClaimer
□ Configure mint authorities on LocalMeta
□ Configure LocalSplitter with correct addresses
□ Test fee distribution
□ Test proof-based claims
```

---

## Epoch Lifecycle

```
Week N:
├── Mon-Wed: Trading generates fees
├── Thu 00:00 UTC: Epoch boundary
│   ├── BASE: updateIndex() - calculates emissions
│   ├── BASE: Snapshot poolData for proof generation
│   └── REMOTE: Fees distributed locally (no delay)
│
├── Thu-Wed: Week N+1 begins
│
└── Thu +2-3 hours: Proof availability
    ├── REMOTE: LocalIncentiveClaimer.claimVEPoolIncentives()
    ├── REMOTE: LocalIncentiveClaimer.claimLPIncentives()
    └── REMOTE: Users can checkpoint stakes for fee claims
```

---

## L1 Proof Timing

### Why Not 7 Days?

The 7-day finality window applies to **withdrawals** where assets are at risk if a fraud proof succeeds. For **state reads** (S value, user stakes, pool accruals), we use recent output roots:

```
Base state changes
       ↓ ~1-2 hours
L1: Output root posted to L2OutputOracle
       ↓ ~minutes
Remote L2: Can read via L1Block predeploy
```

**Total lag: ~2-3 hours**

### Risk Assessment

| Data Type | Risk if Output Reverted | Consequence |
|-----------|-------------------------|-------------|
| S value | Fee split slightly wrong | Self-corrects next epoch |
| User stake | Wrong fee accrual | Minor over/under payment |
| Pool accrued | Wrong incentive mint | Correctable |

In practice, output reversals on Base/Optimism are near-zero probability (permissioned sequencers, no active fraud proofs).

### Why Lag Doesn't Matter

| Data | Update Frequency | ~2hr Lag Impact |
|------|------------------|-----------------|
| S (staking ratio) | Slow-moving (24-48hr unlock) | Negligible |
| Incentives | Daily (midnight) | ~8% of cycle |
| Fees | Weekly (epoch) | ~1% of cycle |

**Conclusion:** Use recent (unfinalized) output roots. The lag is immaterial given update frequencies.

---

## Summary Table

| Component | Base | Remote | Token |
|-----------|------|--------|-------|
| Staking | ✅ lockAndVote() | ❌ | META |
| Voting | ✅ | ❌ | - |
| C-token fees | claimFeesForVEPool() | Direct distribution | AERO/VELO |
| Staker fees | claimRewards() | checkpointStake() + claimFees() | AERO/VELO |
| LP fees | pushToLPGauge() | Direct to gauge | AERO/VELO |
| C-token incentives | claimForVEPool() | claimVEPoolIncentives(proof) | META/LOCAL META |
| LP incentives | pushToLPGauge() | claimLPIncentives(proof) | META/LOCAL META |
| Staker incentives | claimRewards() | ❌ (claim on Base) | META |

---

## Key Design Decisions

1. **Fees stay local** - No bridging complexity, immediate distribution
2. **Native fee tokens** - Users get VELO on Optimism, not bridged AERO
3. **Staker fees require proof** - Must prove Base stake to claim remote fees
4. **Incentives via LOCAL META** - 1:1 with Base allocation, minted on proof
5. **~2-3 hour proof lag** - Output roots posted hourly, negligible vs daily/weekly cycles
6. **Single staking location** - All META staked on Base, simplifies accounting
7. **Same address cross-chain** - User 0xABC on Base claims as 0xABC on Optimism
