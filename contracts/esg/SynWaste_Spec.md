# SynWaste Contract Spec

## Overview
Waste collection and recycling incentive dApp. Users submit waste collection evidence (photo, type, weight, location). Registered partner organizations verify submissions and approve SYN rewards based on waste type and weight.

---

## State Variables

```solidity
// Access control
address public owner;
mapping(address => bool) public verifiers;
mapping(address => bool) public partnerOrgs;

// Token integration
address public synToken;

// Reward rates per waste type (SYN per kg, with 18 decimals)
// Example: 1 * 10**18 = 1 SYN per kg
mapping(bytes32 => uint256) public rewardRates;  // keccak256(wasteType) => rate
bytes32[] public wasteTypes;  // Registered waste type hashes

// Daily limits
uint256 public maxDailySubmissions = 5;       // Per user per day
uint256 public maxDailyReward = 100 * 10**18; // 100 SYN cap per day per user

// Submission struct
struct WasteReport {
    uint256 reportId;
    address reporter;
    string photoHash;
    bytes32 wasteType;       // keccak256 hash of type string
    uint256 weight;          // Weight in grams (to avoid decimals)
    int256 lat;
    int256 lng;
    uint256 submittedAt;
    bool verified;
    address verifier;
    uint256 rewardAmount;
    string partnerNotes;     // Optional verification notes
}

// Storage
mapping(uint256 => WasteReport) public reports;
mapping(address => uint256[]) public reporterReports;
mapping(address => mapping(uint256 => uint256)) public dailySubmissions;  // user => day => count
mapping(address => mapping(uint256 => uint256)) public dailyRewards;      // user => day => total
mapping(string => bool) public photoHashUsed;

uint256 public reportCounter;
uint256 public totalVerified;
uint256 public totalRewardsDistributed;
uint256 public totalWeightCollected;  // Total grams across all verified reports
```

---

## Events

```solidity
event WasteSubmitted(
    uint256 indexed reportId,
    address indexed reporter,
    bytes32 wasteType,
    uint256 weight,
    int256 lat,
    int256 lng,
    string photoHash
);

event WasteVerified(
    uint256 indexed reportId,
    address indexed verifier,
    address indexed reporter,
    uint256 rewardAmount
);

event WasteRejected(
    uint256 indexed reportId,
    address indexed verifier,
    string reason
);

event RewardRateSet(string wasteType, uint256 ratePerKg);
event PartnerOrgAdded(address indexed org);
event PartnerOrgRemoved(address indexed org);
event DailyLimitsUpdated(uint256 maxSubmissions, uint256 maxReward);
```

---

## Functions

### `submitWaste(string calldata photoHash, string calldata wasteType, uint256 weight, int256 lat, int256 lng)`

```solidity
function submitWaste(
    string calldata photoHash,
    string calldata wasteType,
    uint256 weight,      // Weight in grams
    int256 lat,
    int256 lng
) external returns (uint256 reportId) {
    require(bytes(photoHash).length > 0, "Photo hash required");
    require(!photoHashUsed[photoHash], "Photo already used");
    require(bytes(wasteType).length > 0, "Waste type required");
    require(weight > 0, "Weight must be positive");
    require(weight <= 100000000, "Weight too high (max 100 tons)");  // 100,000,000g = 100 tons
    require(lat >= -90000000 && lat <= 90000000, "Invalid latitude");
    require(lng >= -180000000 && lng <= 180000000, "Invalid longitude");
    
    bytes32 typeHash = keccak256(bytes(wasteType));
    require(rewardRates[typeHash] > 0, "Waste type not registered");
    
    // Daily limits check
    uint256 today = block.timestamp / 86400;
    require(dailySubmissions[msg.sender][today] < maxDailySubmissions, "Daily submission limit reached");
    
    reportCounter++;
    reportId = reportCounter;
    
    reports[reportId] = WasteReport({
        reportId: reportId,
        reporter: msg.sender,
        photoHash: photoHash,
        wasteType: typeHash,
        weight: weight,
        lat: lat,
        lng: lng,
        submittedAt: block.timestamp,
        verified: false,
        verifier: address(0),
        rewardAmount: 0,
        partnerNotes: ""
    });
    
    reporterReports[msg.sender].push(reportId);
    dailySubmissions[msg.sender][today]++;
    photoHashUsed[photoHash] = true;
    
    emit WasteSubmitted(reportId, msg.sender, typeHash, weight, lat, lng, photoHash);
}
```

### `verifyWaste(uint256 reportId)`

