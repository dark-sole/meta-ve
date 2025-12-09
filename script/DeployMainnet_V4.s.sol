// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/Meta.sol";
import "../contracts/VToken.sol";
import "../contracts/CToken.sol";
import "../contracts/RToken.sol";
import "../contracts/VeAeroSplitter.sol";

/**
 * @title DeployMainnet_V4
 * @notice Phase 1: Deploy core META V4 ecosystem on Base Mainnet
 * 
 * READS FROM .env:
 *   TOKENISYS_ADDRESS    - Receives 1% V-AERO + 1% C-AERO (+ 2.8% META TGE)
 *   TREASURY_ADDRESS     - Receives 5% META emissions
 *   META_MSIG            - Protocol governance (whitelists, updates)
 *   LIQUIDATION_MULTISIG - Receives veAERO NFTs on liquidation
 * 
 * DEPLOYMENT ORDER:
 *   1. VToken (V-AERO)
 *   2. CToken (C-AERO)
 *   3. RToken (R-AERO)
 *   4. Meta
 *   5. VeAeroSplitter
 *   6-12. Wire contracts
 * 
 * POST-DEPLOYMENT (Phase 2 - separate):
 *   - Create META-AERO LP pool on Aerodrome (Tokenisys)
 *   - Set LP pool and gauge in Meta
 *   - Transfer ownership to MSIG
 * 
 * RUN:
 *   source .env
 *   forge script script/DeployMainnet_V4.s.sol:DeployMainnet_V4 \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     -vvvv
 */
