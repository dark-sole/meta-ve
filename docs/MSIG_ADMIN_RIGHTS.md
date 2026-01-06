# META-VE Protocol: MSIG Admin Rights & Post-Deployment Guide

**Version:** 1.0  
**Date:** January 2026  
**Network:** Base Mainnet (Chain ID: 8453)

---

## Executive Summary

The META-VE protocol uses a **two-tier admin structure**:

1. **META MSIG** (Owner) - Protocol configuration, no asset extraction
2. **LIQUIDATION MSIG** - Only active during liquidation phase, NFT custody

**Critical Security Property:** Neither MSIG can extract user assets under normal operation. Asset flows are programmatic and user-initiated.

---

## Contract Ownership Overview

| Contract | Owner Type | Owner Address | Can Extract Assets? |
|----------|------------|---------------|---------------------|
| VeAeroSplitter | Ownable | META MSIG | ❌ No |
| CToken | Ownable | META MSIG | ❌ No |
| VToken | Ownable | META MSIG | ❌ No |
| RToken | Ownable | META MSIG | ❌ No |
| Meta | Custom MSIG | META MSIG | ❌ No |
| EmissionsVoteLib | Ownable | META MSIG | ❌ No |
| VeAeroBribes | Immutable | N/A (no admin) | ❌ No |
| VeAeroLiquidation | Immutable | N/A (no admin) | ❌ No |
| VoteLib | Immutable | N/A (no admin) | ❌ No |
| L1ProofVerifier | Custom Owner | META MSIG | ❌ No |

---

## VeAeroSplitter.sol

### Owner Functions (META MSIG)

| Function | Purpose | Asset Risk |
|----------|---------|------------|
| `setAerodromeVoter(address)` | Update Aerodrome Voter reference | ⚠️ Low - could break voting |
| `setEpochGovernor(address)` | Set emissions governor | ⚠️ Low - could break Fed vote |
| `setProposalVoteLib(address)` | Set protocol governance lib | ✅ Safe - enables new feature |
| `setVoteLib(address)` | Set VoteLib for multi-NFT voting | ⚠️ Low - could break gauge voting |
| `setEmissionsVoteLib(address)` | Set EmissionsVoteLib for Fed voting | ✅ Safe - enables Fed voting |
| `transferOwnership(address)` | Transfer owner role | ⚠️ Medium - one-time, irreversible |

### ❌ What Owner CANNOT Do

- Cannot withdraw user deposits
- Cannot withdraw AERO, META, or any tokens held for users
- Cannot bypass liquidation governance
- Cannot modify fee splits or token allocations
- Cannot mint/burn V-AERO, C-AERO, R-AERO
- Cannot access bribe tokens (only Tokenisys in sweep window)

---

## CToken.sol

### Owner Functions (META MSIG)

| Function | Purpose | One-Time? |
|----------|---------|-----------|
| `setSplitter(address)` | Link to VeAeroSplitter | ✅ Yes (reverts if already set) |
| `setMeta(address)` | Link to Meta contract | ✅ Yes (reverts if already set) |
| `setLiquidation(address)` | Link to VeAeroLiquidation | ✅ Yes (reverts if already set) |
| `setAero(address)` | Set AERO token address | ✅ Yes (reverts if already set) |
| `setEmissionsVoteLib(address)` | Link to EmissionsVoteLib | ✅ Yes (reverts if already set) |

### ❌ What Owner CANNOT Do

- Cannot mint C-AERO (only Splitter)
- Cannot burn C-AERO (only Splitter)
- Cannot transfer user C-AERO
- Cannot modify fee distribution logic
- Cannot extract AERO fees held for users

---

## Meta.sol

### MSIG Functions (msigTreasury)

| Function | Purpose | One-Time? |
|----------|---------|-----------|
| `setSplitter(address)` | Link to VeAeroSplitter | Changeable |
| `setVToken(address)` | Link to VToken | Changeable |
| `setLPPool(address)` | Set META/AERO LP pool | Changeable |
| `setPoolLPGauge(vePool, lpGauge)` | Set LP gauge for VE pool | Changeable |
| `setMSIG(address)` | Transfer MSIG role | ⚠️ Irreversible |
| `renounceL1ProofAuthority()` | Disable L1 proof control | ✅ One-time, irreversible |
| `enableMultiVE()` | Enable Phase 2 multi-VE | ✅ One-time, irreversible |
| `addVEPool(vePool, lpGauge)` | Add local VE pool | Changeable |
| `removeVEPool(vePool)` | Remove VE pool | Changeable |

### ❌ What MSIG CANNOT Do

- Cannot mint META tokens (algorithmic only)
- Cannot burn META tokens
- Cannot transfer user META
- Cannot modify emission curve (immutable)
- Cannot extract staked META
- Cannot extract AERO fees held for users
- Cannot modify fee percentages (immutable constants)

---

## Security Invariants

### Asset Safety

1. **No admin extraction** - MSIG cannot withdraw user deposits, fees, or rewards
2. **Programmatic flows only** - All asset movements are user-initiated or algorithmic
3. **Immutable fee splits** - Fee percentages are constants, not modifiable
4. **Governance-gated liquidation** - NFT withdrawal requires C+V holder supermajority

### Configuration Safety

1. **One-time setters** - Most linking functions revert if already set
2. **Zero-address checks** - All setters validate non-zero addresses
3. **No upgrade paths** - Contracts are not upgradeable proxies

### Operational Safety

1. **Sweep window limited** - Tokenisys can only sweep in last hour of epoch
2. **Liquidation gated** - Multiple phases with timeouts and supermajority requirements
3. **Governor guards** - Voting functions revert if governor not set

---

## Summary

The META MSIG has **configuration authority** but **no extraction capability**:

✅ Can configure protocol parameters  
✅ Can enable new features  
✅ Can set external contract references  
❌ Cannot withdraw user funds  
❌ Cannot modify immutable fee splits  
❌ Cannot bypass governance requirements  
❌ Cannot mint/burn tokens arbitrarily  

This design ensures that even a compromised MSIG cannot steal user assets - only disrupt protocol functionality temporarily.

---

© 2026 Tokenisys. All rights reserved.