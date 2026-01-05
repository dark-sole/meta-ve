// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VeAeroLiquidation V.BETA.1
 * @notice Tracks liquidation votes and phase transitions for VeAeroSplitter
 * @dev Separated from VeAeroSplitter V5 to meet EIP-170 size limit
 *      
 * Liquidation Process:
 *      Phase 1 (CLock): C-AERO holders lock tokens → 25% triggers CVote
 *      Phase 2 (CVote): 90 day voting period → 75% C locked required
 *      Phase 3 (VConfirm): V-AERO holders confirm → 50% V locked required (1 epoch)
 *      Phase 4 (Approved): Liquidation approved → R-Token claims in VeAeroSplitter
 *      Phase 5 (Closed): All claimed → NFT withdrawal in VeAeroSplitter
 *      
 * This contract:
 *      - Receives C-AERO and V-AERO locks from tokens
 *      - Tracks phase transitions based on thresholds
 *      - Provides isLiquidationApproved() for VeAeroSplitter modifier
 *      - Returns locked tokens on failed liquidation
 *      
 * VeAeroSplitter handles:
 *      - R-Token minting (claimRTokens)
 *      - NFT withdrawal (withdrawAllNFTs)
 *      - Unclaimed receipt sweeping
 */
contract VeAeroLiquidation {
    using SafeERC20 for IERC20;
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    uint256 public constant C_LOCK_THRESHOLD_BPS = 2500;    // 25% to start CVote
    uint256 public constant C_VOTE_THRESHOLD_BPS = 7500;    // 75% to pass CVote
    uint256 public constant V_CONFIRM_THRESHOLD_BPS = 5000; // 50% to confirm
    uint256 public constant C_VOTE_DURATION = 90 days;
    
    // ═══════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════
    
    IERC20 public immutable C_TOKEN;
    IERC20 public immutable V_TOKEN;
    address public immutable SPLITTER;
    
    // ═══════════════════════════════════════════════════════════════
    // ENUMS
    // ═══════════════════════════════════════════════════════════════
    
    enum LiquidationPhase { Normal, CLock, CVote, VConfirm, Approved, Closed }
    
    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════
    
    LiquidationPhase public liquidationPhase;
    uint256 public totalCLocked;
    uint256 public totalVLocked;
    uint256 public cVoteStartTime;
    uint256 public vConfirmEpoch;
    uint256 public liquidationApprovedTime;
    
    mapping(address => uint256) public cLockedForLiquidation;
    mapping(address => uint256) public vLockedForLiquidation;
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event LiquidationPhaseChanged(LiquidationPhase oldPhase, LiquidationPhase newPhase);
    event CLocked(address indexed user, uint256 amount);
    event VLocked(address indexed user, uint256 amount);
    event FailedLiquidationWithdrawn(address indexed user, uint256 cAmount, uint256 vAmount);
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error OnlyCToken();
    error OnlyVToken();
    error OnlySplitter();
    error InvalidLiquidationPhase();
    error CVoteNotExpired();
    error VConfirmEpochNotEnded();
    error NothingToWithdraw();
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor(
        address _cToken,
        address _vToken,
        address _splitter
    ) {
        require(_cToken != address(0), "Zero cToken");
        require(_vToken != address(0), "Zero vToken");
        require(_splitter != address(0), "Zero splitter");
        C_TOKEN = IERC20(_cToken);
        V_TOKEN = IERC20(_vToken);
        SPLITTER = _splitter;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // LOCK RECORDING (Called by CToken/VToken)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Record C-AERO locked for liquidation vote
     * @dev Called by CToken.lockForLiquidation()
     *      Advances phase: Normal → CLock (first lock)
     *      Advances phase: CLock → CVote (25% threshold)
     * @param user Address locking tokens
     * @param amount Amount being locked
     */
    function recordCLock(address user, uint256 amount) external {
        if (msg.sender != address(C_TOKEN)) revert OnlyCToken();
        if (liquidationPhase != LiquidationPhase.Normal &&
            liquidationPhase != LiquidationPhase.CLock &&
            liquidationPhase != LiquidationPhase.CVote) {
            revert InvalidLiquidationPhase();
        }
        
        cLockedForLiquidation[user] += amount;
        totalCLocked += amount;
        
        // First lock starts CLock phase
        if (liquidationPhase == LiquidationPhase.Normal) {
            emit LiquidationPhaseChanged(LiquidationPhase.Normal, LiquidationPhase.CLock);
            liquidationPhase = LiquidationPhase.CLock;
        }
        
        // Check for 25% threshold to advance to CVote
        uint256 cSupply = C_TOKEN.totalSupply();
        uint256 threshold = (cSupply * C_LOCK_THRESHOLD_BPS) / 10000;
        if (liquidationPhase == LiquidationPhase.CLock && totalCLocked >= threshold) {
            emit LiquidationPhaseChanged(LiquidationPhase.CLock, LiquidationPhase.CVote);
            liquidationPhase = LiquidationPhase.CVote;
            cVoteStartTime = block.timestamp;
        }
        
        emit CLocked(user, amount);
    }
    
    /**
     * @notice Record V-AERO locked to confirm liquidation
     * @dev Called by VToken.lockForLiquidation()
     *      Only allowed during VConfirm phase
     * @param user Address locking tokens
     * @param amount Amount being locked
     */
    function recordVConfirmation(address user, uint256 amount) external {
        if (msg.sender != address(V_TOKEN)) revert OnlyVToken();
        if (liquidationPhase != LiquidationPhase.VConfirm) revert InvalidLiquidationPhase();
        
        vLockedForLiquidation[user] += amount;
        totalVLocked += amount;
        
        emit VLocked(user, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE RESOLUTION (Anyone can call)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Resolve CVote phase after 90 days
     * @dev Success (75% locked): Advance to VConfirm
     *      Failure: Return to Normal (tokens withdrawable)
     * @param currentEpoch Current epoch from VeAeroSplitter
     */
    function resolveCVote(uint256 currentEpoch) external {
        if (liquidationPhase != LiquidationPhase.CVote) revert InvalidLiquidationPhase();
        if (block.timestamp < cVoteStartTime + C_VOTE_DURATION) revert CVoteNotExpired();
        
        uint256 cSupply = C_TOKEN.totalSupply();
        uint256 threshold = (cSupply * C_VOTE_THRESHOLD_BPS) / 10000;
        
        if (totalCLocked >= threshold) {
            // Success: advance to VConfirm at next epoch
            emit LiquidationPhaseChanged(LiquidationPhase.CVote, LiquidationPhase.VConfirm);
            liquidationPhase = LiquidationPhase.VConfirm;
            vConfirmEpoch = currentEpoch + 1;
        } else {
            // Failed: back to Normal, C withdrawable
            emit LiquidationPhaseChanged(LiquidationPhase.CVote, LiquidationPhase.Normal);
            liquidationPhase = LiquidationPhase.Normal;
            cVoteStartTime = 0;
        }
    }
    
    /**
     * @notice Resolve VConfirm phase after epoch ends
     * @dev Success (50% V locked): Advance to Approved
     *      Failure: Return to Normal (tokens withdrawable)
     * @param currentEpoch Current epoch from VeAeroSplitter
     */
    function resolveVConfirm(uint256 currentEpoch) external {
        if (liquidationPhase != LiquidationPhase.VConfirm) revert InvalidLiquidationPhase();
        if (currentEpoch <= vConfirmEpoch) revert VConfirmEpochNotEnded();
        
        uint256 vSupply = V_TOKEN.totalSupply();
        uint256 threshold = (vSupply * V_CONFIRM_THRESHOLD_BPS) / 10000;
        
        if (totalVLocked >= threshold) {
            // Success: liquidation approved
            emit LiquidationPhaseChanged(LiquidationPhase.VConfirm, LiquidationPhase.Approved);
            liquidationPhase = LiquidationPhase.Approved;
            liquidationApprovedTime = block.timestamp;
        } else {
            // Failed: back to Normal, C and V withdrawable
            emit LiquidationPhaseChanged(LiquidationPhase.VConfirm, LiquidationPhase.Normal);
            liquidationPhase = LiquidationPhase.Normal;
            cVoteStartTime = 0;
            vConfirmEpoch = 0;
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // WITHDRAWAL (After failed liquidation)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Withdraw tokens after failed liquidation
     * @dev Only available when phase has returned to Normal
     */
    function withdrawFailedLiquidation() external {
        if (liquidationPhase != LiquidationPhase.Normal) revert InvalidLiquidationPhase();
        
        uint256 cAmount = cLockedForLiquidation[msg.sender];
        uint256 vAmount = vLockedForLiquidation[msg.sender];
        
        if (cAmount == 0 && vAmount == 0) revert NothingToWithdraw();
        
        // ═══════════════════════════════════════════════════════════════════
        // EFFECTS - All state updates before any external calls
        // ═══════════════════════════════════════════════════════════════════
        cLockedForLiquidation[msg.sender] = 0;
        vLockedForLiquidation[msg.sender] = 0;
        
        if (cAmount > 0) {
            totalCLocked -= cAmount;
        }
        if (vAmount > 0) {
            totalVLocked -= vAmount;
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // INTERACTIONS - All external calls after state is finalized
        // ═══════════════════════════════════════════════════════════════════
        if (cAmount > 0) {
            C_TOKEN.safeTransfer(msg.sender, cAmount);
        }
        if (vAmount > 0) {
            V_TOKEN.safeTransfer(msg.sender, vAmount);
        }
        
        emit FailedLiquidationWithdrawn(msg.sender, cAmount, vAmount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // SPLITTER CALLBACKS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Mark liquidation as closed (called by Splitter after R-Token sweep)
     */
    function markClosed() external {
        if (msg.sender != SPLITTER) revert OnlySplitter();
        if (liquidationPhase != LiquidationPhase.Approved) revert InvalidLiquidationPhase();
        
        emit LiquidationPhaseChanged(LiquidationPhase.Approved, LiquidationPhase.Closed);
        liquidationPhase = LiquidationPhase.Closed;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Check if liquidation has been approved
     * @dev Used by VeAeroSplitter.notInLiquidation modifier
     */
    function isLiquidationApproved() external view returns (bool) {
        return liquidationPhase == LiquidationPhase.Approved || 
               liquidationPhase == LiquidationPhase.Closed;
    }
    
    /**
     * @notice Get timestamp when liquidation was approved
     * @dev Used by VeAeroSplitter for R-Token claim window
     */
    function getLiquidationApprovedTime() external view returns (uint256) {
        return liquidationApprovedTime;
    }
    
    /**
     * @notice Get user's locked C-AERO amount
     * @dev Used by VeAeroSplitter for R-Token claim amount
     */
    function getUserCLocked(address user) external view returns (uint256) {
        return cLockedForLiquidation[user];
    }
    
    /**
     * @notice Get total C-AERO locked
     * @dev Used by VeAeroSplitter for R-Token sweep calculation
     */
    function getTotalCLocked() external view returns (uint256) {
        return totalCLocked;
    }
    
    /**
     * @notice Get comprehensive liquidation status
     */
    function getLiquidationStatus(
        uint256 currentEpoch,
        uint256 epochEndTime
    ) external view returns (
        LiquidationPhase phase,
        uint256 cLockedPercent,
        uint256 vLockedPercent,
        uint256 cTargetPercent,
        uint256 vTargetPercent,
        uint256 timeRemaining
    ) {
        phase = liquidationPhase;
        
        uint256 cSupply = C_TOKEN.totalSupply();
        uint256 vSupply = V_TOKEN.totalSupply();
        
        cLockedPercent = cSupply > 0 ? (totalCLocked * 10000) / cSupply : 0;
        vLockedPercent = vSupply > 0 ? (totalVLocked * 10000) / vSupply : 0;
        
        if (phase == LiquidationPhase.Normal || phase == LiquidationPhase.CLock) {
            cTargetPercent = C_LOCK_THRESHOLD_BPS;
            vTargetPercent = 0;
            timeRemaining = 0;
        } else if (phase == LiquidationPhase.CVote) {
            cTargetPercent = C_VOTE_THRESHOLD_BPS;
            vTargetPercent = 0;
            uint256 endTime = cVoteStartTime + C_VOTE_DURATION;
            timeRemaining = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
        } else if (phase == LiquidationPhase.VConfirm) {
            cTargetPercent = C_VOTE_THRESHOLD_BPS;
            vTargetPercent = V_CONFIRM_THRESHOLD_BPS;
            timeRemaining = currentEpoch > vConfirmEpoch ? 0 : epochEndTime - block.timestamp;
        } else {
            cTargetPercent = 0;
            vTargetPercent = 0;
            timeRemaining = 0;
        }
    }
    
    /**
     * @notice Get days remaining in CVote phase
     */
    function daysRemainingInCVote() external view returns (uint256) {
        if (liquidationPhase != LiquidationPhase.CVote) return 0;
        
        uint256 endTime = cVoteStartTime + C_VOTE_DURATION;
        if (block.timestamp >= endTime) return 0;
        
        return (endTime - block.timestamp) / 1 days;
    }
}
