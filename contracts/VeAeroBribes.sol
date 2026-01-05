// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces.sol";

/**
 * @title VeAeroBribes V.BETA.1
 * @notice Handles bribe snapshot and claim logic for VeAeroSplitter
 * @dev Separated from VeAeroSplitter to meet EIP-170 size limit
 *      
 * Flow:
 *      1. splitter.collectBribes() - claims from Aerodrome, tokens stay in Splitter
 *      2. bribes.snapshotForBribes() - user records vote power after voting ends
 *      3. bribes.claimBribes() - user claims pro-rata share via splitter.pullBribeToken()
 *      4. bribes.sweepUnclaimedBribes() - sweep remaining to treasury
 *      
 * Security:
 *      - Reads whitelist from Splitter (only Splitter can whitelist)
 *      - Pull requests go through Splitter's pullBribeToken() which validates
 *      - No direct token custody - tokens always in Splitter until claimed
 */
contract VeAeroBribes {
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant CLAIM_WINDOW_BUFFER = 1 hours;
    
    // ═══════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════
    
    IVeAeroSplitterBribes public immutable SPLITTER;
    IVToken public immutable V_TOKEN;
    address public immutable TOKENISYS;
    address public immutable META;
    
    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════
    
    // Snapshot state
    mapping(address => uint256) public snapshotVotePower;
    mapping(address => uint256) public snapshotEpoch;
    uint256 public epochSnapshotTotal;
    uint256 public epochSnapshotEpoch;
    
    // Claim state
    mapping(address => uint256) public bribeRatioPerV;
    mapping(address => uint256) public bribeTokenEpoch;
    mapping(address => uint256) public claimedBribesEpoch;
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event BribeSnapshot(address indexed user, uint256 votePower, uint256 epoch);
    event EpochSnapshotSet(uint256 totalPower, uint256 epoch);
    event BribesClaimed(address indexed user, address[] tokens, uint256[] amounts);
    event BribeTokenRegistered(address indexed token, uint256 ratio, uint256 epoch);
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error SnapshotWindowClosed();
    error AlreadySnapshotted();
    error NoLockedBalance();
    error NoSnapshotLastEpoch();
    error AlreadyClaimedBribes();
    error LiquidationInProgress();
    error ZeroAddress();
    error VoteNotExecuted();
    error ClaimWindowClosed();
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor(
        address _splitter,
        address _vToken,
        address _tokenisys,
        address _meta
    ) {
        if (_splitter == address(0)) revert ZeroAddress();
        if (_vToken == address(0)) revert ZeroAddress();
        if (_tokenisys == address(0)) revert ZeroAddress();
        if (_meta == address(0)) revert ZeroAddress();
        
        SPLITTER = IVeAeroSplitterBribes(_splitter);
        V_TOKEN = IVToken(_vToken);
        TOKENISYS = _tokenisys;
        META = _meta;
    }
        
    // ═══════════════════════════════════════════════════════════════
    // SNAPSHOT
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Snapshot vote power for bribe claims
     * @dev Must be called after voting ends but before epoch ends(2 hour slot)
     */
    function snapshotForBribes() external {
        uint256 currentEpoch = SPLITTER.currentEpoch();
        uint256 votingEndTime = SPLITTER.votingEndTime();
        uint256 epochEndTime = SPLITTER.epochEndTime();
        
        // Check not in liquidation
        if (SPLITTER.isLiquidationActive()) revert LiquidationInProgress();

        // Must wait for executeGaugeVote() to be called first
        if (!SPLITTER.voteExecutedThisEpoch()) revert VoteNotExecuted();
        
        // Window: after voting ends, before epoch ends
        if (block.timestamp <= votingEndTime) revert SnapshotWindowClosed();
        if (block.timestamp >= epochEndTime) revert SnapshotWindowClosed();
        
        // Check user has locked balance
        uint256 locked = V_TOKEN.lockedAmount(msg.sender);
        if (locked == 0) revert NoLockedBalance();
        
        // Check not already snapshotted this epoch
        if (snapshotEpoch[msg.sender] == currentEpoch) revert AlreadySnapshotted();
        
        // Set epoch snapshot total on first snapshot of epoch
        if (epochSnapshotEpoch != currentEpoch) {
            uint256 totallocked = SPLITTER.cachedTotalVLockedForVoting();
            uint256 metalocked = V_TOKEN.currentLockedAmount(META) / PRECISION;
            epochSnapshotTotal = totallocked - metalocked;
            epochSnapshotEpoch = currentEpoch;
            emit EpochSnapshotSet(epochSnapshotTotal, currentEpoch);
        }
        
        // Record user's vote power (whole tokens)
        uint256 lockedWholeTokens = locked / 1e18;
        snapshotVotePower[msg.sender] = lockedWholeTokens;
        snapshotEpoch[msg.sender] = currentEpoch;
        
        emit BribeSnapshot(msg.sender, lockedWholeTokens, currentEpoch);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CLAIM
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Claim bribe tokens from previous epoch
     * @param tokens Array of bribe token addresses to claim
     */
    function claimBribes(address[] calldata tokens) external {
        uint256 currentEpoch = SPLITTER.currentEpoch();
        uint256 epochEndTime = SPLITTER.epochEndTime();

        // Cannot claim in last hour of epoch (Tokenisys sweep window)
        if (block.timestamp > epochEndTime - CLAIM_WINDOW_BUFFER) revert ClaimWindowClosed();
    
        // Must have snapshotted last epoch
        if (snapshotEpoch[msg.sender] != currentEpoch - 1) revert NoSnapshotLastEpoch();
        
        // Cannot claim twice
        if (claimedBribesEpoch[msg.sender] == currentEpoch) revert AlreadyClaimedBribes();
        
        claimedBribesEpoch[msg.sender] = currentEpoch;
        
        uint256 userPower = snapshotVotePower[msg.sender];
        uint256 totalPower = epochSnapshotTotal;
        
        uint256[] memory amounts = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            
            // Validate whitelist via Splitter
            if (!SPLITTER.isWhitelistedBribe(token)) continue;
            if (SPLITTER.bribeWhitelistEpoch(token) != currentEpoch) continue;
            
            // First claimer sets ratio
            if (bribeTokenEpoch[token] != currentEpoch) {
                uint256 balance = IERC20(token).balanceOf(address(SPLITTER));
                if (balance > 0 && totalPower > 0) {
                    bribeRatioPerV[token] = (balance * PRECISION) / totalPower;
                    bribeTokenEpoch[token] = currentEpoch;
                    emit BribeTokenRegistered(token, bribeRatioPerV[token], currentEpoch);
                }
            }
            
            // Calculate user's share
            uint256 owed = (userPower * bribeRatioPerV[token]) / PRECISION;
            amounts[i] = owed;
            
            // Pull from Splitter directly to user
            if (owed > 0) {
                SPLITTER.pullBribeToken(token, msg.sender, owed);
            }
        }
        
        emit BribesClaimed(msg.sender, tokens, amounts);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Check if user can snapshot this epoch
     */
    function canSnapshot(address user) external view returns (bool) {
        uint256 currentEpoch = SPLITTER.currentEpoch();
        uint256 votingEndTime = SPLITTER.votingEndTime();
        uint256 epochEndTime = SPLITTER.epochEndTime();
        
        return block.timestamp > votingEndTime && 
               block.timestamp < epochEndTime &&
               snapshotEpoch[user] != currentEpoch &&
               V_TOKEN.currentLockedAmount(user) > 0;
    }
    
    /**
     * @notice Get user's claimable bribe amount for a token
     * @param user Address to check
     * @param token Bribe token address
     */
    function pendingBribes(address user, address token) external view returns (uint256) {
        uint256 currentEpoch = SPLITTER.currentEpoch();
        uint256 epochEndTime = SPLITTER.epochEndTime();

        // Past claim deadline
        if (block.timestamp > epochEndTime - CLAIM_WINDOW_BUFFER) return 0;
        
        // Must have snapshotted last epoch
        if (snapshotEpoch[user] != currentEpoch - 1) return 0;
        
        // Must not have claimed
        if (claimedBribesEpoch[user] == currentEpoch) return 0;
        
        // Must be whitelisted
        if (!SPLITTER.isWhitelistedBribe(token)) return 0;
        if (SPLITTER.bribeWhitelistEpoch(token) != currentEpoch) return 0;
        
        uint256 userPower = snapshotVotePower[user];
        
        // If ratio not set yet, calculate it
        uint256 ratio = bribeRatioPerV[token];
        if (bribeTokenEpoch[token] != currentEpoch) {
            uint256 balance = IERC20(token).balanceOf(address(SPLITTER));
            uint256 totalPower = epochSnapshotTotal;
            if (balance > 0 && totalPower > 0) {
                ratio = (balance * PRECISION) / totalPower;
            }
        }
        
        return (userPower * ratio) / PRECISION;
    }
}

// ═══════════════════════════════════════════════════════════════
// INTERFACES
// ═══════════════════════════════════════════════════════════════

interface IVeAeroSplitterBribes {
    function currentEpoch() external view returns (uint256);
    function votingEndTime() external view returns (uint256);
    function epochEndTime() external view returns (uint256);
    function totalVLockedForVoting() external view returns (uint256);
    function cachedTotalVLockedForVoting() external view returns (uint256);
    function voteExecutedThisEpoch() external view returns (bool);
    function isWhitelistedBribe(address token) external view returns (bool);
    function bribeWhitelistEpoch(address token) external view returns (uint256);
    function isLiquidationActive() external view returns (bool);
    function pullBribeToken(address token, address to, uint256 amount) external;
}

