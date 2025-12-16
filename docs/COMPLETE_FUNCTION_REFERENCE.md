# COMPLETE SMART CONTRACT FUNCTION REFERENCE
# All Functions from All Contracts

Generated: Complete extraction from all .sol files

================================================================================

## AdversarialTest
**File:** `AdversarialTest.sol`

### Functions

**Line 24:** [public]
```solidity
function setUp() public override
```

**Line 49:** [public]
```solidity
function test_Adversarial_TimingAttacks() public
```

**Line 77:** [public]
```solidity
function test_Adversarial_TransferExploits() public
```

**Line 106:** [public]
```solidity
function test_Adversarial_Reentrancy_ClaimFees() public
```

**Line 129:** [public]
```solidity
function test_Adversarial_ProtocolTokenBypass() public
```

**Line 150:** [public]
```solidity
function test_Adversarial_LiquidationGaming() public
```

**Line 175:** [public]
```solidity
function test_Adversarial_NFTManipulation() public
```

**Line 198:** [public]
```solidity
function test_Adversarial_WindfallProtection() public
```

**Line 220:** [internal]
```solidity
function _setupMultipleDepositors() internal
```

**Line 269:** [external]
```solidity
function mint(address to, uint256 amount) external
```

**Line 274:** [external]
```solidity
function transfer(address to, uint256 amount) external returns (bool)
```

**Line 286:** [external]
```solidity
function approve(address spender, uint256 amount) external returns (bool)
```

**Line 291:** [external]
```solidity
function transferFrom(address from, address to, uint256 amount) external returns (bool)
```

**Line 298:** [external]
```solidity
function enableAttack() external
```

**Line 314:** [external]
```solidity
function onERC721Received( address from, uint256 tokenId, bytes calldata data ) external override returns (bytes4)
```

**Line 328:** [external]
```solidity
function enableAttack() external
```

**Line 332:** [external]
```solidity
function approve(address token, address spender, uint256 amount) external
```

---

## CToken
**File:** `CToken.sol`

### Functions

**Line 94:** [public, pure]
```solidity
function decimals() public pure override returns (uint8)
```

**Line 102:** [external]
```solidity
function setSplitter(address _splitter) external onlyOwner
```

**Line 109:** [external]
```solidity
function setMeta(address _meta) external onlyOwner
```

**Line 115:** [external]
```solidity
function setLiquidation(address _liquidation) external onlyOwner
```

**Line 130:** [external]
```solidity
function mint(address to, uint256 amount) external onlySplitter
```

**Line 136:** [external]
```solidity
function burn(address from, uint256 amount) external onlySplitter
```

**Line 150:** [external]
```solidity
function collectMeta() external nonReentrant returns (uint256 metaClaimed)
```

**Line 175:** [external]
```solidity
function claimMeta() external nonReentrant returns (uint256 amount)
```

**Line 200:** [external, view]
```solidity
function pendingMeta(address user) external view returns (uint256)
```

**Line 220:** [internal]
```solidity
function _tryCollectMeta(IMeta _meta) internal
```

**Line 238:** [internal]
```solidity
function _checkpointUser(address user) internal
```

**Line 247:** [internal]
```solidity
function _updateUserDebt(address user) internal
```

**Line 260:** [external]
```solidity
function voteEmissions(int8 choice, uint256 amount) external nonReentrant
```

**Line 303:** [external]
```solidity
function voteLiquidation(uint256 amount) external nonReentrant
```

**Line 325:** [public, view]
```solidity
function unlockedBalanceOf(address account) public view returns (uint256)
```

**Line 334:** [external, view]
```solidity
function isLocked(address account) external view returns (bool)
```

**Line 342:** [internal]
```solidity
function _update(address from, address to, uint256 amount) internal virtual override
```

**Line 377:** [external, view]
```solidity
function isMetaActive() external view returns (bool)
```

**Line 381:** [external, view]
```solidity
function getMetaAccumulator() external view returns (uint256)
```

---

## EpochGovernor
**File:** `EpochGovernor.sol`

### Functions

**Line 27:** [public, pure]
```solidity
function votingDelay() public pure override(IGovernor) returns (uint256)
```

**Line 31:** [public, pure]
```solidity
function votingPeriod() public pure override(IGovernor) returns (uint256)
```

---

## L1ProofVerifier
**File:** `L1ProofVerifier.sol`

### Functions

**Line 24:** [external, view]
```solidity
function hash() external view returns (bytes32)
```

**Line 25:** [external, view]
```solidity
function number() external view returns (uint64)
```

**Line 26:** [external, view]
```solidity
function timestamp() external view returns (uint64)
```

**Line 47:** [internal, pure]
```solidity
function toRlpItem(bytes memory item) internal pure returns (RLPItem memory)
```

**Line 56:** [internal, pure]
```solidity
function toList(RLPItem memory item) internal pure returns (RLPItem[] memory)
```

**Line 73:** [internal, pure]
```solidity
function isList(RLPItem memory item) internal pure returns (bool)
```

**Line 84:** [internal, pure]
```solidity
function toBytes(RLPItem memory item) internal pure returns (bytes memory)
```

**Line 100:** [internal, pure]
```solidity
function toUint(RLPItem memory item) internal pure returns (uint256)
```

**Line 117:** [internal, pure]
```solidity
function toBytes32(RLPItem memory item) internal pure returns (bytes32)
```

**Line 134:** [internal, pure]
```solidity
function toAddress(RLPItem memory item) internal pure returns (address)
```

**Line 140:** [private, pure]
```solidity
function numItems(RLPItem memory item) private pure returns (uint256)
```

**Line 154:** [private, pure]
```solidity
function _itemLength(uint256 memPtr) private pure returns (uint256)
```

**Line 188:** [private, pure]
```solidity
function _payloadOffset(uint256 memPtr) private pure returns (uint256)
```

**Line 208:** [private, pure]
```solidity
function copy(uint256 src, uint256 dest, uint256 len) private pure
```

**Line 240:** [internal, pure]
```solidity
function verify( bytes memory encodedPath, bytes memory rlpParentNodes, bytes32 root ) internal pure returns (bool)
```

