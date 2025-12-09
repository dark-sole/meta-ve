# META-VE Protocol

**Autonomous Vote-Escrow Liquidity Layer for Aerodrome**

META-VE wraps veAERO into liquid, composable tokens while maintaining full voting power. The protocol operates autonomously with no active treasury management—all asset flows are handled programmatically through smart contracts.

---

## Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| META Token | [`0xCCDB07280eeDc221b81D14038A7f7C7f87d5b9C5`](https://basescan.org/address/0xCCDB07280eeDc221b81D14038A7f7C7f87d5b9C5) |
| V-AERO | [`0xBA3639F0c4C4aB72A88aA76f0dd07C5D1c083d97`](https://basescan.org/address/0xBA3639F0c4C4aB72A88aA76f0dd07C5D1c083d97) |
| C-AERO | [`0xF8304F37B9dfc16a0c43625159A308851D20683f`](https://basescan.org/address/0xF8304F37B9dfc16a0c43625159A308851D20683f) |
| R-AERO | [`0x99a0CA6E2c8571EB29D78137d9C3FF2006b9AAf8`](https://basescan.org/address/0x99a0CA6E2c8571EB29D78137d9C3FF2006b9AAf8) |
| VeAeroSplitter | [`0x8082dF869B67067d05De583Ea3550FCEE4A24B22`](https://basescan.org/address/0x8082dF869B67067d05De583Ea3550FCEE4A24B22) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            USER DEPOSITS                                 │
│                           veAERO NFT (locked)                           │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          VeAeroSplitter                                  │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ DEPOSIT SPLIT                                                     │   │
│  │   V-AERO: 90% user │ 1% Tokenisys │ 9% META contract             │   │
│  │   C-AERO: 99% user │ 1% Tokenisys                                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ FEE SPLIT (Trading Fees)                                         │   │
│  │   50% → C-AERO holders (via globalFeeIndex)                      │   │
│  │   50% → META.receiveFees() → S to stakers, (1-S) to LP gauge     │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    V-AERO       │    │    C-AERO       │    │      META       │
│  Voting Token   │    │  Capital Token  │    │   Governance    │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • Gauge voting  │    │ • 50% AERO fees │    │ • Stake & vote  │
│ • Passive vote  │    │ • META rewards  │    │ • Dual rewards  │
│ • Bribe claims  │    │ • Transferable  │    │ • LP incentives │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## The VE Split Mechanism

When a user deposits a veAERO NFT, the protocol mints two separate tokens representing the decomposed rights:

### V-AERO (Voting Token)
- Represents voting power for gauge direction
- Non-transferable while locked for voting
- Used for gauge voting, passive voting, and liquidation confirmation

### C-AERO (Capital Token)
- Represents economic rights to trading fees
- Fully transferable (ERC-20)
- Receives 50% of trading fees plus META incentives from VE pool allocations

### Deposit Split Distribution

| Recipient | V-AERO | C-AERO | Purpose |
|-----------|--------|--------|---------|
| User | 90% | 99% | Primary owner |
| Tokenisys | 1% | 1% | IP fee |
| META Contract | 9% | — | Protocol voting power |

The 9% V-AERO accumulated in META functions as the protocol's governance flywheel, voted 50% passively (following the collective) and 50% for the META-AERO liquidity pool.

---

## DeltaForce Emission Model

META emissions follow a decay curve called **DeltaForce**, which modulates the emission rate based on staking participation.

### Core Formula

```
Daily Emission (I) = P × (1 - P) × K × U

Where:
  P = Progress factor (percentage of max supply minted, ∈ [0,1])
  K = Pre-calculated constant controlling issuance speed
  U = Utilisation factor = 4 × S × (1 - S)
  S = Staking ratio (staked META / circulating META)
```

### The Utilisation Function

The U factor creates a parabolic relationship with staking ratio S:

| Staking Ratio (S) | Utilisation (U) | Emission Impact |
|-------------------|-----------------|-----------------|
| 0% | 0 | No emissions |
| 25% | 0.75 | 75% of maximum |
| **50%** | **1.00** | **Maximum rate** |
| 75% | 0.75 | 75% of maximum |
| 100% | 0 | No emissions |

### Economic Rationale

The parabolic utilisation curve:
- **Protects bootstrapping:** When S = 0, no emissions; tokens are not wasted
- **Targets equilibrium:** Maximum emissions at S = 50% encourage balance
- **Discourages hoarding:** As S → 1, emissions decline
- **Self-regulates:** System tends toward interior equilibrium without intervention

### Emission Distribution

Once minted, emissions are allocated via fixed fractions:

| Recipient | Percentage | Formula |
|-----------|------------|---------|
| Treasury | 5% | Fixed |
| META Stakers | Variable | (1 - S) × 95% |
| VE Pools (C-AERO) | Variable | S/2 × 95% |
| LP Gauge | Variable | S/2 × 95% |

---

## Dynamic Incentive vs Fee Distribution

The fee distribution is **intentionally inverted** relative to emissions:

### Fee Flow

```
Trading Fees (100%)
       │
       ├──► 50% to C-AERO holders (direct via globalFeeIndex)
       │
       └──► 50% to META.receiveFees()
                  │
                  ├──► S portion → META stakers
                  │
                  └──► (1-S) portion → LP gauge
```

### Inverse Relationship

| Recipient | META Emissions | AERO Fees | Net Effect |
|-----------|----------------|-----------|------------|
| META Stakers | (1 - S) | S | High S → more fees, fewer emissions |
| LP Gauge | S/2 | (1 - S) | Low S → more fee subsidy |

### Why Inversion Works

- **Early stage (low S):** LP gauge receives more fee revenue, subsidising liquidity bootstrapping
- **Mature stage (high S):** Stakers receive more fee revenue as reward for commitment
- **Equilibrium:** Around S = 50%, incentives to stake and provide liquidity are balanced

### Distribution at S = 50%

| Recipient | META Emissions | AERO Fees |
|-----------|----------------|-----------|
| C-AERO Holders | — | 50% |
| META Stakers | 46.1% | 25% |
| VE Pools | 23.05% | — |
| LP Gauge | 23.05% | 25% |
| Treasury | 5% | — |

---

## Epoch Timeline

All operations align with Aerodrome's weekly epoch (Thursday 00:00 UTC → Thursday 00:00 UTC).

| Time (UTC) | Window | Available Actions |
|------------|--------|-------------------|
| Thu 00:00 | Epoch start | Tokens unlock, new epoch begins |
| Thu 00:01 – Wed 21:44 | Deposit window | `depositVeAero()`, `vote()`, `lockAndVote()` |
| Wed 21:45 – 22:00 | Deposit closed | Consolidation preparation |
| Wed 22:00 – Thu 00:00 | Execution window | `executeGaugeVote()` |
| Wed 23:00 – Thu 00:00 | Snapshot window | `snapshotForBribes()`, `pushVote()` |

---

## Integrated Locking & Anti-Gaming

### Epoch-Based Lock Architecture

| Action | Token | Lock Duration | Unlock Trigger |
|--------|-------|---------------|----------------|
| `VToken.vote()` | V-AERO | Until epoch end | Epoch rollover |
| `CToken.voteEmissions()` | C-AERO | Until epoch end | Epoch rollover |
| `META.lockAndVote()` | META | Until epoch end | Epoch rollover |
| `confirmLiquidation()` | V-AERO | Until resolution | Liquidation end |
| `voteLiquidation()` | C-AERO | Until resolution | Liquidation end |

### Transfer Settlement

On C-AERO transfers, the `onCTokenTransfer` hook prevents windfall attacks:
- Sender's unclaimed fees swept to treasury
- Receiver assigned current `globalFeeIndex` (no windfall)
- Existing holders receive weighted average checkpoint

---

## META Staking

```solidity
META.lockAndVote(amount, vePoolAddress)  // Stake and vote
META.initiateUnlock()                     // Start ~2 day cooldown
META.completeUnlock()                     // Withdraw after cooldown
META.claimRewards()                       // Claim META + AERO
```

Stakers earn:
- **(1-S) share** of META emissions
- **S share** of AERO fees routed through META

---

## Liquidation Process

Protocol wind-down requires supermajority consent through 6 phases:

| Phase | Name | Threshold | Duration |
|-------|------|-----------|----------|
| 0 | Normal | — | Ongoing |
| 1 | CLock | Any C-AERO locked | Instant |
| 2 | CVote | ≥25% C-AERO | 90 days |
| 3 | VConfirm | ≥75% C-AERO | 1 epoch |
| 4 | Approved | ≥50% V-AERO | 7 days |
| 5 | Closed | Claim window expires | Final |

R-AERO tokens are minted 1:1 for C-AERO locked during CVote, representing claims on underlying veAERO NFTs.

---

## Vested Interest Model (No Keepers)

The protocol removes keeper dependency by ensuring every critical action can be triggered profitably by participants:

| Function | When | Who Benefits |
|----------|------|--------------|
| `collectFees()` | After trades | C-AERO holders, META stakers |
| `updateIndex()` | Daily | META stakers, VE pools, LPs |
| `pushToLPGauge()` | After fees/emissions | LP gauge participants |
| `executeGaugeVote()` | Wed 22:00 – Thu 00:00 | All V-AERO voters |
| `pushVote()` | Wed 23:00 – Thu 00:00 | META protocol |

---

## Gas Optimisations

| Technique | Benefit |
|-----------|---------|
| Index-based claims | O(1) complexity regardless of time elapsed |
| Bitpacked vote storage | ~80% storage savings vs plain mappings |
| Immutable addresses | Bytecode constants vs SLOAD |
| Lazy epoch transitions | First user pays reset; others benefit |

---

## Security

- **CEI Pattern:** All functions follow Checks-Effects-Interactions
- **Reentrancy Guards:** OpenZeppelin ReentrancyGuard on state-changing functions
- **Transfer Settlement:** Prevents fee windfall attacks on C-AERO transfers
- **Epoch Locks:** Voting locks tokens until epoch end, preventing vote-and-dump
- **Bribe Snapshots:** 1-hour window prevents last-second sniping

---

## Build & Deploy

### Requirements

- [Foundry](https://book.getfoundry.sh/)
- Base RPC URL
- Deployer private key with ETH for gas

### Build

```bash
forge build
```

### Deploy

```bash
export BASE_RPC_URL=https://mainnet.base.org
export PRIVATE_KEY=0x...

forge script script/DeployMainnet_V4.s.sol:DeployMainnet_V4 \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  --verify
```

---

## Governance

The MSIG (`0xeAcf5B81136db1c29380BdaCDBE5c7e1138A1d93`) handles only high-level governance:

- Whitelisting VE pools
- Updating contract addresses
- LP pool/gauge configuration

**No withdrawal or funding responsibilities**—all value flows are programmatic.

---

## License

```
SPDX-License-Identifier: UNLICENSED
© 2025 Tokenisys. All rights reserved.
Caveat Utilitator
```
