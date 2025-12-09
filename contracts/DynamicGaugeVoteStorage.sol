// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title DynamicGaugeVoteStorage
 * @notice Bitpacked storage for gauge voting weights with dynamic configuration
 * @dev Adapts to:
 *      - Number of pools from Aerodrome voter.length()
 *      - Token supply from AERO.totalSupply()
 * 
 * Configuration calculated at deployment:
 *      bitsPerPool = ceil(log2(totalSupply)) + 1 (safety margin)
 *      poolsPerSlot = 256 / bitsPerPool
 *      numSlots = ceil(maxPools / poolsPerSlot)
 * 
 * Examples:
 *      100M supply, 200 pools: 28 bits, 9/slot, 23 slots
 *      100M supply, 400 pools: 28 bits, 9/slot, 45 slots
 *      500M supply, 400 pools: 30 bits, 8/slot, 50 slots
 *      1B supply, 500 pools:   31 bits, 8/slot, 63 slots
 */
library DynamicGaugeVoteStorage {
    
    // ═══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    /// @dev Absolute maximum slots (hard safety cap to prevent gas bombs)
    uint256 public constant ABSOLUTE_MAX_SLOTS = 500;
    
    /// @dev Default maximum slots (100 slots = ~400 pools, sufficient for active Aerodrome gauges)
    /// Note: We use sequential pool indices via registry, not Aerodrome's gauge indices
    uint256 public constant DEFAULT_MAX_SLOTS = 100;
    
    /// @dev Minimum bits per pool (sanity check)
    uint256 internal constant MIN_BITS_PER_POOL = 20;
    
    /// @dev Maximum bits per pool (sanity check)
    uint256 internal constant MAX_BITS_PER_POOL = 64;
    
    // ═══════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════
    
    error PoolIndexOutOfBounds(uint256 index, uint256 maxIndex);
    error WeightOverflow(uint256 weight, uint256 maxWeight);
    error ConfigurationInvalid();
    error TooManySlots(uint256 required, uint256 max);
    
    // ═══════════════════════════════════════════════════════════════
    // STORAGE STRUCTS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Configuration for bitpacking
     * @dev Set once at initialization, can be updated if Aerodrome grows
     */
    struct Config {
        uint32 maxPools;       // Maximum pool index + 1
        uint32 bitsPerPool;    // Bits allocated per pool weight
        uint32 poolsPerSlot;   // How many pools fit in 256 bits
        uint32 numSlots;       // Total storage slots needed
        uint256 mask;          // Bitmask for extracting weight
        uint256 maxWeight;     // Maximum weight value (2^bits - 1)
    }
    
    /**
     * @notice Packed weight storage
     * @dev Dynamic array sized based on config
     */
    struct PackedWeights {
        uint256[] slots;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculate optimal configuration
     * @param totalSupply Total token supply (to determine bits needed)
     * @param poolCount Current number of pools
     * @param buffer Extra pools to allow for growth (e.g., 50)
     * @param maxSlotsLimit Maximum slots allowed (configurable by admin)
     * @return config Calculated configuration
     */
    function calculateConfig(
        uint256 totalSupply,
        uint256 poolCount,
        uint256 buffer,
        uint256 maxSlotsLimit
    ) internal pure returns (Config memory config) {
        // Calculate bits needed for max possible weight
        // Add 1 bit safety margin
        uint256 bitsNeeded = log2Ceil(totalSupply) + 1;
        
        // Clamp to reasonable range
        if (bitsNeeded < MIN_BITS_PER_POOL) bitsNeeded = MIN_BITS_PER_POOL;
        if (bitsNeeded > MAX_BITS_PER_POOL) bitsNeeded = MAX_BITS_PER_POOL;
        
        // Calculate pools per slot
        uint256 poolsPerSlot = 256 / bitsNeeded;
        if (poolsPerSlot == 0) revert ConfigurationInvalid();
        
        // Calculate total pools with buffer
        uint256 maxPools = poolCount + buffer;
        
        // Calculate slots needed
        uint256 numSlots = (maxPools + poolsPerSlot - 1) / poolsPerSlot;
        
        // Check against configurable limit (capped by absolute max)
        uint256 effectiveMax = maxSlotsLimit > ABSOLUTE_MAX_SLOTS ? ABSOLUTE_MAX_SLOTS : maxSlotsLimit;
        if (numSlots > effectiveMax) revert TooManySlots(numSlots, effectiveMax);
        
        // Build config
        config.maxPools = uint32(maxPools);
        config.bitsPerPool = uint32(bitsNeeded);
        config.poolsPerSlot = uint32(poolsPerSlot);
        config.numSlots = uint32(numSlots);
        config.mask = (1 << bitsNeeded) - 1;
        config.maxWeight = config.mask;
    }
    
    /**
     * @notice Initialize storage slots
     * @param self Storage pointer
     * @param config Configuration
     */
    function initialize(
        PackedWeights storage self,
        Config memory config
    ) internal {
        // Resize array if needed
        uint256 currentLength = self.slots.length;
        uint256 needed = config.numSlots;
        
        if (currentLength < needed) {
            // Extend array
            for (uint256 i = currentLength; i < needed; i++) {
                self.slots.push(0);
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Get weight for a pool
     * @param self Storage pointer
     * @param config Configuration
     * @param poolIndex Index of pool
     * @return weight Current weight
     */
    function getWeight(
        PackedWeights storage self,
        Config memory config,
        uint256 poolIndex
    ) internal view returns (uint256 weight) {
        if (poolIndex >= config.maxPools) {
            revert PoolIndexOutOfBounds(poolIndex, config.maxPools - 1);
        }
        
        uint256 slot = poolIndex / config.poolsPerSlot;
        uint256 position = poolIndex % config.poolsPerSlot;
        uint256 offset = position * config.bitsPerPool;
        
        if (slot >= self.slots.length) return 0;
        
        weight = (self.slots[slot] >> offset) & config.mask;
    }
    
    /**
     * @notice Add weight to a pool
     * @param self Storage pointer
     * @param config Configuration
     * @param poolIndex Index of pool
     * @param amount Amount to add
     * @return newWeight Updated weight
     */
    function addWeight(
        PackedWeights storage self,
        Config memory config,
        uint256 poolIndex,
        uint256 amount
    ) internal returns (uint256 newWeight) {
        if (poolIndex >= config.maxPools) {
            revert PoolIndexOutOfBounds(poolIndex, config.maxPools - 1);
        }
        
        uint256 slot = poolIndex / config.poolsPerSlot;
        uint256 position = poolIndex % config.poolsPerSlot;
        uint256 offset = position * config.bitsPerPool;
        
        // Ensure slot exists
        while (self.slots.length <= slot) {
            self.slots.push(0);
        }
        
        // Read current value
        uint256 slotValue = self.slots[slot];
        uint256 currentWeight = (slotValue >> offset) & config.mask;
        
        // Calculate new weight
        newWeight = currentWeight + amount;
        if (newWeight > config.maxWeight) {
            revert WeightOverflow(newWeight, config.maxWeight);
        }
        
        // Clear old value and set new
        slotValue = slotValue & ~(config.mask << offset);
        slotValue = slotValue | (newWeight << offset);
        
        self.slots[slot] = slotValue;
    }
    
    /**
     * @notice Clear all weights
     * @param self Storage pointer
     */
    function clearAll(PackedWeights storage self) internal {
        uint256 len = self.slots.length;
        for (uint256 i = 0; i < len; i++) {
            self.slots[i] = 0;
        }
    }
    
    /**
     * @notice Load all slots into memory
     * @param self Storage pointer
     * @return slots Memory copy
     */
    function loadAll(
        PackedWeights storage self
    ) internal view returns (uint256[] memory slots) {
        uint256 len = self.slots.length;
        slots = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            slots[i] = self.slots[i];
        }
    }
    
    /**
     * @notice Find top N pools by weight
     * @param self Storage pointer
     * @param config Configuration
     * @param poolRegistry Index → pool address mapping
     * @param n Maximum pools to return
     * @return pools Top pool addresses
     * @return weights Corresponding weights
     * @return count Actual count returned
     */
    function findTopPools(
        PackedWeights storage self,
        Config memory config,
        mapping(uint256 => address) storage poolRegistry,
        uint256 n
    ) internal view returns (
        address[] memory pools,
        uint256[] memory weights,
        uint256 count
    ) {
        // Load all slots to memory
        uint256[] memory slots = loadAll(self);
        uint256 numSlots = slots.length;
        
        // Temporary arrays for top N
        pools = new address[](n);
        weights = new uint256[](n);
        count = 0;
        
        // Iterate through all pool positions
        for (uint256 poolIndex = 0; poolIndex < config.maxPools; poolIndex++) {
            uint256 slot = poolIndex / config.poolsPerSlot;
            if (slot >= numSlots) break;
            
            uint256 position = poolIndex % config.poolsPerSlot;
            uint256 offset = position * config.bitsPerPool;
            
            uint256 weight = (slots[slot] >> offset) & config.mask;
            
            if (weight == 0) continue;
            
            address pool = poolRegistry[poolIndex];
            if (pool == address(0)) continue;
            
            // Insert into top N
            if (count < n) {
                pools[count] = pool;
                weights[count] = weight;
                count++;
            } else {
                // Find minimum in current top N
                uint256 minIdx = 0;
                uint256 minWeight = weights[0];
                for (uint256 j = 1; j < n; j++) {
                    if (weights[j] < minWeight) {
                        minWeight = weights[j];
                        minIdx = j;
                    }
                }
                
                // Replace if current is higher
                if (weight > minWeight) {
                    pools[minIdx] = pool;
                    weights[minIdx] = weight;
                }
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // UTILITIES
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Calculate ceiling of log2
     * @param x Input value
     * @return result ceil(log2(x))
     */
    function log2Ceil(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        // Find highest set bit
        uint256 msb = 0;
        uint256 temp = x;
        
        if (temp >= 2**128) { msb += 128; temp >>= 128; }
        if (temp >= 2**64)  { msb += 64;  temp >>= 64; }
        if (temp >= 2**32)  { msb += 32;  temp >>= 32; }
        if (temp >= 2**16)  { msb += 16;  temp >>= 16; }
        if (temp >= 2**8)   { msb += 8;   temp >>= 8; }
        if (temp >= 2**4)   { msb += 4;   temp >>= 4; }
        if (temp >= 2**2)   { msb += 2;   temp >>= 2; }
        if (temp >= 2**1)   { msb += 1; }
        
        // Check if power of 2
        result = msb;
        if (x > (1 << msb)) {
            result += 1;
        }
    }
    
    /**
     * @notice Get storage statistics
     * @param config Configuration
     * @return bitsPerPool Bits allocated per pool
     * @return poolsPerSlot Pools per storage slot
     * @return totalSlots Total slots used
     * @return maxPoolIndex Maximum valid pool index
     * @return maxWeightPerPool Maximum weight per pool
     */
    function getStats(
        Config memory config
    ) internal pure returns (
        uint256 bitsPerPool,
        uint256 poolsPerSlot,
        uint256 totalSlots,
        uint256 maxPoolIndex,
        uint256 maxWeightPerPool
    ) {
        bitsPerPool = config.bitsPerPool;
        poolsPerSlot = config.poolsPerSlot;
        totalSlots = config.numSlots;
        maxPoolIndex = config.maxPools - 1;
        maxWeightPerPool = config.maxWeight;
    }
}