**Line 310:** [private, pure]
```solidity
function _getNibbles(bytes memory b) private pure returns (bytes memory)
```

**Line 320:** [private, pure]
```solidity
function _sharedPrefixLength( uint256 pathPtr, bytes memory nodePath ) private pure returns (uint256)
```

**Line 402:** [external]
```solidity
function configureChain( address oracle, bytes32 slot ) external onlyOwner
```

**Line 416:** [external]
```solidity
function transferOwnership(address newOwner) external onlyOwner
```

**Line 450:** [public, view]
```solidity
function getL1BlockHash() public view returns (bytes32)
```

**Line 455:** [public, view]
```solidity
function getL1BlockNumber() public view returns (uint64)
```

**Line 463:** [public, view]
```solidity
function verifyL1BlockHeader( bytes memory l1BlockHeader ) public view returns (bytes32 stateRoot)
```

**Line 496:** [public, pure]
```solidity
function verifyAccountProof( address account, bytes memory accountProof ) public pure returns (AccountState memory state)
```

**Line 530:** [public, pure]
```solidity
function verifyStorageProof( bytes32 slot, bytes memory storageProof ) public pure returns (bytes32 value)
```

**Line 546:** [internal, pure]
```solidity
function _extractValueFromProof( bytes memory key, bytes32 root ) internal pure returns (bytes memory value)
```

**Line 605:** [internal, pure]
```solidity
function _toNibbles(bytes memory data) internal pure returns (bytes memory)
```

**Line 624:** [external, view]
```solidity
function verifyL2StateRoot( uint256 l1BlockNumber, bytes calldata l1BlockHeader, uint256 l2OutputIndex, bytes calldata l1AccountProof, bytes calldata l1StorageProof ) external view returns (bytes32 l2StateRoot)
```

**Line 678:** [external, pure]
```solidity
function verifyRemoteStorage( bytes32 l2StateRoot, address contractAddress, bytes32 slot, bytes calldata l2AccountProof, bytes calldata l2StorageProof ) external pure returns (bytes32 value)
```

**Line 709:** [external, view]
```solidity
function verifyRemoteFees( uint256 epoch, uint256 expectedFees, bytes calldata proof ) external view returns (bool valid)
```

**Line 759:** [external, view]
```solidity
function verifyRemoteBurn( address user, uint256 burnedAmount, bytes calldata proof ) external view returns (bool valid)
```

**Line 775:** [external, pure]
```solidity
function getMappingSlot(bytes32 baseSlot, uint256 key) external pure returns (bytes32)
```

**Line 780:** [external, pure]
```solidity
function getAddressMappingSlot(bytes32 baseSlot, address key) external pure returns (bytes32)
```

**Line 785:** [external, pure]
```solidity
function getNestedMappingSlot( uint256 key1, address key2 ) external pure returns (bytes32)
```

---

## Meta
**File:** `Meta.sol`

### Functions

**Line 276:** [internal, view]
```solidity
function _getPoolData(address pool) internal view returns (uint128 baseline, uint128 accrued)
```

**Line 282:** [internal]
```solidity
function _setPoolData(address pool, uint128 baseline, uint128 accrued) internal
```

**Line 286:** [internal, view]
```solidity
function _getUserBaselines(address user) internal view returns (uint128 metaBaseline, uint128 feeBaseline)
```

**Line 292:** [internal]
```solidity
function _setUserBaselines(address user, uint128 metaBaseline, uint128 feeBaseline) internal
```

**Line 300:** [external]
```solidity
function setSplitter(address _splitter) external onlyMSIG
```

**Line 306:** [external]
```solidity
function setVToken(address _vToken) external onlyMSIG
```

**Line 312:** [external]
```solidity
function setLPPool(address _pool) external onlyMSIG
```

**Line 317:** [external]
```solidity
function setPoolLPGauge(address vePool, address lpGauge_) external onlyMSIG
```

**Line 324:** [external]
```solidity
function setMSIG(address newMSIG) external onlyMSIG
```

**Line 333:** [external]
```solidity
function renounceL1ProofAuthority() external onlyMSIG
```

**Line 340:** [external]
```solidity
function setL1ProofVerifier(address _verifier) external onlyMSIG
```

**Line 347:** [external]
```solidity
function whitelistChain(uint256 chainId) external onlyMSIG
```

**Line 357:** [external]
```solidity
function removeChain(uint256 chainId) external onlyMSIG
```

**Line 379:** [external]
```solidity
function setFeeContract(address _feeContract) external onlyMSIG
```

**Line 385:** [external]
```solidity
function enableMultiVE() external onlyMSIG
```

**Line 402:** [external]
```solidity
function receiveFees(uint256 amount) external onlySplitter nonReentrant
```

**Line 465:** [internal, view]
```solidity
function _getLocalVEPool() internal view returns (address)
```

**Line 485:** [internal]
```solidity
function _pushToLPGauge(address vePool) internal
```

**Line 505:** [internal]
```solidity
function _pushAllLocalLPGauges() internal
```

**Line 516:** [external]
```solidity
function pushToLPGauge(address vePool) external nonReentrant
```

**Line 522:** [external]
```solidity
function pushAllLPGauges() external nonReentrant
```

**Line 526:** [external]
```solidity
function pushVote() external nonReentrant
```

**Line 557:** [public, view]
```solidity
function getCurrentDay() public view returns (uint64)
```

**Line 562:** [external, view]
```solidity
function needsIndexUpdate() external view returns (bool)
```

**Line 566:** [public, view]
```solidity
function getCurrentS() public view returns (uint256)
```

**Line 573:** [public]
```solidity
function updateIndex(uint64 maxSteps) public returns (uint64 processedDays, bool complete)
```

**Line 624:** [internal]
```solidity
function _distributeCTokenIncentives(uint256 totalMinted, uint256 S) internal
```

**Line 673:** [internal]
```solidity
function _distributeLPIncentives(uint256 totalMinted, uint256 S) internal
```

**Line 716:** [external]
```solidity
function updateIndex() external returns (uint64, bool)
```

**Line 720:** [internal]
```solidity
function _processDays(uint64 daysToProcess, uint256 U) internal returns (uint256 totalMinted, uint128 newIndex)
```

