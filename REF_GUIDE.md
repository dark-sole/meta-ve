# META Protocol - User Guide

A quick reference for interacting with the META protocol on Base.

---

## Contract Addresses (Base Mainnet)

| Contract | Address | Purpose |
|----------|---------|---------|
| VeAeroSplitter | `0xf47Ece65481f0709e78c58f802d8e76B20fd4361` | Deposit veAERO |
| VToken (V-AERO) | `0x56b1c70EC3e5751F513Bb4E1C1B041398413246A` | Gauge voting |
| CToken (C-AERO) | `0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E` | Fees, bribes, emissions |
| Meta | `0x24408894b6C34ed11a609db572d5a2d7e7b187C6` | META staking |

---

## 1. Deposit veAERO

Convert your veAERO NFT into liquid tokens.

**Requirements:**
- veAERO NFT (permanent lock only)
- NFT must not have voted this epoch

**Steps:**
1. Approve Splitter to transfer your NFT
2. Call `depositVeAero(tokenId)`

**You receive:**
- **V-AERO** (90%) - Voting rights
- **C-AERO** (9%) - Capital rights (fees, bribes, rewards)
- 1% fee to protocol

```solidity
// Approve
VotingEscrow(0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4).approve(
    0xf47Ece65481f0709e78c58f802d8e76B20fd4361, // Splitter
    tokenId
);

// Deposit
VeAeroSplitter(0xf47Ece65481f0709e78c58f802d8e76B20fd4361).depositVeAero(tokenId);
```

---

## 2. Vote with V-AERO

Use V-AERO to vote for Aerodrome gauges.

**Voting Window:** Thursday 00:01 UTC → Wednesday 22:00 UTC

**Options:**

### Active Vote (specific gauge)
```solidity
VToken(0x56b1c70EC3e5751F513Bb4E1C1B041398413246A).vote(
    gaugeAddress,  // Pool to vote for
    amount         // V-AERO amount (in wei)
);
```

### Passive Vote (auto-distributed)
```solidity
VToken(0x56b1c70EC3e5751F513Bb4E1C1B041398413246A).votePassive(amount);
```

**Note:** Voted tokens are locked until epoch ends (Thursday 00:00 UTC).

---

## 3. Claim with C-AERO

C-AERO holders receive protocol rewards.

### Claim Trading Fees
```solidity
CToken(0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E).claimFees();
```

### Claim META Rewards
```solidity
// First, trigger distribution (anyone can call)
CToken(0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E).collectMeta();

// Then claim your share
CToken(0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E).claimMeta();
```

### Vote on Emissions
Vote on AERO emission rate changes:
```solidity
CToken(0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E).voteEmissions(
    choice,  // -1 (decrease), 0 (hold), +1 (increase)
    amount   // C-AERO amount (whole tokens only)
);
```

---

## 4. Stake META

Lock META to earn protocol rewards.

### Lock and Vote
```solidity
Meta(0x24408894b6C34ed11a609db572d5a2d7e7b187C6).lockAndVote(
    amount,  // META amount (in wei)
    0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E  // CToken (VE pool)
);
```

### Add to Existing Lock
```solidity
Meta(0x24408894b6C34ed11a609db572d5a2d7e7b187C6).lockAndVote(
    additionalAmount,
    0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E
);
```

### Claim Staking Rewards
```solidity
Meta(0x24408894b6C34ed11a609db572d5a2d7e7b187C6).claimRewards();
```

### Unlock (24hr cooldown)
```solidity
// Start unlock
Meta(0x24408894b6C34ed11a609db572d5a2d7e7b187C6).initiateUnlock();

// After 24 hours
Meta(0x24408894b6C34ed11a609db572d5a2d7e7b187C6).completeUnlock();
```

---

## 5. Claim Bribes

Bribes are distributed based on C-AERO snapshot.

### Take Snapshot (once per epoch)
```solidity
VeAeroBribes(0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E).snapshotForBribes();
```

### Claim Your Bribes
```solidity
VeAeroBribes(0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E).claimBribes(tokenAddresses);
```

---

## Epoch Schedule

| Event | Time (UTC) | Day |
|-------|------------|-----|
| Epoch Start | 00:00 | Thursday |
| Voting Opens | 00:01 | Thursday |
| Deposits Close | 21:45 | Wednesday |
| Voting Closes | 22:00 | Wednesday |
| Epoch End | 00:00 | Thursday |

---

## External Links

- **AERO Token:** `0x940181a94A35A4569E4529A3CDfB74e38FD98631`
- **veAERO (VotingEscrow):** `0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4`
- **Aerodrome Voter:** `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5`
- **Basescan:** https://basescan.org

---

## Summary

| Have | Want | Do |
|------|------|-----|
| veAERO NFT | Liquid tokens | `Splitter.depositVeAero(tokenId)` |
| V-AERO | Vote for gauges | `VToken.vote(gauge, amount)` |
| C-AERO | Trading fees | `CToken.claimFees()` |
| C-AERO | META rewards | `CToken.claimMeta()` |
| C-AERO | Bribes | `VeAeroBribes.claimBribes(tokens)` |
| META | Staking rewards | `Meta.lockAndVote(amount, pool)` |

---

© Tokenisys. All rights reserved.

Contact: ds@tokenisys.com
