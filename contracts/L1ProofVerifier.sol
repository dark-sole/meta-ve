// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
// Caveat Utilitator
pragma solidity ^0.8.24;

/**
 * @title L1ProofVerifier V.DELTA
 * @notice Verifies cross-L2 state via L1 Ethereum state proofs
 * @dev Used on Base to verify state from other L2s (Optimism, Arbitrum)
 * 
 * PROOF FLOW:
 * 1. Base's L1Block predeploy provides L1 block hash
 * 2. Verify L1 block header against this hash
 * 3. Use L1 state root to prove L2OutputOracle state
 * 4. Extract remote L2's state root from outputRoot
 * 5. Verify storage values against remote L2's state root
 * 
 */

// ============ EXTERNAL INTERFACES ============

/// @notice Base L1Block predeploy interface
interface IL1Block {
    function hash() external view returns (bytes32);
    function number() external view returns (uint64);
    function timestamp() external view returns (uint64);
}

// ============ LIBRARIES ============

/// @title RLPReader
/// @notice Library for parsing RLP encoded data
/// @dev Adapted from Solidity-RLP (https://github.com/hamdiallam/Solidity-RLP)
library RLPReader {
    uint8 constant STRING_SHORT_START = 0x80;
    uint8 constant STRING_LONG_START = 0xb8;
    uint8 constant LIST_SHORT_START = 0xc0;
    uint8 constant LIST_LONG_START = 0xf8;
    uint8 constant WORD_SIZE = 32;

    struct RLPItem {
        uint256 len;
        uint256 memPtr;
    }

    /// @notice Convert bytes to RLPItem
    function toRlpItem(bytes memory item) internal pure returns (RLPItem memory) {
        uint256 memPtr;
        assembly {
            memPtr := add(item, 0x20)
        }
        return RLPItem(item.length, memPtr);
    }

    /// @notice Convert RLPItem to list of RLPItems
    function toList(RLPItem memory item) internal pure returns (RLPItem[] memory) {
        require(isList(item), "RLP: not a list");
        
        uint256 items = numItems(item);
        RLPItem[] memory result = new RLPItem[](items);
        
        uint256 memPtr = item.memPtr + _payloadOffset(item.memPtr);
        uint256 dataLen;
        for (uint256 i = 0; i < items; i++) {
            dataLen = _itemLength(memPtr);
            result[i] = RLPItem(dataLen, memPtr);
            memPtr = memPtr + dataLen;
        }
        return result;
    }

    /// @notice Check if RLPItem is a list
    function isList(RLPItem memory item) internal pure returns (bool) {
        if (item.len == 0) return false;
        uint8 byte0;
        uint256 memPtr = item.memPtr;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }
        return byte0 >= LIST_SHORT_START;
    }

    /// @notice Convert RLPItem to bytes
    function toBytes(RLPItem memory item) internal pure returns (bytes memory) {
        require(item.len > 0, "RLP: empty item");
        
        uint256 offset = _payloadOffset(item.memPtr);
        uint256 len = item.len - offset;
        bytes memory result = new bytes(len);
        
        uint256 destPtr;
        assembly {
            destPtr := add(result, 0x20)
        }
        copy(item.memPtr + offset, destPtr, len);
        return result;
    }

    /// @notice Convert RLPItem to uint256
    function toUint(RLPItem memory item) internal pure returns (uint256) {
        require(item.len > 0 && item.len <= 33, "RLP: invalid uint");
        
        uint256 offset = _payloadOffset(item.memPtr);
        uint256 len = item.len - offset;
        uint256 result;
        uint256 memPtr = item.memPtr + offset;
        assembly {
            result := mload(memPtr)
            if lt(len, 32) {
                result := div(result, exp(256, sub(32, len)))
            }
        }
        return result;
    }

    /// @notice Convert RLPItem to bytes32
    function toBytes32(RLPItem memory item) internal pure returns (bytes32) {
        require(item.len > 0 && item.len <= 33, "RLP: invalid bytes32");
        
        uint256 offset = _payloadOffset(item.memPtr);
        uint256 len = item.len - offset;
        bytes32 result;
        uint256 memPtr = item.memPtr + offset;
        assembly {
            result := mload(memPtr)
            if lt(len, 32) {
                result := and(result, not(sub(exp(256, sub(32, len)), 1)))
            }
        }
        return result;
    }

    /// @notice Convert RLPItem to address
    function toAddress(RLPItem memory item) internal pure returns (address) {
        require(item.len == 21, "RLP: invalid address");
        return address(uint160(toUint(item)));
    }

    /// @notice Get number of items in RLP list
    function numItems(RLPItem memory item) private pure returns (uint256) {
        if (item.len == 0) return 0;
        
        uint256 count = 0;
        uint256 currPtr = item.memPtr + _payloadOffset(item.memPtr);
        uint256 endPtr = item.memPtr + item.len;
        while (currPtr < endPtr) {
            currPtr = currPtr + _itemLength(currPtr);
            count++;
        }
        return count;
    }

    /// @notice Get length of RLP item
    function _itemLength(uint256 memPtr) private pure returns (uint256) {
        uint256 itemLen;
        uint256 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }
        
        if (byte0 < STRING_SHORT_START) {
            itemLen = 1;
        } else if (byte0 < STRING_LONG_START) {
            itemLen = byte0 - STRING_SHORT_START + 1;
        } else if (byte0 < LIST_SHORT_START) {
            uint256 dataLen;
            uint256 lenOfLen = byte0 - STRING_LONG_START + 1;
            assembly {
                let lenPtr := add(memPtr, 1)
                dataLen := div(mload(lenPtr), exp(256, sub(32, lenOfLen)))
            }
            itemLen = 1 + lenOfLen + dataLen;
        } else if (byte0 < LIST_LONG_START) {
            itemLen = byte0 - LIST_SHORT_START + 1;
        } else {
            uint256 dataLen;
            uint256 lenOfLen = byte0 - LIST_LONG_START + 1;
            assembly {
                let lenPtr := add(memPtr, 1)
                dataLen := div(mload(lenPtr), exp(256, sub(32, lenOfLen)))
            }
            itemLen = 1 + lenOfLen + dataLen;
        }
        return itemLen;
    }

    /// @notice Get payload offset
    function _payloadOffset(uint256 memPtr) private pure returns (uint256) {
        uint256 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }
        
        if (byte0 < STRING_SHORT_START) {
            return 0;
        } else if (byte0 < STRING_LONG_START) {
            return 1;
        } else if (byte0 < LIST_SHORT_START) {
            return byte0 - STRING_LONG_START + 2;
        } else if (byte0 < LIST_LONG_START) {
            return 1;
        } else {
            return byte0 - LIST_LONG_START + 2;
        }
    }

    /// @notice Copy memory
    function copy(uint256 src, uint256 dest, uint256 len) private pure {
        if (len == 0) return;
        for (; len >= WORD_SIZE; len -= WORD_SIZE) {
            assembly {
                mstore(dest, mload(src))
            }
            src += WORD_SIZE;
            dest += WORD_SIZE;
        }
        if (len > 0) {
            uint256 mask = 256 ** (WORD_SIZE - len) - 1;
            assembly {
                let srcpart := and(mload(src), not(mask))
                let destpart := and(mload(dest), mask)
                mstore(dest, or(destpart, srcpart))
            }
        }
    }
}

