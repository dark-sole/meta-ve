// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/Meta.sol";
import "../contracts/VToken.sol";
import "../contracts/CToken.sol";
import "../contracts/RToken.sol";
import "../contracts/VeAeroSplitter.sol";
import "../contracts/VeAeroLiquidation.sol";
import "../contracts/VeAeroBribes.sol";
import "../contracts/VoteLib.sol";
import "../contracts/EmissionsVoteLib.sol";

/**
 * @title DeployMainnet_DELTA
 * @notice Deploy META DELTA ecosystem on Base Mainnet
 * 
 * DELTA CHANGES (from GAMMA):
 * - VeAeroSplitter: Transfer re-indexes unclaimed fees (not sweep to Tokenisys)
 * - VeAeroSplitter: Added feeSwapper integration for non-AERO fee tokens
 * - VeAeroSplitter: collectFees() now pushes non-AERO to FeeSwapper
 * - VeAeroSplitter: processSwappedFees() callback for FeeSwapper
 * - FeeSwapper deployed separately after this script
 * 
 * INHERITED FROM GAMMA:
 * - Recipient checkpoint blended with round-UP
 * - Self-transfer guard (no-op)
 * - VeAeroBribes: Excludes META's V-AERO from bribe denominator
 * - EmissionsVoteLib: Fed emissions voting enabled
 * - CToken: Direct AERO fee distribution via feePerCToken
 * - Auto rebase collection in resetEpoch()
 * - Bribe claim deadline (Wed 23:00)
 * - Tokenisys sweep window (Wed 23:00-00:00)
 * 
 * DEPLOYMENT ORDER (9 contracts):
 *   nonce+0: VToken
 *   nonce+1: CToken
 *   nonce+2: RToken
 *   nonce+3: Meta
 *   nonce+4: VeAeroLiquidation (uses predicted Splitter)
 *   nonce+5: VoteLib
 *   nonce+6: EmissionsVoteLib
 *   nonce+7: VeAeroBribes (uses predicted Splitter)
 *   nonce+8: VeAeroSplitter (DELTA - with feeSwapper support)
 * 
 * POST-DEPLOYMENT:
 *   1. Deploy FeeSwapper via DeployFeeSwapper_DELTA.s.sol
 *   2. MSIG: Splitter.setFeeSwapper(feeSwapper)
 *   3. MSIG: FeeSwapper.setRoute() for each fee token
 *   4. MSIG: Meta.addVEPool(cToken, address(0))
 * 
 * RUN:
 *   source .env
 *   forge script script/DeployMainnet_DELTA.s.sol:DeployMainnet_DELTA \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 */