```solidity
function verifyWaste(uint256 reportId) external onlyPartnerOrVerifier {
    WasteReport storage report = reports[reportId];
    require(report.reporter != address(0), "Report not found");
    require(!report.verified, "Already verified");
    
    // Calculate reward
    uint256 rate = rewardRates[report.wasteType];  // SYN per kg (with 18 decimals)
    uint256 weightKg = report.weight / 1000;         // Convert grams to kg
    uint256 reward = rate * weightKg;
    
    // Daily reward cap check
    uint256 today = block.timestamp / 86400;
    uint256 currentDaily = dailyRewards[report.reporter][today];
    if (currentDaily + reward > maxDailyReward) {
        reward = maxDailyReward - currentDaily;
    }
    require(reward > 0, "Daily reward cap reached");
    
    // Mark verified
    report.verified = true;
    report.verifier = msg.sender;
    report.rewardAmount = reward;
    dailyRewards[report.reporter][today] += reward;
    
    // Transfer reward
    require(IERC20(synToken).transfer(report.reporter, reward), "Reward transfer failed");
    
    totalVerified++;
    totalRewardsDistributed += reward;
    totalWeightCollected += report.weight;
    
    emit WasteVerified(reportId, msg.sender, report.reporter, reward);
}
```

### `rejectWaste(uint256 reportId, string calldata reason)`

```solidity
function rejectWaste(uint256 reportId, string calldata reason) external onlyPartnerOrVerifier {
    WasteReport storage report = reports[reportId];
    require(report.reporter != address(0), "Report not found");
    require(!report.verified, "Already verified");
    
    // Decrement daily submission count so user can resubmit
    uint256 today = block.timestamp / 86400;
    if (dailySubmissions[report.reporter][today] > 0) {
        dailySubmissions[report.reporter][today]--;
    }
    
    // Free photo hash for reuse
    photoHashUsed[report.photoHash] = false;
    
    report.partnerNotes = reason;
    
    emit WasteRejected(reportId, msg.sender, reason);
}
```

### `addWasteType(string calldata wasteType, uint256 ratePerKg)`

```solidity
function addWasteType(string calldata wasteType, uint256 ratePerKg) external onlyOwner {
    require(bytes(wasteType).length > 0, "Type name required");
    require(ratePerKg > 0, "Rate must be positive");
    
    bytes32 typeHash = keccak256(bytes(wasteType));
    require(rewardRates[typeHash] == 0, "Type already exists");
    
    rewardRates[typeHash] = ratePerKg;
    wasteTypes.push(typeHash);
    
    emit RewardRateSet(wasteType, ratePerKg);
}
```

### `updateWasteRate(string calldata wasteType, uint256 ratePerKg)`

```solidity
function updateWasteRate(string calldata wasteType, uint256 ratePerKg) external onlyOwner {
    bytes32 typeHash = keccak256(bytes(wasteType));
    require(rewardRates[typeHash] > 0, "Type not found");
    require(ratePerKg > 0, "Rate must be positive");
    
    rewardRates[typeHash] = ratePerKg;
    emit RewardRateSet(wasteType, ratePerKg);
}
```

### Query Functions

```solidity
function getReporterReports(address reporter) external view returns (uint256[] memory) {
    return reporterReports[reporter];
}

function getWasteTypes() external view returns (bytes32[] memory) {
    return wasteTypes;
}

function getRate(string calldata wasteType) external view returns (uint256) {
    return rewardRates[keccak256(bytes(wasteType))];
}

function getDailyStats(address user, uint256 day) external view returns (uint256 submissions, uint256 rewards) {
    return (dailySubmissions[user][day], dailyRewards[user][day]);
}
```

### Admin / Access Control

```solidity
modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
}

modifier onlyVerifier() {
    require(verifiers[msg.sender] || msg.sender == owner, "Not verifier");
    _;
}

modifier onlyPartner() {
    require(partnerOrgs[msg.sender], "Not partner org");
    _;
}

modifier onlyPartnerOrVerifier() {
    require(
        partnerOrgs[msg.sender] || verifiers[msg.sender] || msg.sender == owner,
        "Not authorized"
    );
    _;
}

function addPartnerOrg(address org) external onlyOwner {
    partnerOrgs[org] = true;
    emit PartnerOrgAdded(org);
}

function removePartnerOrg(address org) external onlyOwner {
    partnerOrgs[org] = false;
    emit PartnerOrgRemoved(org);
}

function addVerifier(address verifier) external onlyOwner {
    verifiers[verifier] = true;
}

function removeVerifier(address verifier) external onlyOwner {
    verifiers[verifier] = false;
}

function setDailyLimits(uint256 maxSubmissions, uint256 maxReward) external onlyOwner {
    maxDailySubmissions = maxSubmissions;
    maxDailyReward = maxReward;
    emit DailyLimitsUpdated(maxSubmissions, maxReward);
}

function setTokenAddress(address _syn) external onlyOwner {
    synToken = _syn;
}
```

---

## Default Reward Rates (Example)

| Waste Type | Rate per kg |
|------------|-------------|
| plastic | 2 SYN |
| metal | 3 SYN |
| glass | 1.5 SYN |
| paper | 1 SYN |
| electronics | 5 SYN |
| organic | 0.5 SYN |

---

## Deployment Checklist

- [ ] Deploy SYN token
- [ ] Deploy SynWaste with owner = deployer
- [ ] Call `setTokenAddress(synToken)`
- [ ] Fund contract with SYN for rewards
- [ ] Add partner organizations (waste management orgs)
- [ ] Add verifier addresses
- [ ] Register waste types with reward rates
- [ ] Set daily limits (default: 5 submissions, 100 SYN/day)
