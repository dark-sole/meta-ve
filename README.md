# META V4 Protocol

Liquid staking protocol for veAERO on Base, enabling tokenized voting power and auto-compounding yields.

## Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| META Token | [`0xCCDB07280eeDc221b81D14038A7f7C7f87d5b9C5`](https://basescan.org/address/0xCCDB07280eeDc221b81D14038A7f7C7f87d5b9C5) |
| VToken (V-AERO) | [`0xBA3639F0c4C4aB72A88aA76f0dd07C5D1c083d97`](https://basescan.org/address/0xBA3639F0c4C4aB72A88aA76f0dd07C5D1c083d97) |
| CToken (C-AERO) | [`0xF8304F37B9dfc16a0c43625159A308851D20683f`](https://basescan.org/address/0xF8304F37B9dfc16a0c43625159A308851D20683f) |
| RToken (R-AERO) | [`0x99a0CA6E2c8571EB29D78137d9C3FF2006b9AAf8`](https://basescan.org/address/0x99a0CA6E2c8571EB29D78137d9C3FF2006b9AAf8) |
| VeAeroSplitter | [`0x8082dF869B67067d05De583Ea3550FCEE4A24B22`](https://basescan.org/address/0x8082dF869B67067d05De583Ea3550FCEE4A24B22) |

**Deployment Date:** December 9, 2025  
**Block:** 39249818  
**All contracts verified on BaseScan**

---

## Architecture Overview

```
User deposits AERO
        │
        ▼
┌───────────────────┐
│  VeAeroSplitter   │ ◄── Central hub, holds veAERO NFT
└───────────────────┘
        │
        ├─────────────────┬─────────────────┐
        ▼                 ▼                 ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│   VToken    │   │   CToken    │   │   RToken    │
│  (V-AERO)   │   │  (C-AERO)   │   │  (R-AERO)   │
│   Voting    │   │ Compounding │   │  Redeemable │
└─────────────┘   └─────────────┘   └─────────────┘
        │                 │
        └────────┬────────┘
                 ▼
        ┌─────────────┐
        │    META     │ ◄── Governance token, LP emissions
        └─────────────┘
```

---

## Token Types

### V-AERO (Voting)
- 1:1 with deposited AERO
- Holders vote on Aerodrome gauge weights
- Earns voting rewards (bribes + fees)
- Earns META emissions

### C-AERO (Compounding)
- Auto-compounds voting rewards back into veAERO
- Grows in value relative to AERO over time
- Earns META emissions
- Ideal for passive yield

### R-AERO (Redeemable)
- Redeemable for underlying AERO
- Used for redemptions and settlements
- No voting power or META emissions

### META (Governance)
- Protocol governance token
- 1B max supply, 2% annual decay
- 2.8% to Tokenisys at TGE
- 5% of emissions to Treasury
- Remaining to LP pool stakers

---

## Fee Structure

| Fee | Recipient | Description |
|-----|-----------|-------------|
| 1% V-AERO | Tokenisys | On all V-AERO mints |
| 1% C-AERO | Tokenisys | On all C-AERO mints |
| 5% META | Treasury | Of all META emissions |

---

## Governance

**MSIG Address:** `0xeAcf5B81136db1c29380BdaCDBE5c7e1138A1d93`

The MSIG controls:
- Pool whitelist management
- Emergency functions
- LP pool/gauge configuration
- Protocol upgrades

---

## Contract Descriptions

### `Meta.sol`
Governance token with emission schedule. Handles TGE distribution, epoch-based emissions with 2% annual decay, and LP reward distribution.

### `VToken.sol`
Voting token representing deposited AERO. Holders can vote on Aerodrome gauges through the splitter.

### `CToken.sol`
Compounding token that auto-reinvests voting rewards. Exchange rate increases over time as rewards compound.

### `RToken.sol`
Redeemable token for AERO withdrawals. Minted during redemption operations.

### `VeAeroSplitter.sol`
Central contract managing the veAERO NFT. Handles deposits, voting, reward distribution, and epoch management.

### `DynamicGaugeVoteStorage.sol`
Gas-optimized storage for gauge voting weights using bit-packing.

### `DynamicPoolRegistry.sol`
Manages the whitelist of approved Aerodrome pools.

### `L1ProofVerifier.sol`
Cross-chain proof verification for multi-chain expansion (future use).

---

## Building

```bash
# Install dependencies
forge install

# Compile
forge build

# Run tests
forge test
```

---

## Deployment

See `script/DeployMainnet_V4.s.sol` for the deployment script used.

```bash
# Deploy (requires .env with PRIVATE_KEY and RPC URLs)
forge script script/DeployMainnet_V4.s.sol:DeployMainnet_V4 \
  --rpc-url $BASE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

---

## Security

- All contracts verified on BaseScan
- Ownership transferred to multi-sig
- 216 tests passing (V4 test suite)

---

## License

MIT
