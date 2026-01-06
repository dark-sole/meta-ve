# Changelog

All notable changes to the META-VE Protocol.

## [1.0.0] - 2026-01-05

**Mainnet Deployment on Base**

### Added
- **Transfer Windfall Protection** — Sweep calculated on `amount` transferred, not sender's remaining balance
- **Round-UP Recipient Checkpoints** — Prevents dust accumulation attacks via weighted average with ceiling division
- **Self-Transfer Guard** — Self-transfers are now no-op (no sweep, no checkpoint change)
- **Rebase Sweep Split** — 91% Tokenisys, 9% META (previously 100% Tokenisys)
- **141 Fork Tests** — Live mainnet verification on Base
- **Certora Formal Verification** — 24 additional rules (62 total properties)
- **Multi-Epoch Stress Tests** — 17 scenarios with 100+ users over 20 epochs

### Security
- 833 tests passing (692 unit + 141 fork)
- 62 formal verification properties (Halmos 17 + Echidna 21 + Certora 24)
- 500k+ Echidna fuzz calls
- 43 windfall-specific tests
- 30 adversarial attack prevention tests

### Deployment
- **Block:** 40,414,704
- **Chain:** Base Mainnet (8453)
- **Genesis:** January 4, 2026

---

## [0.11.1] - 2025-12-31

### Fixed
- Corrected rebase timing documentation
- Clarified `collectRebase()` must be called after `consolidateNFTs()`

---

## [0.11.0] - 2025-12-29

### Added
- **EmissionsVoteLib** — Extracted Fed emissions voting to separate contract
- **Auto-Rebase in resetEpoch()** — Fail-safe rebase collection on epoch reset
- **Bribe Claim Deadline** — Users must claim before Wednesday 23:00 UTC
- **Tokenisys Sweep Window** — Last hour of epoch (Wed 23:00-00:00)
- **Cached Vote Totals** — `cachedTotalVLockedForVoting` for consistent bribe snapshots
- **META Exclusion from Bribes** — META's V-AERO excluded from bribe denominator

### Changed
- `sweepBribes()` moved from VeAeroBribes to VeAeroSplitter
- Epoch governor guards prevent revert if not set
- CToken direct AERO fee distribution via `feePerCToken`

### Security
- 692 unit tests passing
- 17 Halmos proofs
- 21 Echidna invariants

---

## [0.1.0] - 2025-12-22

### Added
- Initial protocol release
- VE Split mechanism (V-AERO + C-AERO)
- DeltaForce emission model
- Epoch-based locking
- Liquidation process
- L1 Proof Verification for cross-chain

---

## Contract Addresses (v1.0.0)

| Contract | Address |
|----------|---------|
| VeAeroSplitter | `0x341f394086D6877885fD2cC966904BDFc2620aBf` |
| VToken (V-AERO) | `0x2B214E99050db935FBF3479E8629B2E3078DF61a` |
| CToken (C-AERO) | `0x616cCBC180ed0b7C4121f7551DC6C262f749b2cD` |
| RToken (R-AERO) | `0x0Db78Bb35f58b6A591aCc6bbAEf6dD57C5Ea1908` |
| Meta | `0xC4Dfb91cc97ef36D171F761ab15EdE9bbc2EE051` |
| VeAeroLiquidation | `0xad608ecD3b506EB35f706bBb67D817aCe873B8eB` |
| VeAeroBribes | `0xe3c012c9A8Cd0BafEcd60f72Bb9Cc49662d3FcDB` |
| VoteLib | `0x2dE16D98569c6CB352F80fc6024F5C86F3Ef47c5` |
| EmissionsVoteLib | `0x5a301a802B0C4BD5389E3Dc31eeB54cf37c65324` |

---

© 2026 Tokenisys. All rights reserved.