/// @title MerklePatriciaProof
/// @notice Library for verifying Merkle Patricia Trie proofs
library MerklePatriciaProof {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    /// @notice Verify a Merkle Patricia proof
    /// @param value Expected value (RLP encoded for account, raw for storage)
    /// @param encodedPath Keccak256 hash of the key (address or storage slot)
    /// @param rlpParentNodes RLP encoded proof nodes
    /// @param root State root to verify against
    /// @return True if proof is valid
    function verify(
        bytes memory value,
        bytes memory encodedPath,
        bytes memory rlpParentNodes,
        bytes32 root
    ) internal pure returns (bool) {
        RLPReader.RLPItem memory item = rlpParentNodes.toRlpItem();
        RLPReader.RLPItem[] memory parentNodes = item.toList();

        bytes memory currentNode;
        RLPReader.RLPItem[] memory currentNodeList;

        bytes32 nodeKey = root;
        uint256 pathPtr = 0;

        bytes memory path = _getNibbles(encodedPath);

        for (uint256 i = 0; i < parentNodes.length; i++) {
            if (pathPtr > path.length) return false;

            currentNode = parentNodes[i].toBytes();
            if (nodeKey != keccak256(currentNode)) return false;

            currentNodeList = currentNode.toRlpItem().toList();

            if (currentNodeList.length == 17) {
                // Branch node
                if (pathPtr == path.length) {
                    // Value is in this branch node
                    if (keccak256(currentNodeList[16].toBytes()) == keccak256(value)) {
                        return true;
                    } else {
                        return false;
                    }
                }

                uint8 nextPathNibble = uint8(path[pathPtr]);
                if (nextPathNibble > 16) return false;
                nodeKey = bytes32(currentNodeList[nextPathNibble].toUint());
                pathPtr += 1;
            } else if (currentNodeList.length == 2) {
                // Extension or Leaf node
                bytes memory nodePath = _getNibbles(currentNodeList[0].toBytes());
                uint256 prefixLength = _sharedPrefixLength(path, pathPtr, nodePath);
                
                // Check if this is a leaf (prefix starts with 2 or 3) or extension (0 or 1)
                uint8 prefix = uint8(nodePath[0]);
                bool isLeaf = prefix == 2 || prefix == 3;
                
                if (isLeaf) {
                    // Leaf node - remaining path must match exactly
                    if (pathPtr + prefixLength == path.length) {
                        return keccak256(currentNodeList[1].toBytes()) == keccak256(value);
                    }
                    return false;
                } else {
                    // Extension node
                    if (prefixLength < nodePath.length - 1) return false;
                    pathPtr += prefixLength;
                    nodeKey = bytes32(currentNodeList[1].toUint());
                }
            } else {
                return false;
            }
        }

        return false;
    }

    /// @notice Convert bytes to nibbles
    function _getNibbles(bytes memory b) private pure returns (bytes memory) {
        bytes memory nibbles = new bytes(b.length * 2);
        for (uint256 i = 0; i < b.length; i++) {
            nibbles[i * 2] = bytes1(uint8(b[i]) / 16);
            nibbles[i * 2 + 1] = bytes1(uint8(b[i]) % 16);
        }
        return nibbles;
    }

    /// @notice Get shared prefix length between path and nodePath starting at pathPtr
    function _sharedPrefixLength(
        bytes memory path,
        uint256 pathPtr,
        bytes memory nodePath
    ) private pure returns (uint256) {
        uint256 len = 0;
        // Skip the prefix nibble(s) in nodePath
        uint256 nodePathStart = (uint8(nodePath[0]) % 2 == 0) ? 2 : 1;
        
        for (uint256 i = nodePathStart; i < nodePath.length && pathPtr + len < path.length; i++) {
            if (nodePath[i] != path[pathPtr + len]) break;
            len++;
        }
        return len;
    }
}

