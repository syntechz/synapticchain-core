# SynTree Contract Spec

## Overview
Decentralized reforestation tracking dApp. Users submit tree planting evidence with photo and geolocation. Submissions enter a verification queue. Once a verifier confirms the tree exists and is alive, the planter receives an NFT and 50 SYN reward.

---

## State Variables

```solidity
// Access control
address public owner;
mapping(address => bool) public verifiers;

// Token integration
address public synToken;
address public treeNFTContract;

// Reward parameters
uint256 public constant TREE_REWARD = 50 * 10**18;   // 50 SYN per verified tree
uint256 public verificationTimeout = 7 days;
uint256 public maxPendingPerUser = 10;

// Tree record struct
struct Tree {
    uint256 treeId;
    address planter;
    string photoHash;
    int256 lat;            // * 10**6
    int256 lng;            // * 10**6
    string species;
    uint256 plantedAt;
    uint256 verifiedAt;
    bool verified;
    address verifier;
    uint256 tokenId;
    TreeStatus status;
}

enum TreeStatus {
    Pending,      // Submitted, awaiting verification
    Verified,     // Approved, reward + NFT issued
    Rejected,     // Failed verification
    Expired       // Timed out (>7 days)
}

// Storage
mapping(uint256 => Tree) public trees;
mapping(address => uint256[]) public planterTrees;
mapping(address => uint256) public pendingCount;
mapping(string => bool) public photoHashUsed;
mapping(string => uint256) public speciesRewardMultiplier;  // Optional: rare species bonus

uint256 public treeCounter;
uint256 public totalTreesVerified;
uint256 public totalRewardsDistributed;

// Verification queue (simple array for iteration)
uint256[] public pendingQueue;
mapping(uint256 => uint256) public queueIndex;  // treeId => index in pendingQueue
```

---

## Events

```solidity
event TreePlanted(
    uint256 indexed treeId,
    address indexed planter,
    string photoHash,
    int256 lat,
    int256 lng,
    string species,
    uint256 timestamp
);

event TreeVerified(
    uint256 indexed treeId,
    address indexed verifier,
    address indexed planter,
    uint256 rewardAmount,
    uint256 tokenId
);

event TreeRejected(
    uint256 indexed treeId,
    address indexed verifier,
    string reason
);

event TreeExpired(uint256 indexed treeId);
event SpeciesMultiplierSet(string species, uint256 multiplier);
event VerifierAdded(address indexed verifier);
event VerifierRemoved(address indexed verifier);
```

---

## Functions

### `plantTree(string calldata photoHash, int256 lat, int256 lng, string calldata species)`

```solidity
function plantTree(
    string calldata photoHash,
    int256 lat,
    int256 lng,
    string calldata species
) external returns (uint256 treeId) {
    require(bytes(photoHash).length > 0, "Photo hash required");
    require(!photoHashUsed[photoHash], "Photo already used");
    require(lat >= -90000000 && lat <= 90000000, "Invalid latitude");
    require(lng >= -180000000 && lng <= 180000000, "Invalid longitude");
    require(bytes(species).length > 0 && bytes(species).length <= 64, "Invalid species name");
    require(pendingCount[msg.sender] < maxPendingPerUser, "Too many pending trees");
    
    treeCounter++;
    treeId = treeCounter;
    
    trees[treeId] = Tree({
        treeId: treeId,
        planter: msg.sender,
        photoHash: photoHash,
        lat: lat,
        lng: lng,
        species: species,
        plantedAt: block.timestamp,
        verifiedAt: 0,
        verified: false,
        verifier: address(0),
        tokenId: 0,
        status: TreeStatus.Pending
    });
    
    planterTrees[msg.sender].push(treeId);
    pendingCount[msg.sender]++;
    photoHashUsed[photoHash] = true;
    
    // Add to pending queue
    queueIndex[treeId] = pendingQueue.length;
    pendingQueue.push(treeId);
    
    emit TreePlanted(treeId, msg.sender, photoHash, lat, lng, species, block.timestamp);
}
```

### `verifyTree(uint256 treeId)`

