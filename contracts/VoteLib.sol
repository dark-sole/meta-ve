// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title VoteLib
 * @notice Distributes votes across multiple NFTs when >30 pools voted
 * @dev Pure calculation contract - no state, external calls only
 * 
 * Purpose:
 *   Aerodrome limits each NFT to 30 pools maximum
 *   When users vote for >30 pools, votes must be split across multiple NFTs
 * 
 * Algorithm:
 *   1. Calculate numNFTs = ceil(numPools / 30)
 *   2. Sort pools by weight (descending)
 *   3. Distribute top pools across NFTs
 *   4. Calculate each NFT's % of total voting power
 *   5. Normalize weights within each NFT
 * 
 * Example:
 *   100 pools voted → Need 4 NFTs
 *   NFT 1: Top 30 pools (90% of weight)
 *   NFT 2: Next 30 pools (7% of weight)
 *   NFT 3: Next 30 pools (2.5% of weight)
 *   NFT 4: Last 10 pools (0.5% of weight)
 */
contract VoteLib {
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    /// @dev Aerodrome's maximum pools per NFT
    uint256 public constant MAX_POOLS_PER_NFT = 30;
    
    /// @dev Basis points base (100%)
    uint256 public constant BPS_BASE = 10000;
    
    // ═══════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Vote instruction for a single NFT
     * @dev Each struct contains everything needed for one voter.vote() call
     */
    struct NFTVote {
        /// @dev Pool addresses to vote for
        address[] pools;
        
        /// @dev Corresponding vote weights
        uint256[] weights;
        
        /// @dev This NFT's % of total voting power (basis points)
        /// @dev Used by splitter to determine NFT weight when splitting
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
     * @dev Pure function - no state changes, gas efficient
     * @param pools All pool addresses (should be pre-sorted descending by weight)
     * @param weights Corresponding weights
     * @return nftVotes Array of vote instructions, one per NFT needed
     */
    function distributeVotes(
        address[] memory pools,
        uint256[] memory weights
    ) external pure returns (NFTVote[] memory nftVotes) {
        // Validate inputs
        if (pools.length == 0) revert NoVotes();
        if (pools.length != weights.length) revert LengthMismatch();
        
        uint256 numPools = pools.length;
        
        // Case 1: Single NFT sufficient (≤30 pools)
        if (numPools <= MAX_POOLS_PER_NFT) {
            nftVotes = new NFTVote[](1);
            nftVotes[0] = NFTVote({
                pools: pools,
                weights: weights,
                nftWeightBps: BPS_BASE  // 100%
            });
            return nftVotes;
        }
        
        // Case 2: Multiple NFTs needed (>30 pools)
        return _distributeMultiNFT(pools, weights, numPools);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // INTERNAL DISTRIBUTION LOGIC
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Distribute pools across multiple NFTs
     * @dev Called when numPools > 30
     * @param pools Pool addresses (sorted descending by weight)
     * @param weights Corresponding weights
     * @param numPools Total number of pools
     * @return nftVotes Array of NFT vote instructions
     */
    function _distributeMultiNFT(
        address[] memory pools,
        uint256[] memory weights,
        uint256 numPools
    ) internal pure returns (NFTVote[] memory nftVotes) {
        // Calculate number of NFTs needed
        // Examples: 31 pools = 2 NFTs, 60 pools = 2 NFTs, 61 pools = 3 NFTs
        uint256 numNFTs = (numPools + MAX_POOLS_PER_NFT - 1) / MAX_POOLS_PER_NFT;
        nftVotes = new NFTVote[](numNFTs);
        
        // Calculate total weight across all pools
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < numPools; i++) {
            totalWeight += weights[i];
        }
        
        if (totalWeight == 0) revert ZeroTotalWeight();
        
        // Distribute pools across NFTs
        uint256 poolIndex = 0;
        
        for (uint256 nftIndex = 0; nftIndex < numNFTs; nftIndex++) {
            // Determine how many pools this NFT gets
            uint256 remainingPools = numPools - poolIndex;
            uint256 poolsThisNFT = remainingPools > MAX_POOLS_PER_NFT 
                ? MAX_POOLS_PER_NFT 
                : remainingPools;
            
            // Allocate arrays for this NFT
            address[] memory nftPools = new address[](poolsThisNFT);
            uint256[] memory nftWeights = new uint256[](poolsThisNFT);
            uint256 nftTotalWeight = 0;
            
            // Fill this NFT's pools and weights
            for (uint256 i = 0; i < poolsThisNFT; i++) {
                nftPools[i] = pools[poolIndex];
                nftWeights[i] = weights[poolIndex];
                nftTotalWeight += weights[poolIndex];
                poolIndex++;
            }
            
            // Calculate this NFT's % of total voting power
            // Example: If this NFT has 900 weight out of 1000 total → 9000 bps (90%)
            uint256 nftWeightBps = (nftTotalWeight * BPS_BASE) / totalWeight;
            
            nftVotes[nftIndex] = NFTVote({
                pools: nftPools,
                weights: nftWeights,
                nftWeightBps: nftWeightBps
            });
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // VIEW / HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculate how many NFTs needed for given pool count
     * @param numPools Number of pools to vote for
     * @return Number of NFTs required
     */
    function calculateNFTsNeeded(uint256 numPools) external pure returns (uint256) {
        if (numPools == 0) return 0;
        return (numPools + MAX_POOLS_PER_NFT - 1) / MAX_POOLS_PER_NFT;
    }
    
    /**
     * @notice Preview distribution without executing
     * @dev Useful for frontend to show distribution before execution
     * @param numPools Number of pools
     * @return poolsPerNFT Array showing pool count per NFT
     */
    function previewDistribution(uint256 numPools) external pure returns (uint256[] memory poolsPerNFT) {
        if (numPools == 0) {
            return new uint256[](0);
        }
        
        uint256 numNFTs = (numPools + MAX_POOLS_PER_NFT - 1) / MAX_POOLS_PER_NFT;
        poolsPerNFT = new uint256[](numNFTs);
        
        uint256 remaining = numPools;
        for (uint256 i = 0; i < numNFTs; i++) {
            poolsPerNFT[i] = remaining > MAX_POOLS_PER_NFT ? MAX_POOLS_PER_NFT : remaining;
            remaining -= poolsPerNFT[i];
        }
    }
    
    /**
     * @notice Get version info
     */
    function version() external pure returns (string memory) {
        return "VoteLib v1.0.0 - Multi-NFT Vote Distribution";
    }
}
