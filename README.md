# META-VE Protocol

**Autonomous Vote-Escrow Liquidity Layer for Aerodrome**

META-VE wraps veAERO into liquid, composable tokens while maintaining full voting power. The protocol operates autonomously with no active treasury management.

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
│  │   V-AERO: 90% user │ 1% treasury │ 9% META contract              │   │
│  │   C-AERO: 99% user │ 1% treasury                                 │   │
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
│ • Gauge voting  │    │ • Fee claims    │    │ • Stake & vote  │
│ • Passive vote  │    │ • META rewards  │    │ • Emissions     │
│ • Bribe claims  │    │ • Transferable  │    │ • LP incentives │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## Token Overview

### V-AERO (Voting Token)
Represents the voting power from deposited veAERO NFTs.

- **Gauge Voting:** Direct voting power to specific Aerodrome pools
- **Passive Voting:** Follow the collective vote proportionally
- **Bribe Claims:** Earn bribes from voted pools
- **Locked While Voting:** Tokens lock until epoch end when used to vote

### C-AERO (Capital Token)
Represents economic rights to trading fees and protocol incentives.

- **Fee Revenue:** 50% of trading fees (paid in AERO)
- **META Rewards:** Proportional share of S/2 emission allocation
- **Fully Transferable:** Standard ERC-20, tradeable and composable

### META (Governance Token)
Protocol governance and yield token with dynamic emission mechanics.

- **1B Maximum Supply:** Fixed cap, no additional minting beyond emissions
- **DeltaForce Emissions:** Logistic decay curve modulated by staking ratio
- **Dual Rewards:** Stakers earn both META emissions and AERO fees
- **Vote Direction:** Stakers vote to allocate emissions to VE pools

### R-AERO (Redemption Token)
Issued during protocol liquidation for claims on underlying veAERO NFTs.

---

## DeltaForce Emission Model

META does not use simple linear or fixed annual decay. Instead, it implements a **logistic decay curve** that responds to staking participation.

### Core Formula

```
Daily Emission = P × (1 - P) × K × U

Where:
  P = Progress factor (percentage of max supply minted)
  K = Issuance constant (controls emission speed)
  U = Utilisation factor = 4 × S × (1 - S)
  S = Staking ratio (staked META / circulating META)
```

### Utilisation Dynamics

The U factor creates a parabolic relationship with staking:

| Staking Ratio (S) | Utilisation (U) | Emission Level |
|-------------------|-----------------|----------------|
| 0% | 0 | No emissions |
| 25% | 0.75 | 75% of max |
| 50% | 1.00 | **Maximum** |
| 75% | 0.75 | 75% of max |
| 100% | 0 | No emissions |

This creates a **self-balancing equilibrium** around S = 50%:
- Too few stakers → emissions slow → staking becomes more attractive
- Too many stakers → emissions slow → selling becomes more attractive

### Emission Distribution

| Recipient | Share | Formula |
|-----------|-------|---------|
| Treasury | 5% | Fixed |
| META Stakers | Variable | (1 - S) × 95% |
| VE Pools (C-AERO) | Variable | S/2 × 95% |
| LP Gauge | Variable | S/2 × 95% |

At S = 50%, this produces: 5% treasury, 47.5% stakers, 23.75% VE pools, 23.75% LP gauge.

---

## Fee Distribution

Trading fees from Aerodrome are split 50/50:

```
Trading Fees (100%)
       │
       ├──► 50% to C-AERO holders (direct via globalFeeIndex)
       │
       └──► 50% to META contract
                  │
                  ├──► S portion → META stakers
                  │
                  └──► (1-S) portion → LP gauge
```

### Inverse Incentive Alignment

Emissions and fees are intentionally inverted:

| Recipient | META Emissions | AERO Fees |
|-----------|----------------|-----------|
| META Stakers | (1 - S) | S |
| LP Gauge | S/2 | (1 - S) |

**Rationale:**
- **Early stage (low S):** LP gauge receives more fees, subsidising liquidity bootstrapping
- **Mature stage (high S):** Stakers receive more fees as reward for commitment
- **Equilibrium:** Balanced incentives around S = 50%

---

## Epoch Timeline

All operations align with Aerodrome's weekly epoch (Thursday 00:00 UTC → Thursday 00:00 UTC).

| Window | Time (UTC) | Available Actions |
|--------|------------|-------------------|
| Epoch Start | Thu 00:00 | Tokens unlock, new epoch begins |
| Deposit Window | Thu 00:01 – Wed 21:44 | `depositVeAero()`, `vote()`, `lockAndVote()` |
| Deposit Closed | Wed 21:45 | Preparation for execution |
| Execution Window | Wed 22:00 – Thu 00:00 | `executeGaugeVote()` |
| META Vote Window | Wed 23:00 – Thu 00:00 | `pushVote()` |

---

## Governance

### META Contract Voting Power

The META contract accumulates 9% of all V-AERO from deposits. This voting power is deployed weekly via `pushVote()`:

- **50% Passive:** Follows the collective user vote
- **50% LP Pool:** Directs to META-AERO liquidity gauge

This creates a **flywheel effect** where more deposits → more protocol voting power → stronger LP incentives → deeper liquidity.

### Multisig Responsibilities

The MSIG (`0xeAcf5B81136db1c29380BdaCDBE5c7e1138A1d93`) handles only high-level governance:

- Whitelisting VE pools
- Updating contract addresses
- LP pool/gauge configuration

**No withdrawal or funding responsibilities** — all value flows are programmatic.

---

## Liquidation

Protocol wind-down requires supermajority consent through a 6-phase process:

| Phase | Name | Threshold | Duration |
|-------|------|-----------|----------|
| 0 | Normal | — | Ongoing |
| 1 | CLock | Any C-AERO locked | Instant |
| 2 | CVote | ≥25% C-AERO | 90 days |
| 3 | VConfirm | ≥75% C-AERO | 1 epoch |
| 4 | Approved | ≥50% V-AERO | 7 days |
| 5 | Closed | Claim window expires | Final |

R-AERO tokens are minted 1:1 for C-AERO locked during CVote phase, representing claims on underlying veAERO NFTs.

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
# Set environment
export BASE_RPC_URL=https://mainnet.base.org
export PRIVATE_KEY=0x...

# Deploy
forge script script/DeployMainnet_V4.s.sol:DeployMainnet_V4 \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  --verify
```

---

## Security

- **CEI Pattern:** All functions follow Checks-Effects-Interactions
- **Reentrancy Guards:** OpenZeppelin ReentrancyGuard on state-changing functions
- **Index-Based Claims:** O(1) claim complexity regardless of time elapsed
- **Transfer Settlement:** Prevents fee windfall attacks on C-AERO transfers
- **Epoch Locks:** Voting locks tokens until epoch end, preventing vote-and-dump

---

## License

BUSL-1.1

---

*© 2025 Tokenisys. All rights reserved.*