```solidity
function verifyTree(uint256 treeId) external onlyVerifier {
    Tree storage tree = trees[treeId];
    require(tree.planter != address(0), "Tree not found");
    require(tree.status == TreeStatus.Pending, "Tree not pending");
    require(block.timestamp <= tree.plantedAt + verificationTimeout, "Verification window expired");
    
    // Mark verified
    tree.verified = true;
    tree.verifiedAt = block.timestamp;
    tree.verifier = msg.sender;
    tree.status = TreeStatus.Verified;
    
    // Calculate reward (species multiplier optional)
    uint256 reward = TREE_REWARD;
    uint256 multiplier = speciesRewardMultiplier[tree.species];
    if (multiplier > 0) {
        reward = reward * multiplier / 100;  // multiplier is in basis points (100 = 1x)
    }
    
    // Mint NFT
    uint256 tokenId = ITreeNFT(treeNFTContract).mint(tree.planter, treeId, tree.species);
    tree.tokenId = tokenId;
    
    // Transfer reward
    require(IERC20(synToken).transfer(tree.planter, reward), "Reward transfer failed");
    
    // Update stats
    totalTreesVerified++;
    totalRewardsDistributed += reward;
    pendingCount[tree.planter]--;
    
    // Remove from pending queue
    _removeFromQueue(treeId);
    
    emit TreeVerified(treeId, msg.sender, tree.planter, reward, tokenId);
}
```

### `rejectTree(uint256 treeId, string calldata reason)`

```solidity
function rejectTree(uint256 treeId, string calldata reason) external onlyVerifier {
    Tree storage tree = trees[treeId];
    require(tree.planter != address(0), "Tree not found");
    require(tree.status == TreeStatus.Pending, "Tree not pending");
    
    tree.status = TreeStatus.Rejected;
    tree.verifier = msg.sender;
    pendingCount[tree.planter]--;
    
    _removeFromQueue(treeId);
    
    emit TreeRejected(treeId, msg.sender, reason);
}
```

### `expireOldTrees()` — Callable by anyone (gas incentive)

```solidity
function expireOldTrees(uint256[] calldata treeIds) external {
    for (uint i = 0; i < treeIds.length; i++) {
        uint256 treeId = treeIds[i];
        Tree storage tree = trees[treeId];
        
        if (tree.status == TreeStatus.Pending && 
            block.timestamp > tree.plantedAt + verificationTimeout) {
            
            tree.status = TreeStatus.Expired;
            pendingCount[tree.planter]--;
            _removeFromQueue(treeId);
            
            emit TreeExpired(treeId);
        }
    }
}
```

### Queue Management (Internal)

```solidity
function _removeFromQueue(uint256 treeId) internal {
    uint256 index = queueIndex[treeId];
    uint256 lastIndex = pendingQueue.length - 1;
    uint256 lastTreeId = pendingQueue[lastIndex];
    
    pendingQueue[index] = lastTreeId;
    queueIndex[lastTreeId] = index;
    pendingQueue.pop();
    delete queueIndex[treeId];
}

function getPendingQueue() external view returns (uint256[] memory) {
    return pendingQueue;
}

function getPlanterTrees(address planter) external view returns (uint256[] memory) {
    return planterTrees[planter];
}
```

### Admin

```solidity
modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
}

modifier onlyVerifier() {
    require(verifiers[msg.sender] || msg.sender == owner, "Not verifier");
    _;
}

function addVerifier(address verifier) external onlyOwner {
    verifiers[verifier] = true;
    emit VerifierAdded(verifier);
}

function removeVerifier(address verifier) external onlyOwner {
    verifiers[verifier] = false;
    emit VerifierRemoved(verifier);
}

function setSpeciesMultiplier(string calldata species, uint256 multiplier) external onlyOwner {
    // multiplier in basis points: 100 = 1x, 150 = 1.5x, 200 = 2x
    speciesRewardMultiplier[species] = multiplier;
    emit SpeciesMultiplierSet(species, multiplier);
}

function setMaxPending(uint256 max) external onlyOwner {
    maxPendingPerUser = max;
}

function setTokenAddresses(address _syn, address _nft) external onlyOwner {
    synToken = _syn;
    treeNFTContract = _nft;
}
```

---

## Reward Calculation

- **Standard verification:** 50 SYN
- **Species bonus (optional):** multiplier * 50 SYN
  - Example: Rare species with 150 multiplier = 75 SYN

---

## Deployment Checklist

- [ ] Deploy SYN token
- [ ] Deploy TreeNFT (ERC721 with metadata URI per tree)
- [ ] Deploy SynTree with owner = deployer
- [ ] Call `setTokenAddresses(synToken, treeNFT)`
- [ ] Fund contract with SYN for rewards
- [ ] Add verifier team addresses
- [ ] (Optional) Set species multipliers for rare trees