**Line 760:** [external]
```solidity
function lockAndVote(uint256 amount, address vePool) external nonReentrant
```

**Line 788:** [external]
```solidity
function initiateUnlock(uint256 amount) external nonReentrant
```

**Line 809:** [external]
```solidity
function completeUnlock() external nonReentrant
```

**Line 844:** [internal]
```solidity
function _ensureIndexUpdated() internal
```

**Line 850:** [internal]
```solidity
function _checkpointUser(address user) internal
```

**Line 887:** [internal]
```solidity
function _syncPoolBaseline(address vePool) internal
```

**Line 903:** [external]
```solidity
function claimRewards() external nonReentrant returns (uint256 metaAmt, uint256 aeroAmt)
```

**Line 932:** [external]
```solidity
function claimStakerRewards() external nonReentrant returns (uint256 amount)
```

**Line 963:** [external]
```solidity
function claimForVEPool() external nonReentrant returns (uint256 amount)
```

**Line 989:** [external]
```solidity
function claimFeesForVEPool() external nonReentrant returns (uint256 amount)
```

**Line 1007:** [external]
```solidity
function claimTreasury() external nonReentrant returns (uint256 amount)
```

**Line 1040:** [external]
```solidity
function addVEPool(address vePool, uint256 chainId, address lpGauge_) external onlyMSIG
```

**Line 1058:** [external]
```solidity
function addVEPool(address vePool, address lpGauge_) external onlyMSIG
```

**Line 1072:** [external]
```solidity
function removeVEPool(address vePool) external onlyMSIG
```

**Line 1101:** [internal, view]
```solidity
function _totalPoolFeeAccrued() internal view returns (uint256 total)
```

**Line 1109:** [external, view]
```solidity
function getVEPools() external view returns (address[] memory)
```

**Line 1113:** [external, view]
```solidity
function getChainList() external view returns (uint256[] memory)
```

**Line 1117:** [external, view]
```solidity
function isRemotePool(address vePool) external view returns (bool)
```

**Line 1121:** [external, view]
```solidity
function isLocalPool(address vePool) external view returns (bool)
```

**Line 1125:** [external, view]
```solidity
function getUserInfo(address user) external view returns ( uint256 unlockingAmount, address votedPool, uint256 unlockTime, uint256 pendingMeta, uint256 pendingAero )
```

**Line 1160:** [external, view]
```solidity
function getAvailableToUnlock(address user) external view returns (uint256 available)
```

**Line 1166:** [external, view]
```solidity
function getPoolInfo(address vePool) external view returns ( uint256 votes, uint256 pendingRewards, uint256 chainId, address lpGauge_, uint256 pendingLPMeta, uint256 pendingFees )
```

**Line 1186:** [external, view]
```solidity
function getCatchupStatus() external view returns ( uint64 lastUpdated, uint64 pendingDays, bool needsUpdate )
```

**Line 1201:** [external, view]
```solidity
function getLPGaugeInfo(address vePool) external view returns ( uint256 pendingMeta )
```

**Line 1208:** [external, view]
```solidity
function getCrossChainStatus() external view returns ( uint256 whitelistedChainCount, uint256 localPoolCount, uint256 remotePoolCount )
```

**Line 1228:** [external, view]
```solidity
function getMultiVEStatus() external view returns ( address feeContract_ )
```

**Line 1237:** [external, view]
```solidity
function userBaselineIndex(address user) external view returns (uint128)
```

**Line 1242:** [external, view]
```solidity
function userFeeBaseline(address user) external view returns (uint128)
```

**Line 1247:** [external, view]
```solidity
function poolBaselineIndex(address pool) external view returns (uint128)
```

**Line 1252:** [external, view]
```solidity
function poolAccrued(address pool) external view returns (uint256)
```

---

## MockAeroToken
**File:** `MockContracts.sol`

### Functions

**Line 17:** [external]
```solidity
function mint(address to, uint256 amount) external
```

**Line 31:** [external]
```solidity
function mint(address to, uint256 amount) external
```

**Line 57:** [external]
```solidity
function createLock(address to, uint256 amount, bool permanent) external returns (uint256 tokenId)
```

**Line 67:** [external]
```solidity
function setVoted(uint256 tokenId, bool _voted) external
```

**Line 71:** [external]
```solidity
function unlockPermanent(uint256 tokenId) external
```

**Line 76:** [external]
```solidity
function merge(uint256 from, uint256 to) external
```

**Line 85:** [external]
```solidity
function depositFor(uint256 tokenId, uint256 amount) external
```

**Line 89:** [internal]
```solidity
function _update(address to, uint256 tokenId, address auth) internal override returns (address)
```

**Line 119:** [external]
```solidity
function setBribeToken(address _bribe) external
```

**Line 123:** [external]
```solidity
function setGauge(address pool, address gauge) external
```

**Line 129:** [external]
```solidity
function setGaugeAlive(address pool, bool alive) external
```

**Line 133:** [external]
```solidity
function setFeeAmount(uint256 amount) external
```

**Line 137:** [external]
```solidity
function setBribeAmount(uint256 amount) external
```

**Line 141:** [external]
```solidity
function vote(uint256 tokenId, address[] calldata pools, uint256[] calldata weights) external
```

**Line 151:** [external]
```solidity
function claimFees(address[] calldata, address[][] calldata, uint256) external
```

**Line 158:** [external]
```solidity
function claimBribes(address[] calldata, address[][] calldata, uint256) external
```

**Line 165:** [external, pure]
```solidity
function length() external pure returns (uint256)
```

**Line 169:** [external, view]
```solidity
function getLastVote() external view returns (address[] memory, uint256[] memory)
```

**Line 173:** [external, view]
```solidity
function getTotalWeight() external view returns (uint256)
```

**Line 190:** [external]
```solidity
function castVote(uint256 proposalId, uint8 support) external
```

**Line 205:** [external]
```solidity
function mint(address to, uint256 amount) external
```

**Line 239:** [external]
```solidity
function receiveMetaIncentives(uint256 amount) external
```

**Line 246:** [external]
```solidity
function receiveCTokenIncentives(uint256 amount) external
```

**Line 253:** [external]
```solidity
function receiveFees(uint256 amount) external
```

