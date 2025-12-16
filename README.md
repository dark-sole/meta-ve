# META-VE Protocol

Tokenisys META Protocol - veAERO tokenization on Base.

## Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| VToken (V-AERO) | `0x56b1c70EC3e5751F513Bb4E1C1B041398413246A` |
| CToken (C-AERO) | `0x07b3a3c5f5B9dAd9b36fC6Faa40fd4bFBcC4aA4E` |
| RToken (R-AERO) | `0x3dB3fF66d9188694f5b6FA8ccdfF9c3921b77832` |
| Meta | `0x24408894b6C34ed11a609db572d5a2d7e7b187C6` |
| VeAeroLiquidation | `0x289d982DA03d7DA73EE88F0de8799eBF5B7672cc` |
| VeAeroBribes | `0x67be8b66c65FC277e86990F7F36b21bdE4e1dE4E` |
| VoteLib | `0x16a6359d45386eD4a26458558A0542B826Bb72c0` |
| VeAeroSplitter | `0xf47Ece65481f0709e78c58f802d8e76B20fd4361` |

## Documentation

- [Technical Handbook](docs/TECHNICAL_HANDBOOK.md)
- [Deployment Summary](docs/DEPLOYMENT_SUMMARY.md)
- [Multi-Chain Architecture](docs/META_MultiChain_Architecture.md)
- [Test Results](docs/TEST_RESULTS.md)
- [Draft Guide (PDF)](docs/Meta_1225_DRAFT_GUIDE.pdf)
- [Function Reference](docs/COMPLETE_FUNCTION_REFERENCE.md)
- [Teaser](docs/META_VE_OnePager.html)

## Directory Structure

```
├── contracts/
│   ├── CToken.sol
│   ├── DynamicGaugeVoteStorage.sol
│   ├── DynamicPoolRegistry.sol
│   ├── IVoteLib.sol
│   ├── Interfaces.sol
│   ├── L1ProofVerifier.sol
│   ├── Meta.sol
│   ├── RToken.sol
│   ├── VToken.sol
│   ├── VeAeroBribes.sol
│   ├── VeAeroLiquidation.sol
│   ├── VeAeroSplitter.sol
│   └── VoteLib.sol
├── deployments/
│   └── base-mainnet.json
├── docs/
│   ├── DEPLOYMENT_SUMMARY.md
│   ├── META_MultiChain_Architecture.md
│   ├── Meta_1225_DRAFT_GUIDE.pdf
│   ├── TECHNICAL_HANDBOOK.md
│   └── TEST_RESULTS.md
└── scripts/
    └── DeployMainnet_V8.s.sol
```

## License

Proprietary - © Tokenisys. All rights reserved.
Enquiries: ds@tokenisys.com
