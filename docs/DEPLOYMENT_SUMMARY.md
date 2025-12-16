# META VE Mainnet Deployment Summary

**Date:** December 16, 2025  
**Network:** Base Mainnet (Chain ID: 8453)  
**Block:** 39530457-39530458  
**Total Cost:** 0.0000297 ETH (~$0.12)

---

## Deployed Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| **VToken** | `0x56b1c70EC3e5751F513Bb4E1C1B041398413246A` | ✅ |
| **CToken** | `0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E` | ✅ |
| **RToken** | `0x3dB3fF66d9188694f5b6FA8ccdfF9c3921b77832` | ✅ |
| **Meta** | `0x24408894b6C34ed11a609db572d5a2d7e7b187C6` | ✅ |
| **VeAeroLiquidation** | `0x289d982DA03d7DA73EE88F0de8799eBF5B7672cc` | ✅ |
| **VeAeroBribes** | `0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E` | ✅ |
| **VoteLib** | `0x16a6359d45386eD4a26458558A0542B826Bb72c0` | ✅ |
| **VeAeroSplitter** | `0xf47Ece65481f0709e78c58f802d8e76B20fd4361` | ✅ |

---

## V8 Key Change

```solidity
// addVEPool() no longer requires gauge address
// Enables META staking before Aerodrome gauge exists
Meta.addVEPool(splitter, address(0))  // NOW WORKS!
```

---

## Configuration

### External Dependencies (Aerodrome)
| Contract | Address |
|----------|---------|
| AERO Token | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` |
| veAERO (Voting Escrow) | `0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4` |
| Voter | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` |
| Epoch Governor | `0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497` |

### Key Addresses
| Role | Address |
|------|---------|
| Tokenisys | `0x432E67d6adF9bD3d42935947E00bF519ecCaA5cB` |
| Treasury | `0xF25a1bB1c463df34E3258ac090e8Fc0895AEC528` |
| META MSIG (Owner) | `0xA50b0109E44233721e427CFB8485F2254E652636` |
| Liquidation MSIG | `0xCF4b81611228ec9bD3dCF264B4bD0BF37283D24D` |
| Deployer | `0x87dD4984c56Bb94D2592F7644fa66f8611864709` |

### Meta Configuration
| Parameter | Value |
|-----------|-------|
| Genesis Time | `1765929600` (Dec 17, 2025 00:00 UTC) |
| TGE Mint | 28,000,000 META → Tokenisys |

### VToken Configuration
| Parameter | Value |
|-----------|-------|
| Max Pools | 200 |
| Bits Per Pool | 64 |
| Pools Per Slot | 4 |
| Max Weight | 50 |

### LP Pool (Created)
| Parameter | Value |
|-----------|-------|
| META-AERO Pool | `0x0d104dcc18004ebdab2cad67acacbf6986d8a5d5` |
| Gauge | Not yet created |

---

## Wiring Verification ✅

| Check | Status |
|-------|--------|
| VToken.splitter → Splitter | ✅ |
| VToken.liquidation → Liquidation | ✅ |
| CToken.splitter → Splitter | ✅ |
| CToken.liquidation → Liquidation | ✅ |
| CToken.meta → Meta | ✅ |
| RToken.splitter → Splitter | ✅ |
| Meta.splitter → Splitter | ✅ |
| Meta.vToken → VToken | ✅ |
| Splitter.voteLib → VoteLib | ✅ |

---

## Ownership ✅

| Contract | Owner |
|----------|-------|
| VToken | `0xA50b0109E44233721e427CFB8485F2254E652636` (MSIG) |
| CToken | `0xA50b0109E44233721e427CFB8485F2254E652636` (MSIG) |
| RToken | `0xA50b0109E44233721e427CFB8485F2254E652636` (MSIG) |
| Splitter | `0xA50b0109E44233721e427CFB8485F2254E652636` (MSIG) |

---

## Environment Variables

```bash
# V8 Deployment Addresses
V_TOKEN=0x56b1c70EC3e5751F513Bb4E1C1B041398413246A
C_TOKEN=0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E
R_TOKEN=0x3dB3fF66d9188694f5b6FA8ccdfF9c3921b77832
META_TOKEN=0x24408894b6C34ed11a609db572d5a2d7e7b187C6
VEAERO_LIQUIDATION=0x289d982DA03d7DA73EE88F0de8799eBF5B7672cc
VEAERO_BRIBES=0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E
VOTE_LIB=0x16a6359d45386eD4a26458558A0542B826Bb72c0
VEAERO_SPLITTER=0xf47Ece65481f0709e78c58f802d8e76B20fd4361
LP_POOL=0x0d104dcc18004ebdab2cad67acacbf6986d8a5d5
```