**Line 260:** [external, view]
```solidity
function getBalances() external view returns (uint256 metaBalance, uint256 aeroBalance)
```

**Line 265:** [external, view]
```solidity
function getTotalReceived() external view returns (uint256 metaTotal, uint256 aeroTotal)
```

---

## MockLPGauge
**File:** `MockLPGauge.sol`

### Functions

**Line 66:** [external]
```solidity
function notifyRewardAmount(address token, uint256 amount) external
```

**Line 87:** [external]
```solidity
function deposit(uint256 amount) external
```

**Line 102:** [external]
```solidity
function withdraw(uint256 amount) external
```

**Line 118:** [external]
```solidity
function getReward(address account) external
```

**Line 135:** [internal]
```solidity
function _updateRewards(address account) internal
```

**Line 151:** [external, view]
```solidity
function earned(address account) external view returns (uint256 metaEarned)
```

**Line 164:** [external, view]
```solidity
function getTotalNotified() external view returns (uint256 totalMeta)
```

**Line 171:** [external, view]
```solidity
function getRewardBalance() external view returns (uint256 metaBalance)
```

---

## RToken
**File:** `RToken.sol`

### Functions

**Line 48:** [public, pure]
```solidity
function decimals() public pure override returns (uint8)
```

**Line 60:** [external]
```solidity
function setSplitter(address _splitter) external onlyOwner
```

**Line 81:** [external]
```solidity
function mint(address to, uint256 amount) external onlySplitter
```

---

## VToken
**File:** `VToken.sol`

### Functions

**Line 105:** [public, pure]
```solidity
function decimals() public pure override returns (uint8)
```

**Line 117:** [external]
```solidity
function setSplitter(address _splitter) external onlyOwner
```

**Line 124:** [external]
```solidity
function setLiquidation(address _liquidation) external onlyOwner
```

**Line 137:** [external]
```solidity
function configureVotingStorage(uint256 maxPools, uint256 totalSupply) external onlyOwner
```

**Line 170:** [external]
```solidity
function mint(address to, uint256 amount) external onlySplitter
```

**Line 179:** [external]
```solidity
function burn(address from, uint256 amount) external onlySplitter
```

**Line 194:** [external]
```solidity
function vote(address pool, uint256 amount) external nonReentrant
```

**Line 246:** [external]
```solidity
function votePassive(uint256 amount) external nonReentrant
```

**Line 298:** [external, view]
```solidity
function getAggregatedVotes() external view returns ( uint256[] memory weights )
```

**Line 356:** [external]
```solidity
function resetVotesForNewEpoch() external
```

**Line 371:** [internal, pure]
```solidity
function _quickSort( uint256[] memory weights, int256 left, int256 right ) internal pure
```

**Line 407:** [external]
```solidity
function confirmLiquidation(uint256 amount) external nonReentrant
```

**Line 431:** [public, view]
```solidity
function unlockedBalanceOf(address account) public view returns (uint256)
```

**Line 449:** [external, view]
```solidity
function isLocked(address account) external view returns (bool)
```

**Line 456:** [external, view]
```solidity
function getTotalVotedPools() external view returns (uint256)
```

**Line 465:** [external, view]
```solidity
function getPoolVotes(address pool) external view returns (uint256)
```

**Line 480:** [internal]
```solidity
function _update(address from, address to, uint256 amount) internal virtual override
```

---

## VeAeroBribes
**File:** `VeAeroBribes.sol`

### Functions

**Line 105:** [external]
```solidity
function snapshotForBribes() external
```

**Line 147:** [external]
```solidity
function claimBribes(address[] calldata tokens) external
```

**Line 201:** [external]
```solidity
function sweepUnclaimedBribes(address[] calldata tokens) external
```

**Line 231:** [external, view]
```solidity
function canSnapshot(address user) external view returns (bool)
```

**Line 247:** [external, view]
```solidity
function pendingBribes(address user, address token) external view returns (uint256)
```

**Line 281:** [external, view]
```solidity
function currentEpoch() external view returns (uint256)
```

**Line 282:** [external, view]
```solidity
function votingEndTime() external view returns (uint256)
```

**Line 283:** [external, view]
```solidity
function epochEndTime() external view returns (uint256)
```

**Line 284:** [external, view]
```solidity
function totalVLockedForVoting() external view returns (uint256)
```

**Line 285:** [external, view]
```solidity
function isWhitelistedBribe(address token) external view returns (bool)
```

**Line 286:** [external, view]
```solidity
function bribeWhitelistEpoch(address token) external view returns (uint256)
```

**Line 287:** [external, view]
```solidity
function isLiquidationActive() external view returns (bool)
```

**Line 288:** [external]
```solidity
function pullBribeToken(address token, address to, uint256 amount) external
```

---

## VeAeroLiquidation
**File:** `VeAeroLiquidation.sol`

### Functions

**Line 119:** [external]
```solidity
function recordCLock(address user, uint256 amount) external
```

**Line 155:** [external]
```solidity
function recordVConfirmation(address user, uint256 amount) external
```

**Line 175:** [external]
```solidity
function resolveCVote(uint256 currentEpoch) external
```

**Line 201:** [external]
```solidity
function resolveVConfirm(uint256 currentEpoch) external
```

**Line 230:** [external]
```solidity
function withdrawFailedLiquidation() external
```

**Line 260:** [external]
```solidity
function markClosed() external
```

**Line 276:** [external, view]
```solidity
function isLiquidationApproved() external view returns (bool)
```

**Line 285:** [external, view]
```solidity
function getLiquidationApprovedTime() external view returns (uint256)
```

**Line 293:** [external, view]
```solidity
function getUserCLocked(address user) external view returns (uint256)
```

**Line 301:** [external, view]
```solidity
function getTotalCLocked() external view returns (uint256)
```

**Line 308:** [external, view]
```solidity
function getLiquidationStatus( uint256 epochEndTime ) external view returns ( LiquidationPhase phase, uint256 cLockedPercent, uint256 vLockedPercent, uint256 cTargetPercent, uint256 vTargetPercent, uint256 timeRemaining )
```

**Line 350:** [external, view]
```solidity
function daysRemainingInCVote() external view returns (uint256)
```

