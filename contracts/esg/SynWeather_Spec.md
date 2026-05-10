# SynWeather Contract Spec

## Overview
Decentralized weather data collection dApp. Users submit local weather readings (temperature, humidity, geolocation) with photo proof. Valid submissions mint an NFT and reward SYN tokens, with streak bonuses for consecutive daily submissions.

---

## State Variables

```solidity
// Access control
address public owner;
mapping(address => bool) public verifiers;

// Token integration
address public synToken;           // SYN ERC20 contract address
address public nftContract;        // Weather NFT contract address

// Reward parameters
uint256 public baseReward = 10 * 10**18;      // 10 SYN (18 decimals)
uint256 public streakBonus = 5 * 10**18;       // 5 SYN per streak day
uint256 public maxStreakBonus = 50 * 10**18;   // Cap at 50 SYN
int256 public minTemp = -50;                  // Celsius
int256 public maxTemp = 60;                   // Celsius
uint256 public minHumidity = 0;
uint256 public maxHumidity = 100;

// Submission tracking
struct WeatherReport {
    address reporter;
    int256 temperature;      // Celsius * 100 (2 decimals)
    uint256 humidity;        // 0-100
    int256 lat;              // Latitude * 10**6
    int256 lng;              // Longitude * 10**6
    string photoHash;        // IPFS or content hash
    uint256 timestamp;
    bool verified;
    uint256 rewardAmount;
    uint256 tokenId;         // Minted NFT ID
}

mapping(uint256 => WeatherReport) public reports;
mapping(address => uint256) public lastSubmissionDate;  // Unix day number
mapping(address => uint256) public currentStreak;
mapping(address => uint256) public totalSubmissions;
mapping(string => bool) public photoHashUsed;  // Prevent duplicate photos

uint256 public reportCounter;
uint256 public totalRewardsDistributed;
```

---

## Events

```solidity
event WeatherSubmitted(
    uint256 indexed reportId,
    address indexed reporter,
    int256 temperature,
    uint256 humidity,
    int256 lat,
    int256 lng,
    string photoHash,
    uint256 timestamp
);

event WeatherVerified(
    uint256 indexed reportId,
    address indexed verifier,
    uint256 rewardAmount,
    uint256 tokenId
);

event StreakUpdated(address indexed reporter, uint256 newStreak);
event RewardParametersUpdated(uint256 baseReward, uint256 streakBonus, uint256 maxStreak);
event VerifierAdded(address indexed verifier);
event VerifierRemoved(address indexed verifier);
```

---

## Functions

### `submitWeather(int256 temp, uint256 humidity, int256 lat, int256 lng, string calldata photoHash)`

```solidity
function submitWeather(
    int256 temp,           // Temperature in Celsius * 100
    uint256 humidity,      // 0-100
    int256 lat,            // Latitude * 10**6
    int256 lng,            // Longitude * 10**6
    string calldata photoHash
) external returns (uint256 reportId) {
    // Validation
    require(bytes(photoHash).length > 0, "Photo hash required");
    require(!photoHashUsed[photoHash], "Photo already submitted");
    require(temp >= minTemp * 100 && temp <= maxTemp * 100, "Temperature out of range");
    require(humidity >= minHumidity && humidity <= maxHumidity, "Humidity out of range");
    require(lat >= -90000000 && lat <= 90000000, "Invalid latitude");
    require(lng >= -180000000 && lng <= 180000000, "Invalid longitude");
    
    // Check daily submission limit (1 per day per user)
    uint256 today = block.timestamp / 86400;
    require(lastSubmissionDate[msg.sender] < today, "Already submitted today");
    
    // Update streak
    uint256 lastDay = lastSubmissionDate[msg.sender];
    if (lastDay == today - 1) {
        currentStreak[msg.sender] += 1;
    } else if (lastDay < today - 1) {
        currentStreak[msg.sender] = 1;  // Reset streak
    }
    lastSubmissionDate[msg.sender] = today;
    
    emit StreakUpdated(msg.sender, currentStreak[msg.sender]);
    
    // Store report
    reportCounter++;
    reportId = reportCounter;
    
    reports[reportId] = WeatherReport({
        reporter: msg.sender,
        temperature: temp,
        humidity: humidity,
        lat: lat,
        lng: lng,
        photoHash: photoHash,
        timestamp: block.timestamp,
        verified: false,
        rewardAmount: 0,
        tokenId: 0
    });
    
    photoHashUsed[photoHash] = true;
    totalSubmissions[msg.sender]++;
    
    emit WeatherSubmitted(reportId, msg.sender, temp, humidity, lat, lng, photoHash, block.timestamp);
}
```

### `verifyWeather(uint256 reportId)`

```solidity
function verifyWeather(uint256 reportId) external onlyVerifier {
    WeatherReport storage report = reports[reportId];
    require(report.reporter != address(0), "Report not found");
    require(!report.verified, "Already verified");
    
    // Calculate reward
    uint256 streak = currentStreak[report.reporter];
    uint256 bonus = streakBonus * (streak - 1);
    if (bonus > maxStreakBonus) {
        bonus = maxStreakBonus;
    }
    uint256 reward = baseReward + bonus;
    
    // Mark verified
    report.verified = true;
    report.rewardAmount = reward;
    
    // Mint NFT
    uint256 tokenId = IWeatherNFT(nftContract).mint(report.reporter, reportId);
    report.tokenId = tokenId;
    
    // Transfer SYN reward
    require(IERC20(synToken).transfer(report.reporter, reward), "Reward transfer failed");
    totalRewardsDistributed += reward;
    
    emit WeatherVerified(reportId, msg.sender, reward, tokenId);
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

function setRewardParameters(uint256 _base, uint256 _streak, uint256 _max) external onlyOwner {
    baseReward = _base;
    streakBonus = _streak;
    maxStreakBonus = _max;
    emit RewardParametersUpdated(_base, _streak, _max);
}

function setTokenAddresses(address _syn, address _nft) external onlyOwner {
    synToken = _syn;
    nftContract = _nft;
}
```

---

## Reward Calculation

| Submissions | Base | Streak Bonus | Total |
|-------------|------|--------------|-------|
| 1st day | 10 SYN | 0 | 10 SYN |
| 2nd consecutive | 10 SYN | 5 SYN | 15 SYN |
| 3rd consecutive | 10 SYN | 10 SYN | 20 SYN |
| ... | ... | ... | ... |
| 11+ consecutive | 10 SYN | 50 SYN (cap) | 60 SYN |

---

## Deployment Checklist

- [ ] Deploy SYN token (ERC20, mintable by owner)
- [ ] Deploy WeatherNFT (ERC721, mintable by SynWeather contract)
- [ ] Deploy SynWeather with owner = deployer
- [ ] Call `setTokenAddresses(synToken, nftToken)`
- [ ] Fund contract with SYN tokens for rewards
- [ ] Add verifier addresses
- [ ] Set reward parameters (or keep defaults)
