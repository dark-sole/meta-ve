// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title Interfaces V4 (CORRECTED)
 * @notice Centralized interface definitions for VeAero Ecosystem V4
 * 
 * FIXES APPLIED:
 * - IMeta.getPoolInfo() now returns 4 values (added chainId)
 * - All IVeAeroSplitter functions that CToken needs are included
 */

// ═══════════════════════════════════════════════════════════════════════════
// PROTOCOL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title IVeAeroSplitter
 * @notice Interface for VeAeroSplitter V3.2 called by tokens
 */
interface IVeAeroSplitter {
    // Gauge voting (called by VToken)
    function recordGaugeVote(address user, address pool, uint256 amount) external;
    function recordPassiveVote(address user, uint256 amount) external;
    
    // Emissions voting (called by CToken)
    function recordEmissionsVote(address user, int8 choice, uint256 amount) external;
    
    // Liquidation (called by CToken and VToken)
    function recordCLock(address user, uint256 amount) external;
    function recordVConfirmation(address user, uint256 amount) external;
    
    // Timing (used by VToken and CToken for voting windows)
    function votingStartTime() external view returns (uint256);
    function votingEndTime() external view returns (uint256);
    function epochEndTime() external view returns (uint256);
    function currentEpoch() external view returns (uint256);
    
    // Liquidation phase
    function liquidationPhase() external view returns (uint8);
    
    // Total V locked for bribe snapshot
    function totalVLockedForVoting() external view returns (uint256);
    
    // Transfer settlement (called by CToken._update)
    // Settles sender's rewards to treasury, weighted checkpoint for receiver
    function onCTokenTransfer(address from, address to, uint256 amount) external;
}

/**
 * @title IVToken
 * @notice Interface for V-AERO token
 */
interface IVToken {
    // Minting/burning (called by VeAeroSplitter)
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    
    // ERC20 views
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    
    // Lock state
    function lockedAmount(address account) external view returns (uint256);
    function lockedUntil(address account) external view returns (uint256);
    
    // Voting (called by Meta for V-AERO voting)
    function vote(address pool, uint256 amount) external;
    function votePassive(uint256 amount) external;
}

/**
 * @title ICToken
 * @notice Interface for C-AERO token
 */
interface ICToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title IRToken
 * @notice Interface for R-AERO token (liquidation receipts)
 */
interface IRToken {
    function mint(address to, uint256 amount) external;
}

/**
 * @title IMeta
 * @notice Interface for META token
 */
interface IMeta {
    // V4: Fee receiving from VeAeroSplitter
    function receiveFees(uint256 amount) external;
    
    // Index updates (used by CToken)
    function needsIndexUpdate() external view returns (bool);
    function lastUpdateDay() external view returns (uint64);
    // Note: updateIndex() returns (uint64 processedDays, bool complete)
    function updateIndex() external returns (uint64, bool);
    
    // VE Pool claims (used by CToken)
    function claimForVEPool() external returns (uint256);
    
    // FIXED: Added chainId to match Meta.sol implementation
    function getPoolInfo(address vePool) external view returns (
        bool whitelisted,
        uint256 votes,
        uint256 pendingRewards,
        uint256 chainId  // ← ADDED: Was missing in original
    );
    
    // Staking
    function lockAndVote(uint256 amount, address vePool) external;
    function initiateUnlock() external;
    function completeUnlock() external;
    
    // LP gauge
    function pushToLPGauge() external;
    function pushVote() external;
    
    // Views
    function getCurrentS() external view returns (uint256);
    function totalLockedVotes() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════
// AERODROME EXTERNAL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title IVotingEscrow
 * @notice Interface for Aerodrome VotingEscrow (veAERO)
 */
interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint256 end;
        bool isPermanent;
    }
    
    function ownerOf(uint256 tokenId) external view returns (address);
    function voted(uint256 tokenId) external view returns (bool);
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function unlockPermanent(uint256 tokenId) external;
    function merge(uint256 from, uint256 to) external;
    function depositFor(uint256 tokenId, uint256 amount) external;
}

/**
 * @title IVoter
 * @notice Interface for Aerodrome Voter
 */
interface IVoter {
    function vote(uint256 tokenId, address[] calldata pools, uint256[] calldata weights) external;
    function claimFees(address[] calldata fees, address[][] calldata tokens, uint256 tokenId) external;
    function claimBribes(address[] calldata bribes, address[][] calldata tokens, uint256 tokenId) external;
    function gauges(address pool) external view returns (address);
    function isGauge(address gauge) external view returns (bool);
    function isAlive(address gauge) external view returns (bool);
    function length() external view returns (uint256);
}

/**
 * @title IEpochGovernor
 * @notice Interface for Aerodrome EpochGovernor
 */
interface IEpochGovernor {
    function castVote(uint256 proposalId, uint8 support) external;
}

/**
 * @title IGauge
 * @notice Interface for Aerodrome Gauge (LP staking)
 */
interface IGauge {
    function notifyRewardAmount(address token, uint256 amount) external;
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address account) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSS-CHAIN INTERFACES (V7)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title IL1ProofVerifier
 * @notice Interface for L1 state proof verification
 */
interface IL1ProofVerifier {
    function verifyRemoteFees(
        uint256 chainId,
        uint256 epoch,
        uint256 totalFees,
        bytes calldata proof
    ) external view returns (bool);
    
    function verifyRemoteBurn(
        uint256 chainId,
        address user,
        uint256 burnedAmount,
        bytes calldata proof
    ) external view returns (bool);
}