---

## VeAeroSplitter
**File:** `VeAeroSplitter.sol`

### Functions

**Line 251:** [internal, view]
```solidity
function _checkNotInLiquidation() internal view
```

**Line 262:** [internal]
```solidity
function _ensureCurrentEpoch() internal
```

**Line 318:** [external]
```solidity
function resetEpoch() external notInLiquidation
```

**Line 323:** [internal]
```solidity
function _resetEpoch() internal
```

**Line 345:** [external, pure]
```solidity
function onERC721Received( address, uint256, bytes calldata ) external pure override returns (bytes4)
```

**Line 358:** [external]
```solidity
function depositVeAero(uint256 tokenId) external nonReentrant notInLiquidation ensureCurrentEpoch
```

**Line 422:** [external]
```solidity
function consolidatePending() external nonReentrant notInLiquidation
```

**Line 430:** [internal]
```solidity
function _consolidateAll() internal
```

**Line 461:** [external]
```solidity
function executeGaugeVote() external nonReentrant notInLiquidation
```

**Line 503:** [external]
```solidity
function recordEmissionsVote( int8 choice, uint256 amount ) external ensureCurrentEpoch
```

**Line 521:** [external]
```solidity
function executeEmissionsVote(uint256 proposalId) external nonReentrant
```

**Line 549:** [external]
```solidity
function collectFees( address[][] calldata tokens ) external nonReentrant notInLiquidation
```

**Line 580:** [external]
```solidity
function claimFees() external nonReentrant returns (uint256 owed)
```

**Line 598:** [external, view]
```solidity
function pendingFees(address user) external view returns (uint256)
```

**Line 611:** [external]
```solidity
function collectMeta() external nonReentrant notInLiquidation
```

**Line 628:** [external]
```solidity
function claimMeta() external nonReentrant returns (uint256 owed)
```

**Line 647:** [external, view]
```solidity
function pendingMeta(address user) external view returns (uint256)
```

**Line 660:** [external]
```solidity
function updateRebaseIndex() external notInLiquidation
```

**Line 664:** [internal]
```solidity
function _updateRebaseIndex() internal
```

**Line 678:** [external]
```solidity
function claimRebase() external nonReentrant notInLiquidation
```

**Line 682:** [internal]
```solidity
function _claimRebaseInternal(address user) internal returns (uint256 netAmount)
```

**Line 726:** [external, view]
```solidity
function pendingRebase(address user) external view returns (uint256)
```

**Line 739:** [external, view]
```solidity
function getAllPendingClaims(address user) external view returns ( uint256 feeAmount, uint256 metaAmount )
```

**Line 778:** [external]
```solidity
function onCTokenTransfer( address to, uint256 amount ) external
```

**Line 866:** [external]
```solidity
function collectBribes( address[][] calldata tokens ) external nonReentrant notInLiquidation
```

**Line 901:** [external]
```solidity
function pullBribeToken(address token, address to, uint256 amount) external
```

**Line 926:** [external]
```solidity
function claimRTokens() external nonReentrant
```

**Line 952:** [external]
```solidity
function sweepUnclaimedReceipts() external
```

**Line 977:** [external]
```solidity
function withdrawAllNFTs() external
```

**Line 998:** [external]
```solidity
function setAerodromeVoter(address _voter) external onlyOwner
```

**Line 1004:** [external]
```solidity
function setEpochGovernor(address _governor) external onlyOwner
```

**Line 1014:** [external]
```solidity
function setVoteLib(address _voteLib) external onlyOwner
```

**Line 1025:** [external, view]
```solidity
function isDepositWindowOpen() external view returns (bool)
```

**Line 1033:** [external, view]
```solidity
function isLiquidationActive() external view returns (bool)
```

**Line 1041:** [internal, view]
```solidity
function _isDepositWindowOpen() internal view returns (bool)
```

**Line 1056:** [internal, view]
```solidity
function _getNextThursday() internal view returns (uint256)
```

---

## VeAeroSplitter
**File:** `VeAeroSplitter_split.sol`

### Functions

**Line 273:** [internal, view]
```solidity
function _checkNotInLiquidation() internal view
```

**Line 284:** [internal]
```solidity
function _ensureCurrentEpoch() internal
```

**Line 343:** [external]
```solidity
function resetEpoch() external notInLiquidation
```

**Line 348:** [internal]
```solidity
function _resetEpoch() internal
```

**Line 372:** [external, pure]
```solidity
function onERC721Received( address, uint256, bytes calldata ) external pure override returns (bytes4)
```

**Line 385:** [external]
```solidity
function depositVeAero(uint256 tokenId) external nonReentrant notInLiquidation ensureCurrentEpoch
```

**Line 449:** [external]
```solidity
function consolidatePending() external nonReentrant notInLiquidation
```

**Line 457:** [internal]
```solidity
function _consolidateAll() internal
```

**Line 484:** [external]
```solidity
function recordGaugeVote( address pool, uint256 amount ) external notInLiquidation ensureCurrentEpoch
```

**Line 513:** [external]
```solidity
function recordPassiveVote( uint256 amount ) external notInLiquidation ensureCurrentEpoch
```

**Line 526:** [external]
```solidity
function executeGaugeVote() external nonReentrant notInLiquidation
```

**Line 573:** [internal]
```solidity
function _executeSingleNFTVote( uint256[] memory weights, uint256 count ) internal
```

**Line 596:** [internal]
```solidity
function _executeMultiNFTVote( uint256[] memory weights, uint256 count ) internal
```

**Line 644:** [internal]
```solidity
function _splitMasterNFT( ) internal returns (uint256[] memory childNftIds)
```

**Line 687:** [internal]
```solidity
function _mergeAllNFTs(uint256[] memory childNftIds) internal returns (uint256)
```

**Line 705:** [internal, view]
```solidity
function _getAllVotedPools() internal view returns ( uint256[] memory weights, uint256 count )
```

**Line 739:** [internal, pure]
```solidity
function _quickSort( uint256[] memory weights, int256 left, int256 right ) internal pure
```

**Line 771:** [external]
```solidity
function recordEmissionsVote( int8 choice, uint256 amount ) external ensureCurrentEpoch
```

