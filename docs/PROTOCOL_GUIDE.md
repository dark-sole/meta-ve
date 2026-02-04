# META-VE Protocol Guide

**Version:** 2.0 (DELTA)  
**Network:** Base Mainnet (Chain ID: 8453)  
**Last Updated:** February 2026

A quick reference for interacting with META-VE on Base.

---

## Contract Addresses

### META-VE Contracts

| Contract | Address | Purpose |
|----------|---------|---------|
| **VeAeroSplitter** | `0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb` | Deposit veAERO, fee distribution |
| **V-AERO** (VToken) | `0x4c53e43C294795D5EB0905E48f7d758852F833c9` | Gauge voting |
| **C-AERO** (CToken) | `0xa5dF6792A2954151aaeD097795D45B17638c2248` | Fees, META rewards, emissions voting |
| **R-AERO** (RToken) | `0x9A3029417505Fb900EF47c544C7d92e981413bA6` | Liquidation receipts |
| **Meta** | `0x8110E76892224F2c522C471D09C4157088eA2c27` | META token, emissions |
| **VeAeroBribes** | `0xEb10F2AA34e1CdB0144437fb6FbA20A9dAb65E27` | Bribe snapshots & claims |
| **VeAeroLiquidation** | `0xF3b04597BFC481efdF985b9DCD4091a8E5a166fA` | Liquidation governance |
| **VoteLib** | `0xAE2aEe761D75BBFE27262D87bc73f54A7E6199b1` | Multi-NFT vote distribution |
| **EmissionsVoteLib** | `0xA336db52655887A4E1bDdA1D60e3E743b25904E1` | Fed emissions voting |
| **FeeSwapper** | `0x50b6Fb0aD83f9fCd01a397deB4C0A4CD59eDB2a5` | Non-AERO fee token conversion |

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
    0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb,  // Splitter
    tokenId
);

// Step 2: Deposit
VeAeroSplitter(0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb).depositVeAero(tokenId);
```

**Window:** Thursday 00:01 UTC → Wednesday 21:44 UTC

---

## 2. Vote with V-AERO

Direct Aerodrome gauge emissions with your V-AERO.

### Active Vote (specific gauge)
```solidity
VToken(0x4c53e43C294795D5EB0905E48f7d758852F833c9).vote(
    gaugeAddress,  // Pool to vote for
    amount         // V-AERO amount in wei (e.g., 100e18 for 100 tokens)
);
```

### Passive Vote (follows active voters)
```solidity
VToken(0x4c53e43C294795D5EB0905E48f7d758852F833c9).votePassive(amount);
```

**Important:**
- Amount must be in wei (18 decimals)
- Voted tokens are **locked until epoch ends** (Thursday 00:00 UTC)
- **Window:** Thursday 00:01 UTC → Wednesday 22:00 UTC

---

## 3. Claim Rewards (C-AERO Holders)

C-AERO holders earn multiple reward streams.

### Trading Fees — Splitter Direct (50% of AERO)

```solidity
VeAeroSplitter splitter = VeAeroSplitter(0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb);

// Claim your share of direct fee distribution
splitter.claimFees();
```

### Trading Fees — Via Meta (remaining share)

```solidity
CToken cToken = CToken(0xa5dF6792A2954151aaeD097795D45B17638c2248);

// Check pending
uint256 pending = cToken.pendingFees(yourAddress);

// Pull AERO from Meta to CToken (anyone can call)
cToken.collectFees();

// Claim your share
cToken.claimFees();
```

> ℹ️ Trading fees arrive as underlying pool tokens (USDC, WETH, etc.), not always AERO.
> The FeeSwapper converts non-AERO tokens to AERO automatically.
> `Splitter.collectFees()` handles direct AERO fees and routes non-AERO to FeeSwapper.

### META Rewards

```solidity
CToken cToken = CToken(0xa5dF6792A2954151aaeD097795D45B17638c2248);

// Check pending
uint256 pending = cToken.pendingMeta(yourAddress);

// Collect (anyone can call)
cToken.collectMeta();

// Claim your share
cToken.claimMeta();
```

### Rebase (V+C token growth)

```solidity
VeAeroSplitter splitter = VeAeroSplitter(0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb);

