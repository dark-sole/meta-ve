<![CDATA[# META-VE Protocol Guide

**Version:** 1.0  
**Network:** Base Mainnet (Chain ID: 8453)  
**Last Updated:** January 2026

A quick reference for interacting with META-VE on Base.

---

## Contract Addresses

### META-VE Contracts

| Contract | Address | Purpose |
|----------|---------|---------|
| **VeAeroSplitter** | `0x341f394086D6877885fD2cC966904BDFc2620aBf` | Deposit veAERO, fee distribution |
| **V-AERO** (VToken) | `0x2B214E99050db935FBF3479E8629B2E3078DF61a` | Gauge voting |
| **C-AERO** (CToken) | `0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD` | Fees, META rewards, emissions voting |
| **R-AERO** (RToken) | `0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908` | Liquidation receipts |
| **Meta** | `0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051` | META token, emissions |
| **VeAeroBribes** | `0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB` | Bribe snapshots & claims |

### Aerodrome Contracts

| Contract | Address |
|----------|---------|
| AERO Token | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` |
| VotingEscrow (veAERO) | `0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4` |
| Aerodrome Voter | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` |

---

## 1. Deposit veAERO

Convert your veAERO NFT into liquid V-AERO and C-AERO tokens.

**Requirements:**
- Permanently locked veAERO NFT
- NFT must not have voted this epoch

**You Receive:**
| Token | Amount | Rights |
|-------|--------|--------|
| **V-AERO** | 90% | Gauge voting, emissions voting |
| **C-AERO** | 99% | Trading fees, META rewards, bribes |

*1% of each goes to Tokenisys as IP fee. 9% of V-AERO goes to META contract.*

```solidity
// Step 1: Approve
VotingEscrow(0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4).approve(
    0x341f394086D6877885fD2cC966904BDFc2620aBf,  // Splitter
    tokenId
);

// Step 2: Deposit
VeAeroSplitter(0x341f394086D6877885fD2cC966904BDFc2620aBf).depositVeAero(tokenId);
```

**Window:** Thursday 00:01 UTC → Wednesday 21:44 UTC

---

## 2. Vote with V-AERO

Direct Aerodrome gauge emissions with your V-AERO.

### Active Vote (specific gauge)
```solidity
VToken(0x2B214E99050db935FBF3479E8629B2E3078DF61a).vote(
    gaugeAddress,  // Pool to vote for
    amount         // V-AERO amount in wei (e.g., 100e18 for 100 tokens)
);
```

### Passive Vote (follows active voters)
```solidity
VToken(0x2B214E99050db935FBF3479E8629B2E3078DF61a).votePassive(amount);
```

**Important:**
- Amount must be in wei (18 decimals)
- Voted tokens are **locked until epoch ends** (Thursday 00:00 UTC)
- **Window:** Thursday 00:01 UTC → Wednesday 22:00 UTC

---

## 3. Claim Rewards (C-AERO Holders)

C-AERO holders earn multiple reward streams.

### Trading Fees (AERO)

```solidity
CToken cToken = CToken(0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD);

// Check pending
uint256 pending = cToken.pendingFees(yourAddress);

// Collect (anyone can call)
cToken.collectFees();

// Claim your share
cToken.claimFees();
```

### META Rewards

```solidity
// Check pending
uint256 pending = cToken.pendingMeta(yourAddress);

// Collect (anyone can call)
cToken.collectMeta();

// Claim your share
cToken.claimMeta();
```

### Rebase (V+C token growth)

```solidity
VeAeroSplitter splitter = VeAeroSplitter(0x341f394086D6877885fD2cC966904BDFc2620aBf);

// Claim rebase (mints new V-AERO and C-AERO)
splitter.claimRebase();
```

---

## 4. Vote on Emissions (C-AERO)

C-AERO holders vote on Aerodrome's Fed emissions rate.

```solidity
CToken(0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD).voteEmissions(
    choice,  // -1 (decrease), 0 (hold), +1 (increase)
    amount   // C-AERO amount (whole tokens only, not wei)
);
```

**Note:** Emissions voting uses **whole tokens**, not wei.

**Window:** Thursday 00:01 UTC → Wednesday 22:00 UTC

---

## 5. Claim Bribes (V-AERO Voters)

Bribes are distributed to V-AERO voters based on epoch snapshots.

### Step 1: Vote (during epoch N)
```solidity
VToken(0x2B214E99050db935FBF3479E8629B2E3078DF61a).vote(gauge, amount);
```

### Step 2: Snapshot (after voting ends)
```solidity
// Call between Wednesday 22:00 - Thursday 00:00 UTC
VeAeroBribes(0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB).snapshotForBribes();
```

### Step 3: Claim (during epoch N+1)
```solidity
VeAeroBribes(0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB).claimBribes(tokenAddresses);
```

> ⚠️ **Deadline:** You must claim bribes before **Wednesday 23:00 UTC**. After this time, unclaimed bribes may be swept by Tokenisys.

---

## 6. Liquidation (Emergency Wind-Down)

Liquidation requires dual supermajority consent (75% C-AERO + 50% V-AERO) and takes 90+ days.

### C-AERO Holders: Vote for Liquidation
```solidity
VeAeroLiquidation(0xad608ecD3b506EB35f706bBb67D817aCe873B8eB).voteLiquidation(amount);
```

### V-AERO Holders: Confirm Liquidation
```solidity
VeAeroLiquidation(0xad608ecD3b506EB35f706bBb67D817aCe873B8eB).confirmLiquidation(amount);
```

### After Approval: Claim R-AERO
```solidity
VeAeroSplitter(0x341f394086D6877885fD2cC966904BDFc2620aBf).claimRTokens();
```

### If Liquidation Fails: Withdraw
```solidity
VeAeroLiquidation(0xad608ecD3b506EB35f706bBb67D817aCe873B8eB).withdrawFailedLiquidation();
```

---

## Epoch Schedule

| Time (UTC) | Day | Event |
|------------|-----|-------|
| 00:00 | Thursday | Epoch starts, tokens unlock |
| 00:01 | Thursday | Deposit & voting opens |
| 21:00-22:00 | Wednesday | META pushVote() window |
| 21:45 | Wednesday | Deposits close |
| 22:00 | Wednesday | Voting closes, executeGaugeVote() |
| 22:00-23:00 | Wednesday | Bribe snapshot window |
| 23:00 | Wednesday | **Bribe claim deadline** |
| 23:00-23:59 | Wednesday | Tokenisys sweep window |
| 00:00 | Thursday | Next epoch begins |

---

## Quick Reference

| I Have | I Want | I Call |
|--------|--------|--------|
| veAERO NFT | Liquid tokens | `Splitter.depositVeAero(tokenId)` |
| V-AERO | Vote for gauge | `VToken.vote(gauge, amount)` |
| V-AERO | Passive vote | `VToken.votePassive(amount)` |
| C-AERO | Trading fees (AERO) | `CToken.claimFees()` |
| C-AERO | META rewards | `CToken.claimMeta()` |
| C-AERO | Vote on emissions | `CToken.voteEmissions(choice, amount)` |
| V-AERO (voted) | Bribes | `Bribes.snapshotForBribes()` then `claimBribes()` |
| C-AERO | Rebase growth | `Splitter.claimRebase()` |

---

## Wei vs Whole Token Reference

| Function | Input Unit | Notes |
|----------|------------|-------|
| `VToken.vote()` | Wei | `100e18` = 100 tokens |
| `VToken.votePassive()` | Wei | `100e18` = 100 tokens |
| `CToken.voteEmissions()` | **Whole tokens** | `100` = 100 tokens |
| All `balanceOf()` | Wei | Standard ERC-20 |
| All `pending*()` | Wei | Standard ERC-20 |

---

## View Functions

### Check Your Balances
```solidity
VToken(0x2B214E99050db935FBF3479E8629B2E3078DF61a).balanceOf(yourAddress);
CToken(0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD).balanceOf(yourAddress);
```

### Check Pending Rewards
```solidity
CToken cToken = CToken(0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD);
cToken.pendingFees(yourAddress);   // Pending AERO fees
cToken.pendingMeta(yourAddress);   // Pending META rewards
```

### Check Bribe Eligibility
```solidity
VeAeroBribes bribes = VeAeroBribes(0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB);
bribes.snapshotVotePower(yourAddress);      // Your snapshot power
bribes.pendingBribes(yourAddress, token);   // Pending for specific token
```

### Check Epoch Info
```solidity
VeAeroSplitter splitter = VeAeroSplitter(0x341f394086D6877885fD2cC966904BDFc2620aBf);
splitter.currentEpoch();
splitter.epochEndTime();
splitter.votingStartTime();
splitter.votingEndTime();
```

---

## Error Codes

| Error | Meaning | Solution |
|-------|---------|----------|
| `TokensLocked()` | Tokens locked from voting | Wait until Thursday 00:00 UTC |
| `InvalidTiming()` | Outside valid window | Check epoch schedule |
| `AlreadyVoted()` | NFT has voted this epoch | Wait for next epoch |
| `NotPermanentLock()` | NFT not permanently locked | Only permanent locks accepted |
| `NothingToClaim()` | No pending rewards | Check `pending*()` first |
| `WindowClosed()` | Outside operation window | Check timing |

---

## Links

- **Basescan:** [VeAeroSplitter](https://basescan.org/address/0x341f394086D6877885fD2cC966904BDFc2620aBf)
- **Technical Handbook:** [TECHNICAL_HANDBOOK.md](TECHNICAL_HANDBOOK.md)
- **Test Results:** [TEST_RESULTS.md](TEST_RESULTS.md)

---

© 2026 Tokenisys. All rights reserved.  
Contact: ds@tokenisys.com
]]>