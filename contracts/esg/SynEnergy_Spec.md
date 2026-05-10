# SynEnergy Contract Spec

## Overview
Renewable energy generation verification dApp. Users submit proof of energy production (solar, wind, hydro, etc.) with photo of meter/installation, energy source type, and kWh generated. Verifiers confirm authenticity and reward SYN based on kWh rate.

---

## State Variables

```solidity
// Access control
address public owner;
mapping(address => bool) public verifiers;

// Token integration
address public synToken;
address public energyNFTContract;  // Optional: milestone NFTs

// Reward rates per energy source (SYN per kWh, with 18 decimals)
// Example: 5 * 10**18 = 5 SYN per kWh
mapping(bytes32 => uint256) public kwhRates;  // keccak256(source) => rate
bytes32[] public energySources;

// Submission limits
uint256 public maxDailySubmissions = 3;
uint256 public maxDailyReward = 200 * 10**18;   // 200 SYN/day cap
uint256 public minKwh = 1;                       // Minimum 1 kWh
uint256 public maxKwh = 10000;                   // Maximum 10,000 kWh per submission

// Meter hash registry (prevent meter reuse fraud)
mapping(string => bool) public meterHashUsed;
mapping(string => address) public meterHashOwner;  // Track original owner

// Energy report struct
struct EnergyReport {
    uint256 reportId;
    address reporter;
    string photoHash;
    bytes32 energySource;
    uint256 kwh;             // kWh * 100 (2 decimal precision)
    string meterHash;        // Unique identifier for the meter/installation
    uint256 submittedAt;
    bool verified;
    address verifier;
    uint256 rewardAmount;
    string verifierNotes;
}

// Storage
mapping(uint256 => EnergyReport) public reports;
mapping(address => uint256[]) public reporterReports;
mapping(address => mapping(uint256 => uint256)) public dailySubmissions;
mapping(address => mapping(uint256 => uint256)) public dailyRewards;
mapping(string => bool) public photoHashUsed;

uint256 public reportCounter;
uint256 public totalVerified;
uint256 public totalRewardsDistributed;
uint256 public totalKwhVerified;  // Total kWh * 100 across all verified reports
```

---

## Events

```solidity
event EnergySubmitted(
    uint256 indexed reportId,
    address indexed reporter,
    bytes32 energySource,
    uint256 kwh,
    string meterHash,
    string photoHash
);

event EnergyVerified(
    uint256 indexed reportId,
    address indexed verifier,
    address indexed reporter,
    uint256 rewardAmount
);

event EnergyRejected(
    uint256 indexed reportId,
    address indexed verifier,
    string reason
);

event RateSet(string energySource, uint256 ratePerKwh);
event MeterRegistered(string meterHash, address owner);
event DailyLimitsUpdated(uint256 maxSubmissions, uint256 maxReward);
event VerifierAdded(address indexed verifier);
event VerifierRemoved(address indexed verifier);
```

---

## Functions

### `submitEnergy(string calldata photoHash, string calldata source, uint256 kwh, string calldata meterHash)`

```solidity
function submitEnergy(
    string calldata photoHash,
    string calldata source,
    uint256 kwh,             // kWh * 100 (2 decimal places)
    string calldata meterHash
) external returns (uint256 reportId) {
    require(bytes(photoHash).length > 0, "Photo hash required");
    require(!photoHashUsed[photoHash], "Photo already used");
    require(bytes(source).length > 0, "Source required");
    require(kwh >= minKwh * 100 && kwh <= maxKwh * 100, "kWh out of range");
    require(bytes(meterHash).length > 0, "Meter hash required");
    
    bytes32 sourceHash = keccak256(bytes(source));
    require(kwhRates[sourceHash] > 0, "Energy source not registered");
    
    // Meter hash validation
    if (meterHashOwner[meterHash] == address(0)) {
        // First time seeing this meter — register to reporter
        meterHashOwner[meterHash] = msg.sender;
        emit MeterRegistered(meterHash, msg.sender);
    } else {
        // Meter already registered — must be same owner
        require(meterHashOwner[meterHash] == msg.sender, "Meter registered to different user");
    }
    require(!meterHashUsed[meterHash], "Meter already used in another report");
    
    // Daily limits
    uint256 today = block.timestamp / 86400;
    require(dailySubmissions[msg.sender][today] < maxDailySubmissions, "Daily limit reached");
    
    reportCounter++;
    reportId = reportCounter;
    
    reports[reportId] = EnergyReport({
        reportId: reportId,
        reporter: msg.sender,
        photoHash: photoHash,
        energySource: sourceHash,
        kwh: kwh,
        meterHash: meterHash,
        submittedAt: block.timestamp,
        verified: false,
        verifier: address(0),
        rewardAmount: 0,
        verifierNotes: ""
    });
    
    reporterReports[msg.sender].push(reportId);
    dailySubmissions[msg.sender][today]++;
    photoHashUsed[photoHash] = true;
    meterHashUsed[meterHash] = true;
    
    emit EnergySubmitted(reportId, msg.sender, sourceHash, kwh, meterHash, photoHash);
}
```

