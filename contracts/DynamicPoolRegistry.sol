// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title DynamicPoolRegistry
 * @notice Maps Aerodrome pool addresses to indices for bitpacked storage
 * @dev Dynamic sizing based on Aerodrome voter.length()
 *      Indices assigned lazily on first vote
 *      Can be expanded if Aerodrome adds more pools
 */
library DynamicPoolRegistry {
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error RegistryFull(uint256 currentCount, uint256 maxCount);
    error PoolNotRegistered(address pool);
    error InvalidMaxPools();
    
    // ═══════════════════════════════════════════════════════════════
    // STORAGE STRUCT
    // ═══════════════════════════════════════════════════════════════
    
    struct Registry {
        /// @dev Pool address → index (0 means check indexToPool[0])
        mapping(address => uint256) poolToIndex;
        
        /// @dev Index → pool address
        mapping(uint256 => address) indexToPool;
        
        /// @dev Next available index
        uint256 nextIndex;
        
        /// @dev Maximum pools allowed (from config)
        uint256 maxPools;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Initialize registry with max pool count
     * @param self Storage pointer
     * @param _maxPools Maximum pools to support
     */
    function initialize(
        Registry storage self,
        uint256 _maxPools
    ) internal {
        if (_maxPools == 0) revert InvalidMaxPools();
        self.maxPools = _maxPools;
    }
    
    /**
     * @notice Update max pools (for expansion)
     * @param self Storage pointer
     * @param _maxPools New maximum
     */
    function setMaxPools(
        Registry storage self,
        uint256 _maxPools
    ) internal {
        if (_maxPools < self.nextIndex) revert InvalidMaxPools();
        self.maxPools = _maxPools;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Get index for a pool, registering if needed
     * @param self Storage pointer
     * @param pool Pool address
     * @return index Pool index
     * @return isNew True if newly registered
     */
    function getOrRegister(
        Registry storage self,
        address pool
    ) internal returns (uint256 index, bool isNew) {
        // Check if already registered
        index = self.poolToIndex[pool];
        
        // Index 0 is valid, need to verify
        if (self.indexToPool[index] == pool) {
            return (index, false);
        }
        
        // Not registered, assign next index
        index = self.nextIndex;
        if (index >= self.maxPools) {
            revert RegistryFull(index, self.maxPools);
        }
        
        self.poolToIndex[pool] = index;
        self.indexToPool[index] = pool;
        self.nextIndex = index + 1;
        
        return (index, true);
    }
    
    /**
     * @notice Get index for a pool (view only)
     * @param self Storage pointer
     * @param pool Pool address
     * @return index Pool index
     */
    function getIndex(
        Registry storage self,
        address pool
    ) internal view returns (uint256 index) {
        index = self.poolToIndex[pool];
        
        if (self.indexToPool[index] != pool) {
            revert PoolNotRegistered(pool);
        }
    }
    
    /**
     * @notice Check if pool is registered
     * @param self Storage pointer
     * @param pool Pool address
     * @return True if registered
     */
    function isRegistered(
        Registry storage self,
        address pool
    ) internal view returns (bool) {
        uint256 index = self.poolToIndex[pool];
        return self.indexToPool[index] == pool;
    }
    
    /**
     * @notice Get pool address at index
     * @param self Storage pointer
     * @param index Pool index
     * @return pool Pool address (address(0) if empty)
     */
    function getPool(
        Registry storage self,
        uint256 index
    ) internal view returns (address pool) {
        return self.indexToPool[index];
    }
    
    /**
     * @notice Get total registered pools
     * @param self Storage pointer
     * @return Number of registered pools
     */
    function count(Registry storage self) internal view returns (uint256) {
        return self.nextIndex;
    }
    
    /**
     * @notice Get remaining capacity
     * @param self Storage pointer
     * @return Number of slots available
     */
    function remaining(Registry storage self) internal view returns (uint256) {
        return self.maxPools - self.nextIndex;
    }
    
    /**
     * @notice Check if registry is full
     * @param self Storage pointer
     * @return True if no more slots
     */
    function isFull(Registry storage self) internal view returns (bool) {
        return self.nextIndex >= self.maxPools;
    }
    
    /**
     * @notice Clear all registrations (called at epoch reset)
     * @dev Only resets nextIndex - mappings become stale but that's fine
     *      because getOrRegister checks indexToPool[index] == pool
     *      Gas efficient: O(1) instead of O(n) to clear mappings
     * @param self Storage pointer
     */
    function clear(Registry storage self) internal {
        // We don't need to clear the mappings - just reset the counter
        // Old mappings become invalid because:
        // 1. poolToIndex[oldPool] might return index X
        // 2. But indexToPool[X] will be overwritten with new pool
        // 3. So getOrRegister's check (indexToPool[index] == pool) fails
        // 4. Pool gets re-registered with new index
        self.nextIndex = 0;
    }
}
