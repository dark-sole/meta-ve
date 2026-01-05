<![CDATA[# Security

## Reporting Vulnerabilities

If you discover a security vulnerability in META-VE, please report it responsibly.

**Contact:** ds@tokenisys.com

**Please include:**
- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Any suggested fixes

We will acknowledge receipt within 24 hours and provide a detailed response within 72 hours.

---

## Security Model

### Admin Structure

META-VE uses a **two-tier admin model** with strict limitations:

| Role | Capabilities | Cannot Do |
|------|--------------|-----------|
| **META MSIG** | Configure parameters, whitelist pools | Extract user funds |
| **LIQUIDATION MSIG** | Withdraw NFTs after liquidation | Act without supermajority |

**Critical Property:** Neither MSIG can extract user assets under normal operation.

### Immutable Constraints

- Fee percentages are **immutable constants**
- Core contract addresses are **immutable**
- No upgrade proxy patterns
- All asset flows are **user-initiated or algorithmic**

---

## Verification Status

### Test Coverage

| Category | Count | Status |
|----------|-------|--------|
| Unit Tests | 692 | ✅ Pass |
| Fork Tests (Mainnet) | 141 | ✅ Pass |
| Stress Tests | 17 | ✅ Pass |
| Adversarial Tests | 30 | ✅ Pass |
| **Total** | **880** | ✅ |

### Formal Verification

| Tool | Properties | Status |
|------|------------|--------|
| Halmos (Symbolic) | 17 | ✅ Proven |
| Echidna (Fuzzing) | 21 | ✅ Pass |
| Certora (SMT) | 24 | ✅ Verified |
| **Total** | **62** | ✅ |

### Static Analysis

- **Slither:** 208 findings reviewed, 0 critical
- **Contract Sizes:** All under EIP-170 limit

---

## Security Features

### Transfer Settlement Protections

| Protection | Description |
|------------|-------------|
| **Sweep on Amount** | Unclaimed rewards calculated on transferred amount, not remaining balance |
| **Sender Checkpoint Preserved** | Sender can still claim on remaining balance after transfer |
| **Round-UP Recipient Blending** | Prevents dust accumulation from repeated small transfers |
| **Self-Transfer Guard** | Self-transfers are no-op (no sweep, no checkpoint change) |

### Anti-Gaming Measures

| Measure | Purpose |
|---------|---------|
| **Epoch Locks** | Prevents vote-and-dump attacks |
| **Bribe Snapshot Window** | 1-hour window prevents last-second sniping |
| **Bribe Claim Deadline** | Wednesday 23:00 UTC cutoff |
| **Liquidation Delays** | 90-day voting + dual supermajority required |

---

## Known Limitations

1. **Proof Lag:** Cross-chain L1 proofs have 2-3 hour delay
2. **Epoch Timing:** All operations aligned to weekly epochs
3. **Consolidation Window:** Cannot consolidate NFTs in first hour after epoch flip (Aerodrome restriction)

---

## Audit Status

The protocol has undergone internal security review and extensive formal verification.

Third-party audit reports will be published when available.

---

## Bug Bounty

We are considering a formal bug bounty program. Contact ds@tokenisys.com for details.

---

© 2026 Tokenisys. All rights reserved.
]]>