### `verifyEnergy(uint256 reportId)`

```solidity
function verifyEnergy(uint256 reportId) external onlyVerifier {
    EnergyReport storage report = reports[reportId];
    require(report.reporter != address(0), "Report not found");
    require(!report.verified, "Already verified");
    
    // Calculate reward
    uint256 rate = kwhRates[report.energySource];  // SYN per kWh (18 decimals)
    uint256 actualKwh = report.kwh;                  // Already * 100
    uint256 reward = (rate * actualKwh) / 100;     // Adjust for 2-decimal kWh
    
    // Daily reward cap
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
    totalKwhVerified += report.kwh;
    
    emit EnergyVerified(reportId, msg.sender, report.reporter, reward);
}
```

### `rejectEnergy(uint256 reportId, string calldata reason)`

```solidity
function rejectEnergy(uint256 reportId, string calldata reason) external onlyVerifier {
    EnergyReport storage report = reports[reportId];
    require(report.reporter != address(0), "Report not found");
    require(!report.verified, "Already verified");
    
    // Decrement daily submission count
    uint256 today = block.timestamp / 86400;
    if (dailySubmissions[report.reporter][today] > 0) {
        dailySubmissions[report.reporter][today]--;
    }
    
    // Free photo and meter hashes for reuse
    photoHashUsed[report.photoHash] = false;
    meterHashUsed[report.meterHash] = false;
    
    report.verifierNotes = reason;
    
    emit EnergyRejected(reportId, msg.sender, reason);
}
```

### `addEnergySource(string calldata source, uint256 ratePerKwh)`

```solidity
function addEnergySource(string calldata source, uint256 ratePerKwh) external onlyOwner {
    require(bytes(source).length > 0, "Source name required");
    require(ratePerKwh > 0, "Rate must be positive");
    
    bytes32 sourceHash = keccak256(bytes(source));
    require(kwhRates[sourceHash] == 0, "Source already exists");
    
    kwhRates[sourceHash] = ratePerKwh;
    energySources.push(sourceHash);
    
    emit RateSet(source, ratePerKwh);
}
```

### `updateEnergyRate(string calldata source, uint256 ratePerKwh)`

```solidity
function updateEnergyRate(string calldata source, uint256 ratePerKwh) external onlyOwner {
    bytes32 sourceHash = keccak256(bytes(source));
    require(kwhRates[sourceHash] > 0, "Source not found");
    require(ratePerKwh > 0, "Rate must be positive");
    
    kwhRates[sourceHash] = ratePerKwh;
    emit RateSet(source, ratePerKwh);
}
```

### Query Functions

```solidity
function getReporterReports(address reporter) external view returns (uint256[] memory) {
    return reporterReports[reporter];
}

function getEnergySources() external view returns (bytes32[] memory) {
    return energySources;
}

function getRate(string calldata source) external view returns (uint256) {
    return kwhRates[keccak256(bytes(source))];
}

function getDailyStats(address user, uint256 day) external view returns (uint256 submissions, uint256 rewards) {
    return (dailySubmissions[user][day], dailyRewards[user][day]);
}

function getMeterOwner(string calldata meterHash) external view returns (address) {
    return meterHashOwner[meterHash];
}

function isMeterUsed(string calldata meterHash) external view returns (bool) {
    return meterHashUsed[meterHash];
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

function addVerifier(address verifier) external onlyOwner {
    verifiers[verifier] = true;
    emit VerifierAdded(verifier);
}

function removeVerifier(address verifier) external onlyOwner {
    verifiers[verifier] = false;
    emit VerifierRemoved(verifier);
}

function setDailyLimits(uint256 maxSubmissions, uint256 maxReward) external onlyOwner {
    maxDailySubmissions = maxSubmissions;
    maxDailyReward = maxReward;
    emit DailyLimitsUpdated(maxSubmissions, maxReward);
}

function setKwhRange(uint256 min, uint256 max) external onlyOwner {
    minKwh = min;
    maxKwh = max;
}

function setTokenAddress(address _syn) external onlyOwner {
    synToken = _syn;
}
```

---

## Default kWh Rates (Example)

| Energy Source | Rate per kWh |
|---------------|--------------|
| solar | 5 SYN |
| wind | 4 SYN |
| hydro | 3 SYN |
| geothermal | 6 SYN |
| biomass | 2 SYN |

---

## Anti-Fraud: Meter Hash System

- Each physical meter/installation gets a unique `meterHash`
- First submission registers the meter to the reporter
- Subsequent submissions with the same meter must come from the same reporter
- Prevents meter sharing / double-counting across users

---

## Deployment Checklist

- [ ] Deploy SYN token
- [ ] Deploy SynEnergy with owner = deployer
- [ ] Call `setTokenAddress(synToken)`
- [ ] Fund contract with SYN for rewards
- [ ] Add verifier addresses
- [ ] Register energy sources with kWh rates
- [ ] Set daily limits (default: 3 submissions, 200 SYN/day)