contract DeployMainnet_V4 is Script {
    // ═══════════════════════════════════════════════════════════════════════
    // AERODROME (Base Mainnet) - IMMUTABLE
    // ═══════════════════════════════════════════════════════════════════════
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant VE_AERO = 0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4;
    address constant VOTER = 0x16613524e02ad97eDfeF371bC883F2F5d6C480A5;
    address constant EPOCH_GOVERNOR = 0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497;

    function run() external {
        // ═══════════════════════════════════════════════════════════════════
        // LOAD CONFIG FROM .env
        // ═══════════════════════════════════════════════════════════════════
        
        address tokenisys = vm.envAddress("TOKENISYS_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address msig = vm.envAddress("META_MSIG");
        address liquidationMultisig = vm.envAddress("LIQUIDATION_MULTISIG");
        
        console.log("\n");
        console.log("============================================================");
        console.log("           META V4 MAINNET DEPLOYMENT - PHASE 1             ");
        console.log("============================================================");
        console.log("");
        console.log("CONFIGURATION:");
        console.log("  Tokenisys:          ", tokenisys);
        console.log("  Treasury:           ", treasury);
        console.log("  META MSIG:          ", msig);
        console.log("  Liquidation MSIG:   ", liquidationMultisig);
        console.log("");
        console.log("AERODROME:");
        console.log("  AERO:               ", AERO);
        console.log("  veAERO:             ", VE_AERO);
        console.log("  Voter:              ", VOTER);
        console.log("  Epoch Governor:     ", EPOCH_GOVERNOR);
        console.log("");
        
        // Validate addresses
        require(tokenisys != address(0), "TOKENISYS_ADDRESS not set");
        require(treasury != address(0), "TREASURY_ADDRESS not set");
        require(msig != address(0), "META_MSIG not set");
        require(liquidationMultisig != address(0), "LIQUIDATION_MULTISIG not set");
        
        vm.startBroadcast();
        
        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        require(deployer.balance > 0.001 ether, "Insufficient ETH for deployment");
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 1-3: DEPLOY TOKENS
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Step 1-3: Deploy Tokens ===");
        
        VToken vToken = new VToken();
        console.log("VToken (V-AERO):     ", address(vToken));
        
        CToken cToken = new CToken();
        console.log("CToken (C-AERO):     ", address(cToken));
        
        RToken rToken = new RToken();
        console.log("RToken (R-AERO):     ", address(rToken));
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 4: DEPLOY META
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Step 4: Deploy Meta ===");
        
        uint64 genesisTime = uint64(block.timestamp);
        console.log("Genesis Time:        ", genesisTime);
        
        Meta meta = new Meta(
            genesisTime,
            tokenisys,      // Receives 2.8% META at TGE
            treasury,       // Receives 5% of emissions
            deployer,       // DEPLOYER as initial msig (for wiring)
            AERO            // AERO token address
        );
        console.log("Meta:                ", address(meta));
        console.log("  (Initial msig = deployer for wiring)");
        
        // ═══════════════════════════════════════════════════════════════════
        // STEP 5: DEPLOY VEAEROSPLITTER
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Step 5: Deploy VeAeroSplitter ===");
        
        VeAeroSplitter splitter = new VeAeroSplitter(
            VE_AERO,                // veAERO NFT contract
            AERO,                   // AERO token
            address(meta),          // Meta contract
            address(vToken),        // V-AERO token
            address(cToken),        // C-AERO token
            address(rToken),        // R-AERO token
            tokenisys,              // Receives 1% V-AERO + 1% C-AERO <-- CORRECTED
            liquidationMultisig,    // Receives veAERO NFTs on liquidation
            VOTER,                  // Aerodrome Voter
            EPOCH_GOVERNOR          // Aerodrome Epoch Governor
        );
        console.log("VeAeroSplitter:      ", address(splitter));
        
        // ═══════════════════════════════════════════════════════════════════
        // STEPS 6-12: WIRE CONTRACTS
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n=== Steps 6-12: Wire Contracts ===");
        
        // Step 6
        vToken.setSplitter(address(splitter));
        console.log("[6] VToken.setSplitter    done");
        
        // Step 7
        cToken.setSplitter(address(splitter));
        console.log("[7] CToken.setSplitter    done");
        
        // Step 8 - CRITICAL
        cToken.setMeta(address(meta));
        console.log("[8] CToken.setMeta        done (CRITICAL)");
        
        // Step 9
        rToken.setSplitter(address(splitter));
        console.log("[9] RToken.setSplitter    done");
        
        // Step 10
        meta.setSplitter(address(splitter));
        console.log("[10] Meta.setSplitter     done");
        
        // Step 11
        meta.setVToken(address(vToken));
        console.log("[11] Meta.setVToken       done");
        
        // Step 12
        meta.addVEPool(address(cToken), block.chainid);
        console.log("[12] Meta.addVEPool       done (C-AERO, chainId:", block.chainid, ")");
        
        // Step 13 - Transfer MSIG to real address
        meta.setMSIG(msig);
        console.log("[13] Meta.setMSIG         done (transferred to:", msig, ")");
        
        // ===============================================================
        // STEPS 14-17: TRANSFER OWNERSHIP TO MSIG
        // ===============================================================
        
        console.log("\n=== Steps 14-17: Transfer Ownership ===");
        
        // Step 14
        vToken.transferOwnership(msig);
        console.log("[14] VToken.transferOwnership    done");
        
        // Step 15
        cToken.transferOwnership(msig);
        console.log("[15] CToken.transferOwnership    done");
        
        // Step 16
        rToken.transferOwnership(msig);
        console.log("[16] RToken.transferOwnership    done");
        
        // Step 17
        splitter.transferOwnership(msig);
        console.log("[17] Splitter.transferOwnership  done");
        
        console.log("\nAll contracts now owned by MSIG:", msig);
        
        vm.stopBroadcast();
        
        // ═══════════════════════════════════════════════════════════════════
        // SUMMARY
        // ═══════════════════════════════════════════════════════════════════
        
        console.log("\n");
        console.log("============================================================");
        console.log("           PHASE 1 DEPLOYMENT COMPLETE                      ");
        console.log("============================================================");
        console.log("");
        console.log("DEPLOYED CONTRACTS:");
        console.log("  META_TOKEN=", address(meta));
        console.log("  V_TOKEN=", address(vToken));
        console.log("  C_TOKEN=", address(cToken));
        console.log("  R_TOKEN=", address(rToken));
        console.log("  VEAERO_SPLITTER=", address(splitter));
        console.log("");
        console.log("MSIG TRANSFERRED TO:", msig);
        console.log("");
        console.log("WIRING COMPLETE:");
        console.log("  [x] VToken.setSplitter");
        console.log("  [x] CToken.setSplitter");
        console.log("  [x] CToken.setMeta");
        console.log("  [x] RToken.setSplitter");
        console.log("  [x] Meta.setSplitter");
        console.log("  [x] Meta.setVToken");
        console.log("  [x] Meta.addVEPool(CToken)");
        console.log("  [x] Meta.setMSIG (transferred to real MSIG)");
        console.log("");
        console.log("OWNERSHIP TRANSFERRED:");
        console.log("  [x] VToken  -> MSIG");
        console.log("  [x] CToken  -> MSIG");
        console.log("  [x] RToken  -> MSIG");
        console.log("  [x] Splitter -> MSIG");
        console.log("  [x] Meta     -> MSIG (via setMSIG)");
        console.log("");
        console.log("LP POOL STATUS:");
        console.log("  [ ] Meta.setLPPool      (Phase 2)");
        console.log("  [ ] Meta.setLPGauge     (Phase 2)");
        console.log("  [ ] Meta.lockLPGauge    (Phase 2, optional)");
        console.log("");
        console.log("PHASE 2 (Tokenisys):");
        console.log("  1. Create META-AERO pool on Aerodrome");
        console.log("  2. Seed initial liquidity");
        console.log("  3. Run SetLPGauge script");
        console.log("");
        console.log("============================================================");
        console.log("");
        console.log("Add to .env:");
        console.log("  META_TOKEN=", address(meta));
        console.log("  V_TOKEN=", address(vToken));
        console.log("  C_TOKEN=", address(cToken));
        console.log("  R_TOKEN=", address(rToken));
        console.log("  VEAERO_SPLITTER=", address(splitter));
        console.log("");
    }
}

/**
 * @title SetLPGauge
 * @notice Phase 2: Set LP pool and gauge after Tokenisys creates the pool
 * 
 * RUN:
 *   source .env
 *   forge script script/DeployMainnet_V4.s.sol:SetLPGauge \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     -vvvv
 */
contract SetLPGauge is Script {
    function run() external {
        address metaAddress = vm.envAddress("META_TOKEN");
        address lpPool = vm.envAddress("LP_POOL");
        address lpGauge = vm.envAddress("LP_GAUGE");
        
        console.log("Meta:", metaAddress);
        console.log("LP Pool:", lpPool);
        console.log("LP Gauge:", lpGauge);
        
        require(metaAddress != address(0), "META_TOKEN not set");
        require(lpPool != address(0), "LP_POOL not set");
        require(lpGauge != address(0), "LP_GAUGE not set");
        
        vm.startBroadcast();
        
        Meta meta = Meta(metaAddress);
        
        meta.setLPPool(lpPool);
        console.log("[13] setLPPool done");
        
        meta.setLPGauge(lpGauge);
        console.log("[14] setLPGauge done");
        
        vm.stopBroadcast();
        
        console.log("\n");
        console.log("============================================================");
        console.log("           PHASE 2 COMPLETE - LP GAUGE CONFIGURED           ");
        console.log("============================================================");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Verify: cast call", metaAddress, "\"lpPool()\"");
        console.log("  2. Verify: cast call", metaAddress, "\"lpGauge()\"");
        console.log("  3. Optional: Run LockLPGauge script");
        console.log("  4. Transfer ownership to MSIG");
        console.log("");
    }
}

