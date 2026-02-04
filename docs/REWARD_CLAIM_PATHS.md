# META-VE Protocol Reward Claim Paths

**Version:** 2.0 (DELTA)  
**Date:** January 2026  
**Network:** Base Mainnet (Chain ID: 8453)

---

## Complete Source of Truth (Based on Smart Contract Review)

---

## 1. C-TOKEN HOLDER REWARDS

### 1.1 META Incentives (from Meta contract)

**Flow:**
```
Meta.updateIndex() → mints META to Meta contract
    ↓
CToken.collectMeta() → calls meta.claimForVEPool() → pulls META to CToken
    ↓  
    Updates metaPerCToken index
    ↓
CToken.claimMeta() → transfers META to user
```

**Functions:**
- `cToken.collectMeta()` - Anyone can call to pull META from Meta to CToken
- `cToken.claimMeta()` - User claims their share
- `cToken.pendingMeta(user)` - View pending (includes uncollected pool rewards)

---

### 1.2 Trading Fees — Splitter Direct (50% of AERO)

**Flow:**
```
Aerodrome Voter → claimFees() on masterNFT
    ↓
Splitter.collectFees() → receives fee tokens
    ├─ AERO received directly:
    │     50% → globalFeeIndex (for C holders via Splitter.claimFees())
    │     50% → Meta.receiveFees()
    └─ Non-AERO tokens → FeeSwapper
          ↓
          FeeSwapper.swap() → converts to AERO
          ↓
          Splitter.processSwappedFees() → 50/50 split as above
    ↓
Splitter.claimFees() → transfers AERO to user (50% direct share)
```

**Functions:**
- `splitter.collectFees(feeDistributors, tokens)` - Claims from Aerodrome
- `splitter.claimFees()` - User claims their share from globalFeeIndex
- `feeSwapper.swap()` - Convert pending non-AERO tokens to AERO (anyone can call)

---

### 1.3 Trading Fees — Via Meta (remaining share via poolFeeAccrued)

**Flow:**
```
Splitter.collectFees() → 50% to Meta.receiveFees()
    ↓
Meta stores in poolFeeAccrued[cToken]
    ↓
CToken.collectFees() → calls meta.claimFeesForVEPool() → pulls AERO to CToken
    ↓
    Updates feePerCToken index
    ↓
CToken.claimFees() → transfers AERO to user
```

**Functions:**
- `cToken.collectFees()` - Pull AERO fees from Meta to CToken
- `cToken.claimFees()` - User claims their share
- `cToken.pendingFees(user)` - View pending (includes uncollected poolFeeAccrued)

---

### 1.4 Rebase (Aerodrome emissions - mints new V+C)

**Flow:**
```
Aerodrome emissions → masterNFT locked amount grows
    ↓
Splitter.collectRebase() → calls REWARDS_DISTRIBUTOR.claim()
    ↓
Splitter._updateRebaseIndex() → tracks growth, updates globalRebaseIndex
    ↓
Splitter.claimRebase() → mints new V-AERO and C-AERO to user
```

**Functions:**
- `splitter.collectRebase()` - Claim emissions from Aerodrome
- `splitter.updateRebaseIndex()` - Update index based on NFT growth
- `splitter.claimRebase()` - User claims, receives minted V+C tokens

---

## 2. V-TOKEN HOLDER REWARDS

### 2.1 Bribes (from VeAeroBribes)

**Flow:**
```
Splitter.collectBribes() → claims from Aerodrome, tokens stay in Splitter
    ↓
User votes via VToken.vote()
    ↓
After voting ends: executeGaugeVote()
    ↓
User calls bribes.snapshotForBribes() → records vote power
    ↓
Next epoch: bribes.claimBribes(tokens) → pulls from Splitter to user
```

**Functions:**
- `splitter.collectBribes(bribes, tokens)` - Collect bribes from Aerodrome
- `bribes.snapshotForBribes()` - User records vote power (after vote execution)
- `bribes.claimBribes(tokens)` - User claims next epoch
- `bribes.pendingBribes(user, token)` - View pending for specific token

---

## 3. TRANSFER SETTLEMENT

### 3.1 C-AERO Transfer Mechanics

On C-AERO transfers, the `onCTokenTransfer()` hook handles reward settlement:

**Sender Settlement (DELTA — Re-indexing):**
- Unclaimed Splitter fees on the **transferred amount** are re-distributed to ALL C-AERO holders by incrementing `globalFeeIndex`
- Sender's fee checkpoint is **NOT updated** — they can still claim on remaining balance
- No sweep to Tokenisys
- CToken rewards (via `feePerCToken`/`metaPerCToken`) are preserved in `userClaimable` storage via checkpoint/debt pattern in CToken._update()

**Recipient Settlement:**
- New holders are assigned current global index values (no windfall)
- Existing holders receive weighted average checkpoint with **round-UP**:
  ```
  newCheckpoint = ⌈(oldBalance × oldCheckpoint + amount × globalIndex) / newBalance⌉
  ```

**Self-Transfer Guard:**
- Self-transfers (`from == to`) are no-op — no re-index, no checkpoint change

---

## 4. KEY DISTINCTIONS

### Splitter vs CToken Claims

| Reward Type | Collect Function | Claim Function | Index Variable |
|-------------|------------------|----------------|----------------|
| Splitter Fees | `splitter.collectFees()` | `splitter.claimFees()` | `globalFeeIndex` |
| CToken Fees | `cToken.collectFees()` | `cToken.claimFees()` | `feePerCToken` |
| CToken Meta | `cToken.collectMeta()` | `cToken.claimMeta()` | `metaPerCToken` |
| Rebase | `splitter.collectRebase()` | `splitter.claimRebase()` | `globalRebaseIndex` |
| Bribes | `splitter.collectBribes()` | `bribes.claimBribes()` | `bribeRatioPerV` |

### Important Notes

1. **CToken `collectMeta()`** pulls META from Meta.claimForVEPool() — the ONLY META claim path for C-AERO holders
2. **CToken `collectFees()`** pulls AERO from Meta.claimFeesForVEPool() — the Meta portion of trading fees
3. **Splitter `claimFees()`** claims the direct 50% AERO share — separate from CToken.claimFees()

4. **`pendingFees()` and `pendingMeta()` in CToken** include **uncollected** rewards from Meta
   - This is a **preview** of what will be available after collection
   - Actual claim amount depends on calling `collectFees()`/`collectMeta()` first

5. **Windfall Protection** - New depositors trigger `_collectPendingFees()` and `_collectPendingMeta()` on mint
   - This crystallizes the fee/META index before setting their debt
   - Prevents front-running fee collection

6. **Transfer Protection** - Transfers re-index unclaimed Splitter fees to all C-AERO holders (DELTA). Sender checkpoint unchanged, recipient checkpoint blended with round-UP.

---

## 5. QUICK REFERENCE

### C-AERO Holder Rewards

| Reward | Source | Collect | Claim |
|--------|--------|---------|-------|
| AERO Fees (Splitter) | Splitter | `splitter.collectFees()` | `splitter.claimFees()` |
| AERO Fees (Meta) | Meta | `cToken.collectFees()` | `cToken.claimFees()` |
| META | Meta | `cToken.collectMeta()` | `cToken.claimMeta()` |
| Rebase | Splitter | `splitter.collectRebase()` | `splitter.claimRebase()` |

### V-AERO Voter Rewards

| Reward | Source | Snapshot | Claim |
|--------|--------|----------|-------|
| Bribes | Splitter | `bribes.snapshotForBribes()` | `bribes.claimBribes(tokens)` |

---

© 2026 Tokenisys. All rights reserved.
