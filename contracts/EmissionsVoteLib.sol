// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EmissionsVoteLib V.BETA.1
 * @notice Tracks C-AERO holder votes on Aerodrome emissions (increase/hold/decrease)
 * @dev Extracted from VeAeroSplitter to reduce contract size
 * 
 * Flow:
 *   1. CToken.voteEmissions() validates timing with Splitter
 *   2. CToken calls this lib's recordVote()
 *   3. Splitter.executeEmissionsVote() calls getWinningChoice()
 *   4. Splitter._resetEpoch() calls resetEpoch()
 */
contract EmissionsVoteLib is Ownable {
    
    // ═══════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Total votes for decrease (-1)
    uint256 public emissionsDecreaseTotal;
    
    /// @notice Total votes for hold (0)
    uint256 public emissionsHoldTotal;
    
    /// @notice Total votes for increase (+1)
    uint256 public emissionsIncreaseTotal;
    
    /// @notice Current epoch (for event logging)
    uint256 public currentEpoch;
    
    /// @notice Authorized CToken address
    address public cToken;
    
    /// @notice Authorized Splitter address
    address public splitter;
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error Unauthorized();
    error ZeroAddress();
    error AlreadySet();
    
    // ═══════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event EmissionsVoteRecorded(address indexed user, uint256 indexed epoch, int8 choice, uint256 amount);
    event EmissionsVoteReset(uint256 indexed epoch);
    event CTokenSet(address indexed cToken);
    event SplitterSet(address indexed splitter);
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    constructor() Ownable(msg.sender) {
        currentEpoch = 1;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // SETUP (Owner only, one-time)
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Set CToken address (one-time)
     * @param _cToken CToken contract address
     */
    function setCToken(address _cToken) external onlyOwner {
        if (_cToken == address(0)) revert ZeroAddress();
        if (cToken != address(0)) revert AlreadySet();
        cToken = _cToken;
        emit CTokenSet(_cToken);
    }
    
    /**
     * @notice Set Splitter address (one-time)
     * @param _splitter VeAeroSplitter contract address
     */
    function setSplitter(address _splitter) external onlyOwner {
        if (_splitter == address(0)) revert ZeroAddress();
        if (splitter != address(0)) revert AlreadySet();
        splitter = _splitter;
        emit SplitterSet(_splitter);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Record an emissions vote
     * @dev Called by CToken.voteEmissions() - CToken validates timing
     * @param user Voter address (for event)
     * @param choice -1 (decrease), 0 (hold), +1 (increase)
     * @param amount Vote weight in whole tokens
     */
    function recordVote(address user, int8 choice, uint256 amount) external {
        if (msg.sender != cToken) revert Unauthorized();
        
        if (choice == -1) {
            emissionsDecreaseTotal += amount;
        } else if (choice == 0) {
            emissionsHoldTotal += amount;
        } else {
            emissionsIncreaseTotal += amount;
        }
        
        emit EmissionsVoteRecorded(user, currentEpoch, choice, amount);
    }
    
    /**
     * @notice Reset vote totals for new epoch
     * @dev Called by Splitter._resetEpoch()
     * @param newEpoch The new epoch number
     */
    function resetEpoch(uint256 newEpoch) external {
        if (msg.sender != splitter) revert Unauthorized();
        
        emissionsDecreaseTotal = 0;
        emissionsHoldTotal = 0;
        emissionsIncreaseTotal = 0;
        currentEpoch = newEpoch;
        
        emit EmissionsVoteReset(newEpoch);
    }
    
    /**
     * @notice Get the winning choice for execution
     * @dev Called by Splitter.executeEmissionsVote()
     * @return support 0=Against(decrease), 1=Abstain(hold), 2=For(increase)
     * @return maxVotes The winning vote total
     */
    function getWinningChoice() external view returns (uint8 support, uint256 maxVotes) {
        maxVotes = emissionsHoldTotal;
        support = 1; // Hold/Abstain
        
        if (emissionsDecreaseTotal > maxVotes) {
            maxVotes = emissionsDecreaseTotal;
            support = 0; // Against
        }
        if (emissionsIncreaseTotal > maxVotes) {
            maxVotes = emissionsIncreaseTotal;
            support = 2; // For
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Get all vote totals
     * @return decrease Total decrease votes
     * @return hold Total hold votes  
     * @return increase Total increase votes
     */
    function getTotals() external view returns (
        uint256 decrease,
        uint256 hold,
        uint256 increase
    ) {
        return (emissionsDecreaseTotal, emissionsHoldTotal, emissionsIncreaseTotal);
    }
}