/**
 * @title LockLPGauge
 * @notice Phase 2 (optional): Lock LP gauge configuration permanently
 * 
 * WARNING: IRREVERSIBLE
 */
contract LockLPGauge is Script {
    function run() external {
        address metaAddress = vm.envAddress("META_TOKEN");
        
        console.log("Meta:", metaAddress);
        console.log("");
        console.log("WARNING: This will PERMANENTLY lock the LP gauge!");
        console.log("         The LP gauge address cannot be changed after this.");
        console.log("");
        
        vm.startBroadcast();
        Meta(metaAddress).lockLPGauge();
        vm.stopBroadcast();
        
        console.log("[15] LP gauge locked permanently");
    }
}

/**
 * @title TransferOwnership
 * @notice Final step: Transfer all contract ownership to MSIG
 */
contract TransferOwnership is Script {
    function run() external {
        address vTokenAddress = vm.envAddress("V_TOKEN");
        address cTokenAddress = vm.envAddress("C_TOKEN");
        address rTokenAddress = vm.envAddress("R_TOKEN");
        address splitterAddress = vm.envAddress("VEAERO_SPLITTER");
        address msig = vm.envAddress("META_MSIG");
        
        console.log("Transferring ownership to MSIG:", msig);
        
        vm.startBroadcast();
        
        VToken(vTokenAddress).transferOwnership(msig);
        console.log("VToken ownership transferred");
        
        CToken(cTokenAddress).transferOwnership(msig);
        console.log("CToken ownership transferred");
        
        RToken(rTokenAddress).transferOwnership(msig);
        console.log("RToken ownership transferred");
        
        VeAeroSplitter(splitterAddress).transferOwnership(msig);
        console.log("VeAeroSplitter ownership transferred");
        
        vm.stopBroadcast();
        
        console.log("\n");
        console.log("============================================================");
        console.log("           OWNERSHIP TRANSFER COMPLETE                      ");
        console.log("============================================================");
        console.log("");
        console.log("All contracts now owned by:", msig);
        console.log("");
        console.log("Note: Meta.sol msig was set in constructor");
        console.log("");
    }
}
