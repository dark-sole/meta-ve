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

/**
 * @title DeployMainnet_V8
 * @notice Deploy META V8 ecosystem on Base Mainnet
 * 
 * CHANGES FROM V7:
 * - Meta.addVEPool() no longer requires gauge address
 * - Allows META staking before Aerodrome gauge exists
 * - LP rewards accumulate until gauge is set via setPoolLPGauge()
 * 
 * DEPLOYMENT ORDER (8 contracts):
 *   nonce+0: VToken
 *   nonce+1: CToken
 *   nonce+2: RToken
 *   nonce+3: Meta (V8 - gauge optional)
 *   nonce+4: VeAeroLiquidation
 *   nonce+5: VeAeroBribes
 *   nonce+6: VoteLib
 *   nonce+7: VeAeroSplitter
 * 
 * RUN:
 *   source .env
 *   forge script script/DeployMainnet_V8.s.sol:DeployMainnet_V8 \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY \
 *     --evm-version cancun \
 *     --use 0.8.24 \
 *     -vvvv
 */
contract DeployMainnet_V8 is Script {
    // Aerodrome (Base Mainnet)
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant VE_AERO = 0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4;
    address constant VOTER = 0x16613524e02ad97eDfeF371bC883F2F5d6C480A5;
    address constant EPOCH_GOVERNOR = 0xC7150B9909DFfCB5e12E4Be6999D6f4b827eE497;

    // Defaults
    uint256 constant DEFAULT_MAX_POOLS = 200;
    uint256 constant DEFAULT_EXPECTED_MAX_SUPPLY = 100_000_000e18;

    function run() external {
        address tokenisys = vm.envAddress("TOKENISYS_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address msig = vm.envAddress("META_MSIG");
        address liquidationMultisig = vm.envAddress("LIQUIDATION_MULTISIG");
        
        uint256 maxPools = vm.envOr("MAX_POOLS", DEFAULT_MAX_POOLS);
        uint256 expectedMaxSupply = vm.envOr("EXPECTED_MAX_SUPPLY", DEFAULT_EXPECTED_MAX_SUPPLY);
        
        console.log("\n============================================================");
        console.log("              META V8 MAINNET DEPLOYMENT                    ");
        console.log("============================================================");
        console.log("  CHANGE: addVEPool() no longer requires gauge address");
        console.log("============================================================\n");
        console.log("Tokenisys:        ", tokenisys);
        console.log("Treasury:         ", treasury);
        console.log("META MSIG:        ", msig);
        console.log("Liquidation MSIG: ", liquidationMultisig);
        console.log("Max Pools:        ", maxPools);
        console.log("Expected Supply:  ", expectedMaxSupply / 1e18, "tokens\n");
        
        require(tokenisys != address(0), "TOKENISYS_ADDRESS not set");
        require(treasury != address(0), "TREASURY_ADDRESS not set");
        require(msig != address(0), "META_MSIG not set");
        require(liquidationMultisig != address(0), "LIQUIDATION_MULTISIG not set");
        require(maxPools >= 50 && maxPools <= 1000, "MAX_POOLS must be 50-1000");
        require(expectedMaxSupply >= 1_000_000e18, "EXPECTED_MAX_SUPPLY too low");
        
        vm.startBroadcast();
        
        address deployer = msg.sender;
        uint64 startingNonce = vm.getNonce(deployer);
        
        console.log("Deployer:", deployer);
        console.log("Starting nonce:", startingNonce);
        console.log("Balance:", deployer.balance);
        require(deployer.balance > 0.001 ether, "Insufficient ETH");
        
        // Predict splitter address: startingNonce + 7
        address predictedSplitter = vm.computeCreateAddress(deployer, startingNonce + 7);
        console.log("Predicted Splitter:", predictedSplitter);
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 1-3: Deploy Tokens (nonce+0, +1, +2)
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Step 1-3: Deploy Tokens ===");
        
        VToken vToken = new VToken(VOTER);
        console.log("[1] VToken:", address(vToken));
        
        CToken cToken = new CToken();
        console.log("[2] CToken:", address(cToken));
        
        RToken rToken = new RToken();
        console.log("[3] RToken:", address(rToken));
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 4: Deploy Meta V8 (nonce+3) - GAUGE OPTIONAL
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Step 4: Deploy Meta V8 (gauge optional) ===");
        
        uint64 genesisTime = uint64(((block.timestamp / 1 days) + 1) * 1 days);
        console.log("Genesis Time:", genesisTime);
        
        Meta meta = new Meta(genesisTime, tokenisys, treasury, deployer, AERO);
        console.log("[4] Meta:", address(meta));

        // ═══════════════════════════════════════════════════════════════
        // STEP 5-8: Deploy Liquidation, Bribes, VoteLib, Splitter
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Step 5-8: Deploy Liquidation, Bribes, VoteLib, Splitter ===");
        console.log("Using predicted Splitter:", predictedSplitter);

        VeAeroLiquidation liquidation = new VeAeroLiquidation(
            address(cToken), address(vToken), predictedSplitter
        );
        console.log("[5] Liquidation:", address(liquidation));

        VeAeroBribes bribes = new VeAeroBribes(
            predictedSplitter, address(vToken), tokenisys
        );
        console.log("[6] Bribes:", address(bribes));
        
        VoteLib voteLib = new VoteLib();
        console.log("[7] VoteLib:", address(voteLib));
        
        VeAeroSplitter splitter = new VeAeroSplitter(
            VE_AERO, AERO, address(meta), address(vToken), address(cToken),
            address(rToken), tokenisys, liquidationMultisig, address(liquidation),
            address(bribes), VOTER, EPOCH_GOVERNOR
        );
        console.log("[8] Splitter:", address(splitter));
       
        // Verify prediction
        if (address(splitter) != predictedSplitter) {
            console.log("WARNING: Splitter address mismatch!");
            console.log("  Predicted:", predictedSplitter);
            console.log("  Actual:", address(splitter));
            revert("Splitter address mismatch!");
        }
        console.log("    Splitter address verified!");
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 9-15: Wire Token Contracts
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Steps 9-15: Wire Token Contracts ===");
        
        vToken.setSplitter(address(splitter));
        console.log("[9] VToken.setSplitter done");
        
        cToken.setSplitter(address(splitter));
        console.log("[10] CToken.setSplitter done");
        
        cToken.setMeta(address(meta));
        console.log("[11] CToken.setMeta done");
        
        rToken.setSplitter(address(splitter));
        console.log("[12] RToken.setSplitter done");
        
        meta.setSplitter(address(splitter));
        console.log("[13] Meta.setSplitter done");
        
        meta.setVToken(address(vToken));
        console.log("[14] Meta.setVToken done");
        
        meta.setMSIG(msig);
        console.log("[15] Meta.setMSIG done");
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 16: Initialize VToken Voting Storage
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Step 16: Initialize VToken Pool Registry ===");
        
        vToken.configureVotingStorage(maxPools, expectedMaxSupply);
        console.log("[16] VToken.configureVotingStorage done");
        
        // Verify config
        (uint256 cfgMaxPools, uint256 cfgBits, uint256 cfgSlots, uint256 cfgMax, , ) = vToken.storageConfig();
        require(cfgMaxPools == maxPools, "VToken config verification failed!");
        console.log("     maxPools:", cfgMaxPools);
        console.log("     bitsPerPool:", cfgBits);
        console.log("     poolsPerSlot:", cfgSlots);
        console.log("     maxWeight:", cfgMax);
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 17-18: Set Liquidation on VToken and CToken
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Steps 17-18: Set Liquidation Addresses ===");
        
        vToken.setLiquidation(address(liquidation));
        console.log("[17] VToken.setLiquidation done");
        
        cToken.setLiquidation(address(liquidation));
        console.log("[18] CToken.setLiquidation done");
        
        // ═══════════════════════════════════════════════════════════════
        // STEP 19: Set VoteLib on Splitter
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Step 19: Set VoteLib ===");
        
        splitter.setVoteLib(address(voteLib));
        console.log("[19] Splitter.setVoteLib done");
        
        // ═══════════════════════════════════════════════════════════════
        // STEPS 20-23: Transfer Ownership
        // ═══════════════════════════════════════════════════════════════
        console.log("\n=== Steps 20-23: Transfer Ownership ===");
        
        vToken.transferOwnership(msig);
        console.log("[20] VToken -> MSIG");
        
        cToken.transferOwnership(msig);
        console.log("[21] CToken -> MSIG");
        
        rToken.transferOwnership(msig);
        console.log("[22] RToken -> MSIG");
        
        splitter.transferOwnership(msig);
        console.log("[23] Splitter -> MSIG");
        
        vm.stopBroadcast();
        
        // ═══════════════════════════════════════════════════════════════
        // SUMMARY
        // ═══════════════════════════════════════════════════════════════
        console.log("\n============================================================");
        console.log("           PHASE 1 DEPLOYMENT COMPLETE (V8)                 ");
        console.log("============================================================\n");
        console.log("V_TOKEN=", address(vToken));
        console.log("C_TOKEN=", address(cToken));
        console.log("R_TOKEN=", address(rToken));
        console.log("META_TOKEN=", address(meta));
        console.log("VEAERO_LIQUIDATION=", address(liquidation));
        console.log("VEAERO_BRIBES=", address(bribes));
        console.log("VOTE_LIB=", address(voteLib));
        console.log("VEAERO_SPLITTER=", address(splitter));
        
        console.log("\n--- VERIFICATION CHECKLIST ---");
        console.log("VToken.splitter:", vToken.splitter() == address(splitter) ? "OK" : "FAIL");
        console.log("VToken.liquidation:", vToken.liquidation() == address(liquidation) ? "OK" : "FAIL");
        console.log("CToken.splitter:", cToken.splitter() == address(splitter) ? "OK" : "FAIL");
        console.log("CToken.liquidation:", cToken.liquidation() == address(liquidation) ? "OK" : "FAIL");
        console.log("CToken.meta:", address(cToken.meta()) == address(meta) ? "OK" : "FAIL");
        console.log("RToken.splitter:", rToken.splitter() == address(splitter) ? "OK" : "FAIL");
        console.log("Meta.splitter:", meta.splitter() == address(splitter) ? "OK" : "FAIL");
        console.log("Meta.vToken:", meta.vToken() == address(vToken) ? "OK" : "FAIL");
        console.log("Splitter.voteLib:", address(splitter.voteLib()) == address(voteLib) ? "OK" : "FAIL");
        
        console.log("\n--- OWNERSHIP ---");
        console.log("VToken.owner:", vToken.owner() == msig ? "MSIG" : "WRONG");
        console.log("CToken.owner:", cToken.owner() == msig ? "MSIG" : "WRONG");
        console.log("RToken.owner:", rToken.owner() == msig ? "MSIG" : "WRONG");
        console.log("Splitter.owner:", splitter.owner() == msig ? "MSIG" : "WRONG");
        
        console.log("\n============================================================");
        console.log("NEXT STEPS (MSIG):");
        console.log("1. Meta.addVEPool(SPLITTER, address(0))  <- ENABLES STAKING");
        console.log("2. (Optional) Meta.setLPPool(LP_POOL) <- For Meta's own voting");
        console.log("3. (Later) Meta.setPoolLPGauge(SPLITTER, GAUGE) <- When gauge exists");
        console.log("============================================================\n");
    }
}

/**
 * @title EnableMetaStaking_V8
 * @notice Enable META staking without gauge (V8 feature)
 * 
 * RUN (MSIG must execute):
 *   cast calldata "addVEPool(address,address)" <SPLITTER> 0x0000000000000000000000000000000000000000
 */
contract EnableMetaStaking_V8 is Script {
    function run() external {
        address metaAddress = vm.envAddress("META_TOKEN");
        address splitterAddress = vm.envAddress("VEAERO_SPLITTER");
        
        console.log("\n=== V8: Enable META Staking (No Gauge Required) ===");
        console.log("Meta:", metaAddress);
        console.log("Splitter:", splitterAddress);
        
        require(metaAddress != address(0), "META_TOKEN not set");
        require(splitterAddress != address(0), "VEAERO_SPLITTER not set");
        
        vm.startBroadcast();
        
        Meta meta = Meta(metaAddress);
        
        // V8: Can now add VE pool with address(0) gauge!
        meta.addVEPool(splitterAddress, address(0));
        console.log("[1] addVEPool(splitter, address(0)) done");
        console.log("    META staking now enabled!");
        console.log("    LP rewards will accumulate until gauge is set");
        
        vm.stopBroadcast();
        
        console.log("\n=== Staking Enabled! ===");
        console.log("Users can now stake META via lockAndVote()");
        console.log("\nOptional next steps:");
        console.log("  Meta.setLPPool(lpPool) - for Meta's own V-AERO voting");
        console.log("  Meta.setPoolLPGauge(splitter, gauge) - when Aerodrome gauge exists");
    }
}

/**
 * @title SetLPGauge_V8
 * @notice Set gauge after Aerodrome creates it (releases accumulated rewards)
 */
contract SetLPGauge_V8 is Script {
    function run() external {
        address metaAddress = vm.envAddress("META_TOKEN");
        address splitterAddress = vm.envAddress("VEAERO_SPLITTER");
        address lpGauge = vm.envAddress("LP_GAUGE");
        
        console.log("\n=== V8: Set LP Gauge (Release Accumulated Rewards) ===");
        console.log("Meta:", metaAddress);
        console.log("Splitter:", splitterAddress);
        console.log("LP Gauge:", lpGauge);
        
        require(metaAddress != address(0), "META_TOKEN not set");
        require(splitterAddress != address(0), "VEAERO_SPLITTER not set");
        require(lpGauge != address(0), "LP_GAUGE not set");
        
        vm.startBroadcast();
        
        Meta meta = Meta(metaAddress);
        
        meta.setPoolLPGauge(splitterAddress, lpGauge);
        console.log("[1] setPoolLPGauge done");
        console.log("    LP rewards will now flow to gauge!");
        
        vm.stopBroadcast();
    }
}

/**
 * @title VerifyDeployment_V8
 * @notice Verify all deployment wiring
 */
contract VerifyDeployment_V8 is Script {
    function run() external view {
        address metaAddr = vm.envAddress("META_TOKEN");
        address vTokenAddr = vm.envAddress("V_TOKEN");
        address cTokenAddr = vm.envAddress("C_TOKEN");
        address rTokenAddr = vm.envAddress("R_TOKEN");
        address splitterAddr = vm.envAddress("VEAERO_SPLITTER");
        address bribesAddr = vm.envAddress("VEAERO_BRIBES");
        address liquidationAddr = vm.envAddress("VEAERO_LIQUIDATION");
        address voteLibAddr = vm.envAddress("VOTE_LIB");
        address msig = vm.envAddress("META_MSIG");
        
        console.log("\n============================================================");
        console.log("              V8 DEPLOYMENT VERIFICATION                    ");
        console.log("============================================================\n");
        
        Meta meta = Meta(metaAddr);
        VToken vToken = VToken(vTokenAddr);
        CToken cToken = CToken(cTokenAddr);
        RToken rToken = RToken(rTokenAddr);
        VeAeroSplitter splitter = VeAeroSplitter(splitterAddr);
        
        // Wiring checks
        console.log("=== WIRING ===");
        console.log("VToken.splitter:    ", vToken.splitter() == splitterAddr ? "OK" : "FAIL");
        console.log("VToken.liquidation: ", vToken.liquidation() == liquidationAddr ? "OK" : "FAIL");
        console.log("CToken.splitter:    ", cToken.splitter() == splitterAddr ? "OK" : "FAIL");
        console.log("CToken.liquidation: ", cToken.liquidation() == liquidationAddr ? "OK" : "FAIL");
        console.log("CToken.meta:        ", address(cToken.meta()) == metaAddr ? "OK" : "FAIL");
        console.log("RToken.splitter:    ", rToken.splitter() == splitterAddr ? "OK" : "FAIL");
        console.log("Meta.splitter:      ", meta.splitter() == splitterAddr ? "OK" : "FAIL");
        console.log("Meta.vToken:        ", meta.vToken() == vTokenAddr ? "OK" : "FAIL");
        console.log("Splitter.BRIBES:    ", splitter.BRIBES() == bribesAddr ? "OK" : "FAIL");
        console.log("Splitter.voteLib:   ", address(splitter.voteLib()) == voteLibAddr ? "OK" : "FAIL");
        
        // VToken config
        console.log("\n=== VTOKEN CONFIG ===");
        (uint256 maxPools, uint256 bits, uint256 slots, uint256 maxW, , ) = vToken.storageConfig();
        console.log("maxPools:    ", maxPools, maxPools > 0 ? "OK" : "FAIL");
        console.log("bitsPerPool: ", bits);
        console.log("poolsPerSlot:", slots);
        console.log("maxWeight:   ", maxW);
        
        // META staking status
        console.log("\n=== META STAKING STATUS ===");
        console.log("LP Pool:", meta.lpPool());
        console.log("Splitter whitelisted:", meta.isWhitelistedVEPool(splitterAddr) ? "YES" : "NO");
        console.log("Splitter gauge:", meta.poolLPGauge(splitterAddr));
        
        // Ownership
        console.log("\n=== OWNERSHIP ===");
        console.log("VToken:  ", vToken.owner() == msig ? "MSIG" : "WRONG");
        console.log("CToken:  ", cToken.owner() == msig ? "MSIG" : "WRONG");
        console.log("RToken:  ", rToken.owner() == msig ? "MSIG" : "WRONG");
        console.log("Splitter:", splitter.owner() == msig ? "MSIG" : "WRONG");
        
        // Status
        bool allOK = maxPools > 0 
            && vToken.liquidation() == liquidationAddr 
            && cToken.liquidation() == liquidationAddr
            && address(splitter.voteLib()) == voteLibAddr;
            
        console.log("\n============================================================");
        if (allOK) {
            console.log("STATUS: ALL CHECKS PASSED");
        } else {
            console.log("STATUS: ISSUES FOUND - CHECK ABOVE");
        }
        console.log("============================================================\n");
    }
}