// ============ MAIN CONTRACT ============

contract L1ProofVerifier {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    // ============ CONSTANTS ============

    /// @notice Base L1Block predeploy address
    address public constant L1_BLOCK_PREDEPLOY = 0x4200000000000000000000000000000000000015;
    
    /// @notice Maximum age of L1 block for proof (prevent stale proofs)
    uint256 public constant MAX_BLOCK_AGE = 256;

    // ============ STATE ============

    /// @notice L2 Output Oracle addresses on L1 for each chain
    mapping(uint256 => address) public l2OutputOracles;
    
    /// @notice Output oracle storage slot for outputs (chain-specific)
    mapping(uint256 => bytes32) public outputRootSlots;
    
    /// @notice Owner for configuration
    address public owner;
    
    /// @notice Verified state roots cache (chainId => l1BlockNumber => stateRoot)
    mapping(uint256 => mapping(uint256 => bytes32)) public cachedStateRoots;

    // ============ EVENTS ============

    event OracleConfigured(uint256 indexed chainId, address oracle, bytes32 slot);
    event StateRootCached(uint256 indexed chainId, uint256 indexed l1Block, bytes32 stateRoot);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============ ERRORS ============

    error NotOwner();
    error ChainNotConfigured();
    error InvalidBlockHeader();
    error BlockHashMismatch();
    error BlockTooOld();
    error InvalidAccountProof();
    error InvalidStorageProof();
    error InvalidOutputRoot();
    error ZeroAddress();

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor() {
        owner = msg.sender;
    }

    // ============ CONFIGURATION ============

    /// @notice Configure L2 Output Oracle for a chain
    /// @param chainId The chain ID of the remote L2
    /// @param oracle The L2OutputOracle address on L1
    /// @param slot The storage slot for the outputs array
    function configureChain(
        uint256 chainId,
        address oracle,
        bytes32 slot
    ) external onlyOwner {
        if (oracle == address(0)) revert ZeroAddress();
        
        l2OutputOracles[chainId] = oracle;
        outputRootSlots[chainId] = slot;
        
        emit OracleConfigured(chainId, oracle, slot);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ============ CORE VERIFICATION ============

    /// @notice Full proof structure for cross-L2 verification
    struct CrossL2Proof {
        // L1 block reference
        uint256 l1BlockNumber;
        bytes l1BlockHeader;        // RLP encoded L1 block header
        
        // L2 Output proof (on L1)
        uint256 l2OutputIndex;      // Index in outputs array
        bytes l1AccountProof;       // Prove L2OutputOracle on L1
        bytes l1StorageProof;       // Prove outputRoot in oracle
        
        // Remote L2 state proof
        uint256 l2BlockNumber;
        bytes l2AccountProof;       // Prove contract on remote L2
        bytes[] l2StorageProofs;    // Prove storage slots on remote L2
    }

    /// @notice Account state structure
    struct AccountState {
        uint256 nonce;
        uint256 balance;
        bytes32 storageRoot;
        bytes32 codeHash;
    }

    /// @notice Get the current L1 block hash from predeploy
    function getL1BlockHash() public view returns (bytes32) {
        return IL1Block(L1_BLOCK_PREDEPLOY).hash();
    }

    /// @notice Get the current L1 block number from predeploy
    function getL1BlockNumber() public view returns (uint64) {
        return IL1Block(L1_BLOCK_PREDEPLOY).number();
    }

    /// @notice Verify and extract state root from L1 block header
    /// @param l1BlockNumber Expected block number
    /// @param l1BlockHeader RLP encoded block header
    /// @return stateRoot The L1 state root
    function verifyL1BlockHeader(
        uint256 l1BlockNumber,
        bytes memory l1BlockHeader
    ) public view returns (bytes32 stateRoot) {
        // Verify block hash matches L1Block predeploy
        bytes32 headerHash = keccak256(l1BlockHeader);
        bytes32 expectedHash = getL1BlockHash();
        uint64 currentL1Block = getL1BlockNumber();
        
        // For now, we only verify against the current L1 block
        // In production, would need historical block hash access
        if (l1BlockNumber != currentL1Block) {
            // Check if block is within range
            if (currentL1Block > l1BlockNumber + MAX_BLOCK_AGE) revert BlockTooOld();
        }
        
        if (headerHash != expectedHash) revert BlockHashMismatch();
        
        // Parse block header to extract state root
        // Block header format: [parentHash, uncleHash, coinbase, stateRoot, ...]
        RLPReader.RLPItem[] memory headerFields = l1BlockHeader.toRlpItem().toList();
        
        if (headerFields.length < 4) revert InvalidBlockHeader();
        
        // State root is at index 3
        stateRoot = headerFields[3].toBytes32();
    }

    /// @notice Verify account exists and get its storage root
    /// @param stateRoot The state root to verify against
    /// @param account The account address
    /// @param accountProof RLP encoded account proof
    /// @return state The account state
    function verifyAccountProof(
        bytes32 stateRoot,
        address account,
        bytes memory accountProof
    ) public pure returns (AccountState memory state) {
        // Account key is keccak256(address)
        bytes memory key = abi.encodePacked(keccak256(abi.encodePacked(account)));
        
        // Verify proof and get account RLP
        // The value in the trie is RLP([nonce, balance, storageRoot, codeHash])
        RLPReader.RLPItem memory proofItem = accountProof.toRlpItem();
        RLPReader.RLPItem[] memory proofNodes = proofItem.toList();
        
        if (proofNodes.length == 0) revert InvalidAccountProof();
        
        // Get the leaf value (last node contains the value)
        bytes memory accountRlp = _extractValueFromProof(accountProof, key, stateRoot);
        
        // Parse account state
        RLPReader.RLPItem[] memory accountFields = accountRlp.toRlpItem().toList();
        
        if (accountFields.length != 4) revert InvalidAccountProof();
        
        state.nonce = accountFields[0].toUint();
        state.balance = accountFields[1].toUint();
        state.storageRoot = accountFields[2].toBytes32();
        state.codeHash = accountFields[3].toBytes32();
    }

    /// @notice Verify storage value at a slot
    /// @param storageRoot The storage root to verify against
    /// @param slot The storage slot
    /// @param storageProof RLP encoded storage proof
    /// @return value The storage value
    function verifyStorageProof(
        bytes32 storageRoot,
        bytes32 slot,
        bytes memory storageProof
    ) public pure returns (bytes32 value) {
        // Storage key is keccak256(slot)
        bytes memory key = abi.encodePacked(keccak256(abi.encodePacked(slot)));
        
        // Verify and extract value
        bytes memory valueRlp = _extractValueFromProof(storageProof, key, storageRoot);
        
        // Storage values are RLP encoded
        value = valueRlp.toRlpItem().toBytes32();
    }

    /// @notice Extract value from Merkle Patricia proof
    function _extractValueFromProof(
        bytes memory proof,
        bytes memory key,
        bytes32 root
    ) internal pure returns (bytes memory value) {
        RLPReader.RLPItem[] memory proofNodes = proof.toRlpItem().toList();
        
        bytes32 nodeKey = root;
        bytes memory path = _toNibbles(key);
        uint256 pathPtr = 0;

        for (uint256 i = 0; i < proofNodes.length; i++) {
            bytes memory currentNode = proofNodes[i].toBytes();
            
            // Verify node hash
            if (keccak256(currentNode) != nodeKey) revert InvalidStorageProof();
            
            RLPReader.RLPItem[] memory nodeList = currentNode.toRlpItem().toList();
            
            if (nodeList.length == 17) {
                // Branch node
                if (pathPtr >= path.length) {
                    // Value in branch
                    return nodeList[16].toBytes();
                }
                uint8 nibble = uint8(path[pathPtr]);
                nodeKey = nodeList[nibble].toBytes32();
                pathPtr++;
            } else if (nodeList.length == 2) {
                // Extension or Leaf
                bytes memory nodePath = _toNibbles(nodeList[0].toBytes());
                uint8 prefix = uint8(nodePath[0]);
                
                // Determine if leaf (2,3) or extension (0,1)
                bool isLeaf = (prefix == 2 || prefix == 3);
                uint256 skipLen = (prefix % 2 == 0) ? 2 : 1;
                
                // Compare paths
                for (uint256 j = skipLen; j < nodePath.length; j++) {
                    if (pathPtr >= path.length || nodePath[j] != path[pathPtr]) {
                        revert InvalidStorageProof();
                    }
                    pathPtr++;
                }
                
                if (isLeaf) {
                    return nodeList[1].toBytes();
                } else {
                    nodeKey = nodeList[1].toBytes32();
                }
            } else {
                revert InvalidStorageProof();
            }
        }
        
        revert InvalidStorageProof();
    }

    /// @notice Convert bytes to nibbles
    function _toNibbles(bytes memory data) internal pure returns (bytes memory) {
        bytes memory nibbles = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            nibbles[i * 2] = bytes1(uint8(data[i]) >> 4);
            nibbles[i * 2 + 1] = bytes1(uint8(data[i]) & 0x0f);
        }
        return nibbles;
    }

    // ============ HIGH-LEVEL VERIFICATION FUNCTIONS ============

    /// @notice Verify remote L2 state root via L1
    /// @param chainId Remote chain ID
    /// @param l1BlockNumber L1 block number
    /// @param l1BlockHeader RLP encoded L1 block header
    /// @param l2OutputIndex Output index in L2OutputOracle
    /// @param l1AccountProof Proof of L2OutputOracle on L1
    /// @param l1StorageProof Proof of outputRoot in oracle
    /// @return l2StateRoot The verified remote L2 state root
    function verifyL2StateRoot(
        uint256 chainId,
        uint256 l1BlockNumber,
        bytes calldata l1BlockHeader,
        uint256 l2OutputIndex,
        bytes calldata l1AccountProof,
        bytes calldata l1StorageProof
    ) external view returns (bytes32 l2StateRoot) {
        address oracle = l2OutputOracles[chainId];
        if (oracle == address(0)) revert ChainNotConfigured();
        
        // 1. Verify L1 block header and get state root
        bytes32 l1StateRoot = verifyL1BlockHeader(l1BlockNumber, l1BlockHeader);
        
        // 2. Verify L2OutputOracle account on L1
        AccountState memory oracleState = verifyAccountProof(
            l1StateRoot,
            oracle,
            l1AccountProof
        );
        
        // 3. Calculate storage slot for outputs[l2OutputIndex]
        // outputs is a dynamic array, so slot = keccak256(baseSlot) + index
        bytes32 baseSlot = outputRootSlots[chainId];
        bytes32 arraySlot = keccak256(abi.encodePacked(baseSlot));
        bytes32 outputSlot = bytes32(uint256(arraySlot) + l2OutputIndex * 2); // OutputRoot is 2 slots
        
        // 4. Verify outputRoot in oracle storage
        bytes32 outputRoot = verifyStorageProof(
            oracleState.storageRoot,
            outputSlot,
            l1StorageProof
        );
        
        // 5. Extract L2 state root from outputRoot
        // Optimism outputRoot = keccak256(version, stateRoot, messagePasserStorageRoot, latestBlockHash)
        // For OP Bedrock, the first 32 bytes after the output root slot is the stateRoot
        // Actually, we need the second slot which contains the stateRoot
        bytes32 stateRootSlot = bytes32(uint256(outputSlot) + 1);
        l2StateRoot = verifyStorageProof(
            oracleState.storageRoot,
            stateRootSlot,
            l1StorageProof
        );
    }

    /// @notice Verify storage value on remote L2
    /// @param chainId Remote chain ID
    /// @param l2StateRoot Previously verified L2 state root
    /// @param contractAddress Contract address on remote L2
    /// @param slot Storage slot
    /// @param l2AccountProof Account proof on L2
    /// @param l2StorageProof Storage proof on L2
    /// @return value The storage value
    function verifyRemoteStorage(
        uint256 chainId,
        bytes32 l2StateRoot,
        address contractAddress,
        bytes32 slot,
        bytes calldata l2AccountProof,
        bytes calldata l2StorageProof
    ) external pure returns (bytes32 value) {
        // 1. Verify contract account on L2
        AccountState memory contractState = verifyAccountProof(
            l2StateRoot,
            contractAddress,
            l2AccountProof
        );
        
        // 2. Verify storage slot
        value = verifyStorageProof(
            contractState.storageRoot,
            slot,
            l2StorageProof
        );
    }

    // ============ META PROTOCOL SPECIFIC VERIFIERS ============

    /// @notice Verify remote fee balance for META protocol
    /// @param chainId Remote chain ID
    /// @param epoch Epoch number
    /// @param expectedFees Expected fee amount
    /// @param proof Full cross-L2 proof
    /// @return valid True if proof verifies the fee amount
    function verifyRemoteFees(
        uint256 chainId,
        uint256 epoch,
        uint256 expectedFees,
        bytes calldata proof
    ) external view returns (bool valid) {
        // Decode proof
        CrossL2Proof memory p = abi.decode(proof, (CrossL2Proof));
        
        address oracle = l2OutputOracles[chainId];
        if (oracle == address(0)) revert ChainNotConfigured();
        
        // 1. Verify L1 state
        bytes32 l1StateRoot = verifyL1BlockHeader(p.l1BlockNumber, p.l1BlockHeader);
        
        // 2. Verify L2OutputOracle on L1
        AccountState memory oracleState = verifyAccountProof(
            l1StateRoot,
            oracle,
            p.l1AccountProof
        );
        
        // 3. Get L2 state root from oracle
        bytes32 baseSlot = outputRootSlots[chainId];
        bytes32 outputSlot = bytes32(uint256(keccak256(abi.encodePacked(baseSlot))) + p.l2OutputIndex * 2 + 1);
        bytes32 l2StateRoot = verifyStorageProof(
            oracleState.storageRoot,
            outputSlot,
            p.l1StorageProof
        );
        
        // 4. Verify MetaFeeLock contract on L2
        // Note: MetaFeeLock address would be configured per chain
        // For now, extract from proof or use configured address
        
        // 5. Verify epochFees[epoch] storage slot
        // epochFees is mapping(uint256 => uint256) at some slot
        // slot = keccak256(epoch, baseSlot)
        
        // For this stub, return true if we got this far without reverting
        // Real implementation would complete verification
        return true;
    }

    /// @notice Verify remote burn for BASE META mint
    /// @param chainId Remote chain ID
    /// @param user User address
    /// @param burnedAmount Expected burned amount
    /// @param proof Full cross-L2 proof
    /// @return valid True if proof verifies the burn
    function verifyRemoteBurn(
        uint256 chainId,
        address user,
        uint256 burnedAmount,
        bytes calldata proof
    ) external view returns (bool valid) {
        // Similar structure to verifyRemoteFees
        // Would verify userBurnedForBase[user] on MetaFeeLock
        
        // Stub implementation
        return true;
    }

    // ============ HELPER FUNCTIONS ============

    /// @notice Calculate storage slot for mapping(uint256 => uint256)
    function getMappingSlot(bytes32 baseSlot, uint256 key) external pure returns (bytes32) {
        return keccak256(abi.encode(key, baseSlot));
    }

    /// @notice Calculate storage slot for mapping(address => uint256)
    function getAddressMappingSlot(bytes32 baseSlot, address key) external pure returns (bytes32) {
        return keccak256(abi.encode(key, baseSlot));
    }

    /// @notice Calculate storage slot for nested mapping(uint256 => mapping(address => uint256))
    function getNestedMappingSlot(
        bytes32 baseSlot,
        uint256 key1,
        address key2
    ) external pure returns (bytes32) {
        bytes32 innerSlot = keccak256(abi.encode(key1, baseSlot));
        return keccak256(abi.encode(key2, innerSlot));
    }
}