**Line 789:** [external]
```solidity
function executeEmissionsVote(uint256 proposalId) external nonReentrant
```

**Line 817:** [external]
```solidity
function collectFees( address[][] calldata tokens ) external nonReentrant notInLiquidation
```

**Line 848:** [external]
```solidity
function claimFees() external nonReentrant returns (uint256 owed)
```

**Line 866:** [external, view]
```solidity
function pendingFees(address user) external view returns (uint256)
```

**Line 879:** [external]
```solidity
function collectMeta() external nonReentrant notInLiquidation
```

**Line 896:** [external]
```solidity
function claimMeta() external nonReentrant returns (uint256 owed)
```

**Line 915:** [external, view]
```solidity
function pendingMeta(address user) external view returns (uint256)
```

**Line 928:** [external]
```solidity
function updateRebaseIndex() external notInLiquidation
```

**Line 932:** [internal]
```solidity
function _updateRebaseIndex() internal
```

**Line 946:** [external]
```solidity
function claimRebase() external nonReentrant notInLiquidation
```

**Line 950:** [internal]
```solidity
function _claimRebaseInternal(address user) internal returns (uint256 netAmount)
```

**Line 994:** [external, view]
```solidity
function pendingRebase(address user) external view returns (uint256)
```

**Line 1007:** [external, view]
```solidity
function getAllPendingClaims(address user) external view returns ( uint256 feeAmount, uint256 metaAmount )
```

**Line 1046:** [external]
```solidity
function onCTokenTransfer( address to, uint256 amount ) external
```

**Line 1134:** [external]
```solidity
function collectBribes( address[][] calldata tokens ) external nonReentrant notInLiquidation
```

**Line 1169:** [external]
```solidity
function pullBribeToken(address token, address to, uint256 amount) external
```

**Line 1194:** [external]
```solidity
function claimRTokens() external nonReentrant
```

**Line 1220:** [external]
```solidity
function sweepUnclaimedReceipts() external
```

**Line 1245:** [external]
```solidity
function withdrawAllNFTs() external
```

**Line 1266:** [external]
```solidity
function setAerodromeVoter(address _voter) external onlyOwner
```

**Line 1272:** [external]
```solidity
function setEpochGovernor(address _governor) external onlyOwner
```

**Line 1282:** [external]
```solidity
function setVoteLib(address _voteLib) external onlyOwner
```

**Line 1290:** [external]
```solidity
function updateSplitStatus() external
```

**Line 1303:** [external, view]
```solidity
function isDepositWindowOpen() external view returns (bool)
```

**Line 1311:** [external, view]
```solidity
function isLiquidationActive() external view returns (bool)
```

**Line 1319:** [internal, view]
```solidity
function _isDepositWindowOpen() internal view returns (bool)
```

**Line 1334:** [internal, view]
```solidity
function _getNextThursday() internal view returns (uint256)
```

**Line 1350:** [internal]
```solidity
function _configureStorage() internal
```

**Line 1372:** [internal]
```solidity
function _checkAndExpandStorage() internal
```

---

## VoteLib
**File:** `VoteLib.sol`

### Functions

**Line 80:** [external, pure]
```solidity
function distributeVotes( uint256[] memory weights ) external pure returns (NFTVote[] memory nftVotes)
```

**Line 117:** [internal, pure]
```solidity
function _distributeMultiNFT( uint256[] memory weights, uint256 numPools ) internal pure returns (NFTVote[] memory nftVotes)
```

**Line 179:** [external, pure]
```solidity
function calculateNFTsNeeded(uint256 numPools) external pure returns (uint256)
```

**Line 190:** [external, view]
```solidity
function previewDistribution(uint256 numPools) external pure returns (uint256[] memory poolsPerNFT)
```

**Line 208:** [external, pure]
```solidity
function version() external pure returns (string memory)
```

---

## Voter
**File:** `Voter.sol`

### Functions

**Line 107:** [external, pure]
```solidity
function epochStart(uint256 _timestamp) external pure returns (uint256)
```

**Line 111:** [external, pure]
```solidity
function epochNext(uint256 _timestamp) external pure returns (uint256)
```

**Line 115:** [external, pure]
```solidity
function epochVoteStart(uint256 _timestamp) external pure returns (uint256)
```

**Line 119:** [external, pure]
```solidity
function epochVoteEnd(uint256 _timestamp) external pure returns (uint256)
```

**Line 124:** [external]
```solidity
function initialize(address[] calldata _tokens, address _minter) external
```

**Line 134:** [public]
```solidity
function setGovernor(address _governor) public
```

**Line 141:** [public]
```solidity
function setEpochGovernor(address _epochGovernor) public
```

**Line 148:** [public]
```solidity
function setEmergencyCouncil(address _council) public
```

**Line 155:** [external]
```solidity
function setMaxVotingNum(uint256 _maxVotingNum) external
```

**Line 163:** [external]
```solidity
function reset(uint256 _tokenId) external onlyNewEpoch(_tokenId) nonReentrant
```

**Line 168:** [internal]
```solidity
function _reset(uint256 _tokenId) internal
```

**Line 194:** [external]
```solidity
function poke(uint256 _tokenId) external nonReentrant
```

**Line 200:** [internal]
```solidity
function _poke(uint256 _tokenId, uint256 _weight) internal
```

**Line 211:** [internal]
```solidity
function _vote(uint256 _tokenId, uint256 _weight, address[] memory _poolVote, uint256[] memory _weights) internal
```

**Line 251:** [external]
```solidity
function vote( address[] calldata _poolVote, uint256[] calldata _weights ) external onlyNewEpoch(_tokenId) nonReentrant
```

**Line 270:** [external]
```solidity
function depositManaged(uint256 _tokenId, uint256 _mTokenId) external nonReentrant onlyNewEpoch(_tokenId)
```

**Line 283:** [external]
```solidity
function withdrawManaged(uint256 _tokenId) external nonReentrant onlyNewEpoch(_tokenId)
```

**Line 301:** [external]
```solidity
function whitelistToken(address _token, bool _bool) external
```

**Line 306:** [internal]
```solidity
function _whitelistToken(address _token, bool _bool) internal
```