// Claim rebase (mints new V-AERO and C-AERO)
splitter.claimRebase();
```

---

## 4. Vote on Emissions (C-AERO)

C-AERO holders vote on Aerodrome's Fed emissions rate.

```solidity
CToken(0xa5dF6792A2954151aaeD097795D45B17638c2248).voteEmissions(
    choice,  // -1 (decrease), 0 (hold), +1 (increase)
    amount   // C-AERO amount in wei (must be whole token multiples, e.g., 100e18)
);
```

**Note:** Emissions voting accepts **wei** that must be whole token multiples (`amount % 1e18 == 0`). Input `100` would revert; use `100e18` for 100 tokens.

**Window:** Thursday 00:01 UTC → Wednesday 22:00 UTC

---

## 5. Claim Bribes (V-AERO Voters)

Bribes are distributed to V-AERO voters based on epoch snapshots.

### Step 1: Vote (during epoch N)
```solidity
VToken(0x4c53e43C294795D5EB0905E48f7d758852F833c9).vote(gauge, amount);
```

### Step 2: Snapshot (after voting ends)
```solidity
// Call between Wednesday 22:00 - Thursday 00:00 UTC
VeAeroBribes(0xEb10F2AA34e1CdB0144437fb6FbA20A9dAb65E27).snapshotForBribes();
```

### Step 3: Claim (during epoch N+1)
```solidity
VeAeroBribes(0xEb10F2AA34e1CdB0144437fb6FbA20A9dAb65E27).claimBribes(tokenAddresses);
```

> ⚠️ **Deadline:** You must claim bribes before **Wednesday 23:00 UTC**. After this time, unclaimed bribes may be swept by Tokenisys.

---

## 6. Liquidation (Emergency Wind-Down)

Liquidation requires dual supermajority consent (75% C-AERO + 50% V-AERO) and takes 90+ days.

### C-AERO Holders: Vote for Liquidation
```solidity
CToken(0xa5dF6792A2954151aaeD097795D45B17638c2248).voteLiquidation(amount);
```

### V-AERO Holders: Confirm Liquidation
```solidity
VToken(0x4c53e43C294795D5EB0905E48f7d758852F833c9).confirmLiquidation(amount);
```

### After Approval: Claim R-AERO
```solidity
VeAeroSplitter(0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb).claimRTokens();
```

### If Liquidation Fails: Withdraw
```solidity
VeAeroLiquidation(0xF3b04597BFC481efdF985b9DCD4091a8E5a166fA).withdrawFailedLiquidation();
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
| C-AERO | Trading fees (AERO — Splitter) | `Splitter.claimFees()` |
| C-AERO | Trading fees (AERO — Meta) | `CToken.collectFees()` then `CToken.claimFees()` |
| C-AERO | META rewards | `CToken.collectMeta()` then `CToken.claimMeta()` |
| C-AERO | Vote on emissions | `CToken.voteEmissions(choice, amount)` |
| V-AERO (voted) | Bribes | `Bribes.snapshotForBribes()` then `claimBribes()` |
| C-AERO | Rebase growth | `Splitter.claimRebase()` |

---

## Wei vs Whole Token Reference

| Function | Input Unit | Notes |
|----------|------------|-------|
| `VToken.vote()` | Wei | `100e18` = 100 tokens |
| `VToken.votePassive()` | Wei | `100e18` = 100 tokens |
| `CToken.voteEmissions()` | Wei (whole multiples) | `100e18` = 100 tokens |
| All `balanceOf()` | Wei | Standard ERC-20 |
| All `pending*()` | Wei | Standard ERC-20 |

---

## View Functions

### Check Your Balances
```solidity
VToken(0x4c53e43C294795D5EB0905E48f7d758852F833c9).balanceOf(yourAddress);
CToken(0xa5dF6792A2954151aaeD097795D45B17638c2248).balanceOf(yourAddress);
```

### Check Pending Rewards
```solidity
CToken cToken = CToken(0xa5dF6792A2954151aaeD097795D45B17638c2248);
cToken.pendingFees(yourAddress);   // Pending AERO fees (CToken path)
cToken.pendingMeta(yourAddress);   // Pending META rewards
```

### Check Bribe Eligibility
```solidity
VeAeroBribes bribes = VeAeroBribes(0xEb10F2AA34e1CdB0144437fb6FbA20A9dAb65E27);
bribes.snapshotVotePower(yourAddress);      // Your snapshot power
bribes.pendingBribes(yourAddress, token);   // Pending for specific token
```

### Check Epoch Info
```solidity
VeAeroSplitter splitter = VeAeroSplitter(0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb);
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
| `MustVoteWholeTokens()` | Amount not whole token multiple | Use multiples of 1e18 |

---

## Links

- **Basescan:** [VeAeroSplitter](https://basescan.org/address/0x72056b6BDfA0E8a3DC5242ebaf37Ce42fb97F4bb)
- **Technical Handbook:** [TECHNICAL_HANDBOOK.md](TECHNICAL_HANDBOOK.md)
- **Test Results:** [TEST_RESULTS.md](TEST_RESULTS.md)

---

© 2026 Tokenisys. All rights reserved.  
Contact@tokenisys.xyz