contract DeployMainnet_DELTA is Script {
    // ═══════════════════════════════════════════════════════════════════════
    // AERODROME ADDRESSES (BASE MAINNET - IMMUTABLE)
    // ═══════════════════════════════════════════════════════════════════════
    
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant VE_AERO = 0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4;
    address constant VOTER = 0x16613524e02ad97eDfeF371bC883F2F5d6C480A5;
    address constant EPOCH_GOVERNOR = 0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497;

    // ═══════════════════════════════════════════════════════════════════════
    // DEFAULTS
    // ═══════════════════════════════════════════════════════════════════════
    
    uint256 constant DEFAULT_MAX_POOLS = 200;
    uint256 constant DEFAULT_EXPECTED_MAX_SUPPLY = 100_000_000e18;

    function run() external {
        // ═══════════════════════════════════════════════════════════════════
        // LOAD ENVIRONMENT
        // ═══════════════════════════════════════════════════════════════════
        
        address tokenisys = vm.envAddress("TOKENISYS_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address msig = vm.envAddress("META_MSIG");
        address liquidationMultisig = vm.envAddress("LIQUIDATION_MULTISIG");
        
        uint256 maxPools = vm.envOr("MAX_POOLS", DEFAULT_MAX_POOLS);
        uint256 expectedMaxSupply = vm.envOr("EXPECTED_MAX_SUPPLY", DEFAULT_EXPECTED_MAX_SUPPLY);
        
        console.log("\n============================================================");
        console.log("              META DELTA MAINNET DEPLOYMENT                  ");
        console.log("============================================================");
        console.log("  DELTA CHANGES:");
        console.log("  - Transfer re-indexes unclaimed fees (not sweep)");
        console.log("  - FeeSwapper integration for non-AERO fee tokens");
        console.log("  - collectFees() pushes non-AERO to FeeSwapper");
        console.log("  - processSwappedFees() callback from FeeSwapper");
        console.log("============================================================");
        console.log("  INHERITED (GAMMA):");
        console.log("  - Recipient checkpoint blended with round-UP");
        console.log("  - Self-transfer guard (no-op)");
        console.log("  - VeAeroBribes: META V-AERO excluded from bribe denominator");
        console.log("  - EmissionsVoteLib: Fed emissions voting enabled");
        console.log("  - Auto rebase in resetEpoch()");
        console.log("  - Bribe deadline Wed 23:00, sweep window 23:00-00:00");
        console.log("============================================================\n");
        
        console.log("--- CONFIGURATION ---");
        console.log("Tokenisys:        ", tokenisys);
        console.log("Treasury:         ", treasury);
        console.log("META MSIG:        ", msig);
        console.log("Liquidation MSIG: ", liquidationMultisig);
        console.log("Max Pools:        ", maxPools);
        console.log("Expected Supply:  ", expectedMaxSupply / 1e18, "tokens\n");
        
        // Validate configuration
        require(tokenisys != address(0), "TOKENISYS_ADDRESS not set");
        require(treasury != address(0), "TREASURY_ADDRESS not set");
        require(msig != address(0), "META_MSIG not set");
        require(liquidationMultisig != address(0), "LIQUIDATION_MULTISIG not set");
        require(maxPools >= 50 && maxPools <= 1000, "MAX_POOLS must be 50-1000");
        require(expectedMaxSupply >= 1_000_000e18, "EXPECTED_MAX_SUPPLY too low");
        
        vm.startBroadcast();
        
        address deployer = msg.sender;
        uint64 startingNonce = vm.getNonce(deployer);
        
        console.log("--- DEPLOYER INFO ---");
        console.log("Deployer:", deployer);
        console.log("Starting nonce:", startingNonce);
        console.log("Balance:", deployer.balance);
        require(deployer.balance > 0.001 ether, "Insufficient ETH for deployment");
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 1: PREDICT SPLITTER ADDRESS
        // ═══════════════════════════════════════════════════════════════════
        
        // Splitter will be deployed at nonce+8
        address predictedSplitter = vm.computeCreateAddress(deployer, startingNonce + 8);
        console.log("\n=== Phase 1: Address Prediction ===");
        console.log("Predicted Splitter (nonce+8):", predictedSplitter);
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 2: DEPLOY TOKENS (nonce+0, +1, +2)
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Phase 2: Deploy Tokens ===");
        
        // nonce+0: VToken
        VToken vToken = new VToken(VOTER);
        console.log("[nonce+0] VToken:", address(vToken));
        require(vm.getNonce(deployer) == startingNonce + 1, "Nonce mismatch after VToken");
        
        // nonce+1: CToken
        CToken cToken = new CToken();
        console.log("[nonce+1] CToken:", address(cToken));
        require(vm.getNonce(deployer) == startingNonce + 2, "Nonce mismatch after CToken");
        
        // nonce+2: RToken
        RToken rToken = new RToken();
        console.log("[nonce+2] RToken:", address(rToken));
        require(vm.getNonce(deployer) == startingNonce + 3, "Nonce mismatch after RToken");
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 3: DEPLOY META (nonce+3)
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Phase 3: Deploy Meta ===");
        
        // Genesis time: current day midnight UTC
        uint64 genesisTime = uint64(((block.timestamp / 1 days)) * 1 days);
        console.log("Genesis Time:", genesisTime);
        
        // nonce+3: Meta (deployer as initial msig for wiring, transferred later)
        Meta meta = new Meta(genesisTime, tokenisys, treasury, deployer, AERO);
        console.log("[nonce+3] Meta:", address(meta));
        require(vm.getNonce(deployer) == startingNonce + 4, "Nonce mismatch after Meta");

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 4: DEPLOY SUPPORT CONTRACTS (nonce+4, +5, +6, +7)
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Phase 4: Deploy Support Contracts ===");
        console.log("Using predicted Splitter:", predictedSplitter);

        // nonce+4: VeAeroLiquidation
        VeAeroLiquidation liquidation = new VeAeroLiquidation(
            address(cToken), 
            address(vToken), 
            predictedSplitter
        );
        console.log("[nonce+4] Liquidation:", address(liquidation));
        require(vm.getNonce(deployer) == startingNonce + 5, "Nonce mismatch after Liquidation");

        // nonce+5: VoteLib
        VoteLib voteLib = new VoteLib();
        console.log("[nonce+5] VoteLib:", address(voteLib));
        require(vm.getNonce(deployer) == startingNonce + 6, "Nonce mismatch after VoteLib");
        
        // nonce+6: EmissionsVoteLib
        EmissionsVoteLib emissionsVoteLib = new EmissionsVoteLib();
        console.log("[nonce+6] EmissionsVoteLib:", address(emissionsVoteLib));
        require(vm.getNonce(deployer) == startingNonce + 7, "Nonce mismatch after EmissionsVoteLib");

        // nonce+7: VeAeroBribes (with META address for bribe denominator fix)
        VeAeroBribes bribes = new VeAeroBribes(
            predictedSplitter,
            address(vToken), 
            tokenisys,
            address(meta)
        );
        console.log("[nonce+7] Bribes:", address(bribes));
        console.log("         META excluded from bribe denominator: YES");
        require(vm.getNonce(deployer) == startingNonce + 8, "Nonce mismatch after Bribes");
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 5: DEPLOY SPLITTER (nonce+8) - MUST MATCH PREDICTION
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Phase 5: Deploy Splitter (DELTA) ===");
        
        // nonce+8: VeAeroSplitter (DELTA version with feeSwapper support)
        VeAeroSplitter splitter = new VeAeroSplitter(
            VE_AERO,
            AERO,
            address(meta),
            address(vToken),
            address(cToken),
            address(rToken),
            tokenisys,
            liquidationMultisig,
            address(liquidation),
            address(bribes),
            VOTER,
            EPOCH_GOVERNOR
        );
        console.log("[nonce+8] Splitter (DELTA):", address(splitter));
        console.log("         feeSwapper support: YES (set via setFeeSwapper after FeeSwapper deploy)");
        
        // CRITICAL: Verify prediction was correct
        require(
            address(splitter) == predictedSplitter, 
            "FATAL: Splitter address mismatch! Liquidation and Bribes have wrong reference."
        );
        console.log(">>> Splitter address VERIFIED matches prediction <<<");
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 6: WIRE CONTRACTS
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Phase 6: Wire Contracts ===");
        
        // VToken wiring
        vToken.setSplitter(address(splitter));
        vToken.setLiquidation(address(liquidation));
        vToken.configureVotingStorage(maxPools, expectedMaxSupply);
        console.log("VToken: splitter, liquidation, storage configured");
        
        // CToken wiring
        cToken.setSplitter(address(splitter));
        cToken.setLiquidation(address(liquidation));
        cToken.setMeta(address(meta));
        cToken.setAero(AERO);
        cToken.setEmissionsVoteLib(address(emissionsVoteLib));
        console.log("CToken: splitter, liquidation, meta, aero, emissionsVoteLib configured");
        
        // RToken wiring
        rToken.setSplitter(address(splitter));
        console.log("RToken: splitter configured");
        
        // Meta wiring (deployer is msigTreasury, so this works)
        meta.setSplitter(address(splitter));
        meta.setVToken(address(vToken));
        console.log("Meta: splitter, vToken configured");
        
        // Splitter wiring
        splitter.setVoteLib(address(voteLib));
        splitter.setEmissionsVoteLib(address(emissionsVoteLib));
        console.log("Splitter: voteLib, emissionsVoteLib configured");
        console.log("Splitter: feeSwapper NOT SET (deploy FeeSwapper first, then MSIG sets)");
        
        // EmissionsVoteLib wiring
        emissionsVoteLib.setCToken(address(cToken));
        emissionsVoteLib.setSplitter(address(splitter));
        console.log("EmissionsVoteLib: cToken, splitter configured");
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 7: TRANSFER OWNERSHIP TO MSIG
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Phase 7: Transfer Ownership ===");
        
        vToken.transferOwnership(msig);
        console.log("VToken ownership -> MSIG");
        
        cToken.transferOwnership(msig);
        console.log("CToken ownership -> MSIG");
        
        rToken.transferOwnership(msig);
        console.log("RToken ownership -> MSIG");
        
        splitter.transferOwnership(msig);
        console.log("Splitter ownership -> MSIG");
        
        emissionsVoteLib.transferOwnership(msig);
        console.log("EmissionsVoteLib ownership -> MSIG");
        
        meta.setMSIG(msig);
        console.log("Meta msigTreasury -> MSIG");
        
        meta.transferOwnership(msig);
        console.log("Meta owner() -> MSIG");
        
        vm.stopBroadcast();
        
        // ═══════════════════════════════════════════════════════════════════
        // OUTPUT SUMMARY
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n============================================================");
        console.log("              META DELTA DEPLOYMENT COMPLETE                 ");
        console.log("============================================================\n");
        
        console.log("=== DEPLOYED CONTRACTS (9) ===");
        console.log("VToken:           ", address(vToken));
        console.log("CToken:           ", address(cToken));
        console.log("RToken:           ", address(rToken));
        console.log("Meta:             ", address(meta));
        console.log("Liquidation:      ", address(liquidation));
        console.log("Bribes:           ", address(bribes));
        console.log("VoteLib:          ", address(voteLib));
        console.log("EmissionsVoteLib: ", address(emissionsVoteLib));
        console.log("Splitter (DELTA): ", address(splitter));
        
        console.log("\n=== ENVIRONMENT VARIABLES (add to .env) ===");
        console.log("VTOKEN=", address(vToken));
        console.log("CTOKEN=", address(cToken));
        console.log("RTOKEN=", address(rToken));
        console.log("META=", address(meta));
        console.log("LIQUIDATION=", address(liquidation));
        console.log("BRIBES=", address(bribes));
        console.log("VOTELIB=", address(voteLib));
        console.log("EMISSIONSVOTELIB=", address(emissionsVoteLib));
        console.log("SPLITTER=", address(splitter));
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Add above addresses to .env");
        console.log("2. Deploy FeeSwapper:");
        console.log("   forge script script/DeployFeeSwapper_DELTA.s.sol --broadcast --verify");
        console.log("3. MSIG: Splitter.setFeeSwapper(feeSwapperAddress)");
        console.log("4. MSIG: FeeSwapper.setRoute() for USDC, WETH, USDbC");
        console.log("5. Deployer: FeeSwapper.transferOwnership(MSIG)");
        console.log("6. MSIG: Meta.addVEPool(CToken, address(0))");
        
        console.log("\n=== GENESIS ===");
        console.log("Genesis Time:", genesisTime);
        console.log("META emissions begin at genesis");
        
        console.log("\n============================================================\n");
    }
}