**Line 312:** [external]
```solidity
function whitelistNFT(uint256 _tokenId, bool _bool) external
```

**Line 320:** [external]
```solidity
function createGauge(address _poolFactory, address _pool) external nonReentrant returns (address)
```

**Line 381:** [external]
```solidity
function killGauge(address _gauge) external
```

**Line 395:** [external]
```solidity
function reviveGauge(address _gauge) external
```

**Line 403:** [external, view]
```solidity
function length() external view returns (uint256)
```

**Line 408:** [external]
```solidity
function notifyRewardAmount(uint256 _amount) external
```

**Line 420:** [external]
```solidity
function updateFor(address[] memory _gauges) external
```

**Line 428:** [external]
```solidity
function updateFor(uint256 start, uint256 end) external
```

**Line 435:** [external]
```solidity
function updateFor(address _gauge) external
```

**Line 439:** [internal]
```solidity
function _updateFor(address _gauge) internal
```

**Line 461:** [external]
```solidity
function claimRewards(address[] memory _gauges) external
```

**Line 469:** [external]
```solidity
function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external
```

**Line 478:** [external]
```solidity
function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external
```

**Line 486:** [internal]
```solidity
function _distribute(address _gauge) internal
```

**Line 499:** [external]
```solidity
function distribute(uint256 _start, uint256 _finish) external nonReentrant
```

**Line 507:** [external]
```solidity
function distribute(address[] memory _gauges) external nonReentrant
```

---

## VotingEscrow
**File:** `VotingEscrow.sol`

### Functions

**Line 124:** [external]
```solidity
function createManagedLockFor(address _to) external nonReentrant returns (uint256 _mTokenId)
```

**Line 144:** [external]
```solidity
function depositManaged(uint256 _tokenId, uint256 _mTokenId) external nonReentrant
```

**Line 182:** [external]
```solidity
function withdrawManaged(uint256 _tokenId) external nonReentrant
```

**Line 229:** [external]
```solidity
function setAllowedManager(address _allowedManager) external
```

**Line 238:** [external]
```solidity
function setManagedState(uint256 _mTokenId, bool _state) external
```

**Line 255:** [external]
```solidity
function setTeam(address _team) external
```

**Line 261:** [external]
```solidity
function setArtProxy(address _proxy) external
```

**Line 268:** [external, view]
```solidity
function tokenURI(uint256 _tokenId) external view returns (string memory)
```

**Line 283:** [internal, view]
```solidity
function _ownerOf(uint256 _tokenId) internal view returns (address)
```

**Line 288:** [external, view]
```solidity
function ownerOf(uint256 _tokenId) external view returns (address)
```

**Line 293:** [external, view]
```solidity
function balanceOf(address _owner) external view returns (uint256)
```

**Line 310:** [external, view]
```solidity
function getApproved(uint256 _tokenId) external view returns (address)
```

**Line 315:** [external, view]
```solidity
function isApprovedForAll(address _owner, address _operator) external view returns (bool)
```

**Line 320:** [external, view]
```solidity
function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool)
```

**Line 324:** [internal, view]
```solidity
function _isApprovedOrOwner(address _spender, uint256 _tokenId) internal view returns (bool)
```

**Line 337:** [external]
```solidity
function approve(address _approved, uint256 _tokenId) external
```

**Line 354:** [external]
```solidity
function setApprovalForAll(address _operator, bool _approved) external
```

**Line 364:** [internal]
```solidity
function _transferFrom(address _from, address _to, uint256 _tokenId, address _sender) internal
```

**Line 384:** [external]
```solidity
function transferFrom(address _from, address _to, uint256 _tokenId) external
```

**Line 389:** [external]
```solidity
function safeTransferFrom(address _from, address _to, uint256 _tokenId) external
```

**Line 393:** [internal, view]
```solidity
function _isContract(address account) internal view returns (bool)
```

**Line 405:** [public]
```solidity
function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) public
```

**Line 432:** [external, view]
```solidity
function supportsInterface(bytes4 _interfaceID) external view returns (bool)
```

**Line 449:** [internal]
```solidity
function _addTokenToOwnerList(address _to, uint256 _tokenId) internal
```

**Line 458:** [internal]
```solidity
function _addTokenTo(address _to, uint256 _tokenId) internal
```

**Line 475:** [internal]
```solidity
function _mint(address _to, uint256 _tokenId) internal returns (bool)
```

**Line 489:** [internal]
```solidity
function _removeTokenFromOwnerList(address _from, uint256 _tokenId) internal
```

**Line 518:** [internal]
```solidity
function _removeTokenFrom(address _from, uint256 _tokenId) internal
```

**Line 530:** [internal]
```solidity
function _burn(uint256 _tokenId) internal
```

**Line 569:** [external, view]
```solidity
function locked(uint256 _tokenId) external view returns (LockedBalance memory)
```

**Line 574:** [external, view]
```solidity
function userPointHistory(uint256 _tokenId, uint256 _loc) external view returns (UserPoint memory)
```

**Line 579:** [external, view]
```solidity
function pointHistory(uint256 _loc) external view returns (GlobalPoint memory)
```

**Line 591:** [internal]
```solidity
function _checkpoint(uint256 _tokenId, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal
```

**Line 760:** [internal]
```solidity
function _depositFor( uint256 _value, uint256 _unlockTime, LockedBalance memory _oldLocked, DepositType _depositType ) internal
```

**Line 802:** [external]
```solidity
function checkpoint() external nonReentrant
```

**Line 807:** [external]
```solidity
function depositFor(uint256 _tokenId, uint256 _value) external nonReentrant
```

**Line 816:** [internal]
```solidity
function _createLock(uint256 _value, uint256 _lockDuration, address _to) internal returns (uint256)
```

**Line 831:** [external]
```solidity
function createLock(uint256 _value, uint256 _lockDuration) external nonReentrant returns (uint256)
```

**Line 836:** [external]
```solidity
function createLockFor(uint256 _value, uint256 _lockDuration, address _to) external nonReentrant returns (uint256)
```

**Line 840:** [internal]
```solidity
function _increaseAmountFor(uint256 _tokenId, uint256 _value, DepositType _depositType) internal
```

