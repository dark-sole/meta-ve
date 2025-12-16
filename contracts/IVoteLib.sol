// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title IVoteLib
 * @notice Interface for VoteLib multi-NFT vote distribution
 * @dev Add this to Interfaces.sol
 */
interface IVoteLib {
    
    // ═══════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Vote instruction for a single NFT
     * @dev Contains everything needed for one voter.vote() call
     */
    struct NFTVote {
        /// @dev Pool addresses to vote for
        address[] pools;
        
        /// @dev Corresponding vote weights
        uint256[] weights;
        
        /// @dev This NFT's % of total voting power (basis points, 10000 = 100%)
        uint256 nftWeightBps;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error LengthMismatch();
    error NoVotes();
    error ZeroTotalWeight();
    
    // ═══════════════════════════════════════════════════════════════
    // MAIN FUNCTION
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Distribute votes across multiple NFTs
     * @dev Pure function - calculates distribution without state changes
     * @param pools All pool addresses (should be sorted descending by weight)
     * @param weights Corresponding vote weights
     * @return nftVotes Array of vote instructions, one per NFT needed
     */
    function distributeVotes(
        address[] memory pools,
        uint256[] memory weights
    ) external pure returns (NFTVote[] memory nftVotes);
    
    // ═══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculate how many NFTs needed for given pool count
     * @param numPools Number of pools to vote for
     * @return Number of NFTs required
     */
    function calculateNFTsNeeded(uint256 numPools) external pure returns (uint256);
    
    /**
     * @notice Preview distribution without executing
     * @param numPools Number of pools
     * @return poolsPerNFT Array showing pool count per NFT
     */
    function previewDistribution(uint256 numPools) external pure returns (uint256[] memory poolsPerNFT);
    
    /**
     * @notice Get version info
     */
    function version() external pure returns (string memory);
}