---

## Next Steps

### Phase 2: Whitelist CToken (MSIG)

**Single transaction required:**

```solidity
Meta.addVEPool(0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E, address(0))  // CToken
```

**Calldata:**
```
0xc441f06600000000000000000000000007b3a3c5f5b9dad9b36fc6faa40fd4bfbcc4aa4e0000000000000000000000000000000000000000000000000000000000000000
```

**Target:** `0x24408894b6C34ed11a609db572d5a2d7e7b187C6` (Meta)
**Value:** 0

**Effect:** Enables CToken to pull META incentives and AERO fees from Meta

### Phase 5 (Optional): Set LP Pool

```solidity
Meta.setLPPool(0x0d104dcc18004ebdab2cad67acacbf6986d8a5d5)
```

**Calldata:**
```
0x69fe0e2d0000000000000000000000000d104dcc18004ebdab2cad67acacbf6986d8a5d5
```

**Effect:** Enables Meta's own V-AERO voting via `pushVote()`

### Phase 6 (When Available): Set Gauge

```solidity
Meta.setPoolLPGauge(0xf47Ece65481f0709e78c58f802d8e76B20fd4361, GAUGE_ADDRESS)
```

**Effect:** LP rewards start flowing to stakers

---

## What Works Now (Phase 1 Complete)

| Feature | Status |
|---------|--------|
| veAERO deposits | ✅ |
| V-AERO/C-AERO minting | ✅ |
| Gauge voting (via VToken) | ✅ |
| Emissions voting (via CToken) | ✅ |
| Liquidation voting | ✅ |
| Token transfers | ✅ |
| **CToken pulls rewards** | ❌ Needs Phase 2 |
| **META staking** | ❌ Needs Phase 2 |

---

## Basescan Links

- [VToken](https://basescan.org/address/0x56b1c70EC3e5751F513Bb4E1C1B041398413246A)
- [CToken](https://basescan.org/address/0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E)
- [RToken](https://basescan.org/address/0x3dB3fF66d9188694f5b6FA8ccdfF9c3921b77832)
- [Meta](https://basescan.org/address/0x24408894b6C34ed11a609db572d5a2d7e7b187C6)
- [VeAeroLiquidation](https://basescan.org/address/0x289d982DA03d7DA73EE88F0de8799eBF5B7672cc)
- [VeAeroBribes](https://basescan.org/address/0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E)
- [VoteLib](https://basescan.org/address/0x16a6359d45386eD4a26458558A0542B826Bb72c0)
- [VeAeroSplitter](https://basescan.org/address/0xf47Ece65481f0709e78c58f802d8e76B20fd4361)

---

## Obsolete V7 Contracts

| Contract | V7 (Obsolete) | V8 (Current) |
|----------|---------------|--------------|
| VToken | `0x18Ce70d81B23EcE52c41eA174154e57f482079b7` | `0x56b1c70EC3e5751F513Bb4E1C1B041398413246A` |
| CToken | `0xD16f41273422B1d92CA9304E75F0E58f60861A47` | `0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E` |
| RToken | `0x7A3227c0d4d71197aF3c30CdF7673B75ee0D03B8` | `0x3dB3fF66d9188694f5b6FA8ccdfF9c3921b77832` |
| Meta | `0xa9BdDeb20B16546F7Fa2Dd276d1F8Ce76CCE9639` | `0x24408894b6C34ed11a609db572d5a2d7e7b187C6` |
| Liquidation | `0x451b51bec8E1f48b13239c2e9E356C2f65A94784` | `0x289d982DA03d7DA73EE88F0de8799eBF5B7672cc` |
| Bribes | `0xb8e5fa5F47c58e0738CC226479bf03F171e6E187` | `0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E` |
| VoteLib | `0x7d750156C40ed59A4fE6B63Fb34Cd978FC02A2cE` | `0x16a6359d45386eD4a26458558A0542B826Bb72c0` |
| Splitter | `0xe2187e1F58d9b7D747DC96cD9A16Be9fE96b7f16` | `0xf47Ece65481f0709e78c58f802d8e76B20fd4361` |