**Line 867:** [external]
```solidity
function increaseAmount(uint256 _tokenId, uint256 _value) external nonReentrant
```

**Line 873:** [external]
```solidity
function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external nonReentrant
```

**Line 892:** [external]
```solidity
function withdraw(uint256 _tokenId) external nonReentrant
```

**Line 921:** [external]
```solidity
function merge(uint256 _from, uint256 _to) external nonReentrant
```

**Line 966:** [external]
```solidity
function split( uint256 _amount ) external nonReentrant returns (uint256 _tokenId1, uint256 _tokenId2)
```

**Line 1008:** [private]
```solidity
function _createSplitNFT(address _to, LockedBalance memory _newLocked) private returns (uint256 _tokenId)
```

**Line 1016:** [external]
```solidity
function toggleSplit(address _account, bool _bool) external
```

**Line 1022:** [external]
```solidity
function lockPermanent(uint256 _tokenId) external
```

**Line 1043:** [external]
```solidity
function unlockPermanent(uint256 _tokenId) external
```

**Line 1067:** [internal, view]
```solidity
function _balanceOfNFTAt(uint256 _tokenId, uint256 _t) internal view returns (uint256)
```

**Line 1071:** [internal, view]
```solidity
function _supplyAt(uint256 _timestamp) internal view returns (uint256)
```

**Line 1076:** [public, view]
```solidity
function balanceOfNFT(uint256 _tokenId) public view returns (uint256)
```

**Line 1082:** [external, view]
```solidity
function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256)
```

**Line 1087:** [external, view]
```solidity
function totalSupply() external view returns (uint256)
```

**Line 1092:** [external, view]
```solidity
function totalSupplyAt(uint256 _timestamp) external view returns (uint256)
```

**Line 1104:** [external]
```solidity
function setVoterAndDistributor(address _voter, address _distributor) external
```

**Line 1111:** [external]
```solidity
function voting(uint256 _tokenId, bool _voted) external
```

**Line 1141:** [external, view]
```solidity
function delegates(uint256 delegator) external view returns (uint256)
```

**Line 1146:** [external, view]
```solidity
function checkpoints(uint256 _tokenId, uint48 _index) external view returns (Checkpoint memory)
```

**Line 1151:** [external, view]
```solidity
function getPastVotes(address _account, uint256 _tokenId, uint256 _timestamp) external view returns (uint256)
```

**Line 1156:** [external, view]
```solidity
function getPastTotalSupply(uint256 _timestamp) external view returns (uint256)
```

**Line 1164:** [internal]
```solidity
function _checkpointDelegator(uint256 _delegator, uint256 _delegatee, address _owner) internal
```

**Line 1176:** [internal]
```solidity
function _checkpointDelegatee(uint256 _delegatee, uint256 balance_, bool _increase) internal
```

**Line 1182:** [internal]
```solidity
function _delegate(uint256 _delegator, uint256 _delegatee) internal
```

**Line 1199:** [external]
```solidity
function delegate(uint256 delegator, uint256 delegatee) external
```

**Line 1205:** [external]
```solidity
function delegateBySig( uint256 delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s ) external
```

**Line 1242:** [external, view]
```solidity
function clock() external view returns (uint48)
```

**Line 1247:** [external, pure]
```solidity
function CLOCK_MODE() external pure returns (string memory)
```

---

## VotingTest
**File:** `VotingTest.sol`

### Functions

**Line 12:** [public]
```solidity
function setUp() public override
```

**Line 26:** [public]
```solidity
function test_GaugeVote_Basic() public
```

**Line 35:** [public]
```solidity
function test_GaugeVote_MustBeWholeTokens() public
```

**Line 41:** [public]
```solidity
function test_GaugeVote_MultiplePoolsSameUser() public
```

**Line 51:** [public]
```solidity
function test_GaugeVote_MultipleUsersToSamePool() public
```

**Line 59:** [public]
```solidity
function test_GaugeVote_TracksTotal() public
```

**Line 69:** [public]
```solidity
function test_GaugeVote_FailsBeforeVotingWindow() public
```

**Line 78:** [public]
```solidity
function test_GaugeVote_FailsAfterVotingWindow() public
```

**Line 86:** [public]
```solidity
function test_GaugeVote_FailsInvalidGauge() public
```

**Line 98:** [public]
```solidity
function test_PassiveVote_Basic() public
```

**Line 109:** [public]
```solidity
function test_PassiveVote_MustBeWholeTokens() public
```

**Line 115:** [public]
```solidity
function test_PassiveVote_LocksTokens() public
```

**Line 122:** [public]
```solidity
function test_PassiveVote_ProportionalDistribution() public
```

**Line 145:** [public]
```solidity
function test_PassiveVote_AllPassive_Reverts() public
```

**Line 158:** [public]
```solidity
function test_PassiveVote_ZeroAmount_Reverts() public
```

**Line 168:** [public]
```solidity
function test_EmissionsVote_Decrease() public
```

**Line 177:** [public]
```solidity
function test_EmissionsVote_Hold() public
```

**Line 186:** [public]
```solidity
function test_EmissionsVote_Increase() public
```

**Line 195:** [public]
```solidity
function test_EmissionsVote_MustBeWholeTokens() public
```

**Line 201:** [public]
```solidity
function test_EmissionsVote_Execute_DecreaseWins() public
```

**Line 218:** [public]
```solidity
function test_EmissionsVote_Execute_DecreaseWinsTies() public
```

**Line 238:** [public]
```solidity
function test_ExecuteVote_Basic() public
```

**Line 250:** [public]
```solidity
function test_ExecuteVote_FailsTwice() public
```

**Line 262:** [public]
```solidity
function test_ExecuteVote_FailsBeforeWindow() public
```

**Line 270:** [public]
```solidity
function test_ExecuteVote_FailsAfterWindow() public
```

**Line 280:** [public]
```solidity
function test_ExecuteVote_ResetsNextEpoch() public
```

**Line 299:** [public]
```solidity
function test_Vote_UnlocksAfterEpoch() public
```

**Line 311:** [public]
```solidity
function test_Vote_CannotTransferLocked() public
```

**Line 320:** [public]
```solidity
function test_Vote_CanTransferUnlocked() public
```

---
