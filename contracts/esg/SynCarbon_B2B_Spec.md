# SynCarbon B2B Contract Spec

## Overview
B2B carbon credit marketplace. Companies post environmental jobs (cleanup, renewable install, etc.). Contractors accept jobs, submit proof of completion with photo + geolocation, and verifiers confirm work to mint a compliance NFT and release SYN reward escrow.

---

## State Variables

```solidity
// Access control
address public owner;
mapping(address => bool) public verifiers;
mapping(address => bool) public registeredCompanies;

// Token integration
address public synToken;
address public complianceNFTContract;

// Fee / economics
uint256 public platformFeePercent = 5;   // 5% platform fee
uint256 public minJobReward = 100 * 10**18;  // 100 SYN minimum

// Job lifecycle
enum JobStatus {
    Open,         // Posted, awaiting acceptance
    Accepted,     // Contractor assigned
    InProgress,   // Work started
    Submitted,    // Proof submitted, awaiting verification
    Verified,     // Completed, NFT minted, reward released
    Disputed,     // Under dispute
    Cancelled     // Cancelled by poster or expired
}

struct Job {
    uint256 jobId;
    address company;         // Job poster
    address contractor;      // Assigned worker
    string description;
    string location;         // Human-readable location string
    int256 lat;              // GPS lat * 10**6
    int256 lng;              // GPS lng * 10**6
    uint256 reward;          // SYN amount (escrowed)
    uint256 postedAt;
    uint256 acceptedAt;
    uint256 completedAt;
    uint256 verifiedAt;
    JobStatus status;
    string proofPhotoHash;
    int256 proofLat;
    int256 proofLng;
    address verifier;
    uint256 tokenId;         // Compliance NFT ID
    string cancellationReason;
}

// Storage
mapping(uint256 => Job) public jobs;
mapping(address => uint256[]) public companyJobs;
mapping(address => uint256[]) public contractorJobs;
mapping(uint256 => uint256) public escrowedAmount;  // jobId => SYN amount held

uint256 public jobCounter;
uint256 public totalJobsCompleted;
uint256 public totalRewardsDistributed;
uint256 public totalPlatformFees;

// Open jobs index for browsing
uint256[] public openJobs;
mapping(uint256 => uint256) public openJobIndex;
```

---

## Events

```solidity
event JobPosted(
    uint256 indexed jobId,
    address indexed company,
    string description,
    string location,
    uint256 reward
);

event JobAccepted(
    uint256 indexed jobId,
    address indexed contractor
);

event JobStarted(
    uint256 indexed jobId,
    address indexed contractor
);

event ProofSubmitted(
    uint256 indexed jobId,
    address indexed contractor,
    string photoHash,
    int256 lat,
    int256 lng
);

event JobVerified(
    uint256 indexed jobId,
    address indexed verifier,
    uint256 rewardReleased,
    uint256 tokenId
);

event JobCancelled(
    uint256 indexed jobId,
    address indexed by,
    string reason
);

event CompanyRegistered(address indexed company, string name);
event PlatformFeeUpdated(uint256 newFeePercent);
```

---

## Functions

### `registerCompany(string calldata name)`

```solidity
function registerCompany(string calldata name) external {
    require(!registeredCompanies[msg.sender], "Already registered");
    require(bytes(name).length > 0, "Name required");
    registeredCompanies[msg.sender] = true;
    emit CompanyRegistered(msg.sender, name);
}
```

### `postJob(string calldata description, string calldata location, int256 lat, int256 lng, uint256 reward)`

```solidity
function postJob(
    string calldata description,
    string calldata location,
    int256 lat,
    int256 lng,
    uint256 reward
) external onlyRegisteredCompany returns (uint256 jobId) {
    require(bytes(description).length > 0, "Description required");
    require(bytes(location).length > 0, "Location required");
    require(reward >= minJobReward, "Reward below minimum");
    require(lat >= -90000000 && lat <= 90000000, "Invalid latitude");
    require(lng >= -180000000 && lng <= 180000000, "Invalid longitude");
    
    // Escrow SYN tokens
    require(IERC20(synToken).transferFrom(msg.sender, address(this), reward), "Escrow failed");
    
    jobCounter++;
    jobId = jobCounter;
    
    jobs[jobId] = Job({
        jobId: jobId,
        company: msg.sender,
        contractor: address(0),
        description: description,
        location: location,
        lat: lat,
        lng: lng,
        reward: reward,
        postedAt: block.timestamp,
        acceptedAt: 0,
        completedAt: 0,
        verifiedAt: 0,
        status: JobStatus.Open,
        proofPhotoHash: "",
        proofLat: 0,
        proofLng: 0,
        verifier: address(0),
        tokenId: 0,
        cancellationReason: ""
    });
    
    escrowedAmount[jobId] = reward;
    companyJobs[msg.sender].push(jobId);
    
    // Add to open jobs list
    openJobIndex[jobId] = openJobs.length;
    openJobs.push(jobId);
    
    emit JobPosted(jobId, msg.sender, description, location, reward);
}
```

### `acceptJob(uint256 jobId)`

```solidity
function acceptJob(uint256 jobId) external {
    Job storage job = jobs[jobId];
    require(job.company != address(0), "Job not found");
    require(job.status == JobStatus.Open, "Job not open");
    require(msg.sender != job.company, "Cannot accept own job");
    
    job.contractor = msg.sender;
    job.status = JobStatus.Accepted;
    job.acceptedAt = block.timestamp;
    
    contractorJobs[msg.sender].push(jobId);
    _removeOpenJob(jobId);
    
    emit JobAccepted(jobId, msg.sender);
}
```

### `startWork(uint256 jobId)`

```solidity
function startWork(uint256 jobId) external {
    Job storage job = jobs[jobId];
    require(job.contractor == msg.sender, "Not assigned contractor");
    require(job.status == JobStatus.Accepted, "Job not accepted");
    
    job.status = JobStatus.InProgress;
    emit JobStarted(jobId, msg.sender);
}
```

### `submitProof(uint256 jobId, string calldata photoHash, int256 proofLat, int256 proofLng)`

```solidity
function submitProof(
    uint256 jobId,
    string calldata photoHash,
    int256 proofLat,
    int256 proofLng
) external {
    Job storage job = jobs[jobId];
    require(job.contractor == msg.sender, "Not assigned contractor");
    require(job.status == JobStatus.InProgress, "Job not in progress");
    require(bytes(photoHash).length > 0, "Photo hash required");
    require(proofLat >= -90000000 && proofLat <= 90000000, "Invalid proof latitude");
    require(proofLng >= -180000000 && proofLng <= 180000000, "Invalid proof longitude");
    
    job.proofPhotoHash = photoHash;
    job.proofLat = proofLat;
    job.proofLng = proofLng;
    job.status = JobStatus.Submitted;
    job.completedAt = block.timestamp;
    
    emit ProofSubmitted(jobId, msg.sender, photoHash, proofLat, proofLng);
}
```

### `verifyCompletion(uint256 jobId)`

```solidity
function verifyCompletion(uint256 jobId) external onlyVerifier {
    Job storage job = jobs[jobId];
    require(job.status == JobStatus.Submitted, "Job not submitted");
    require(job.completedAt > 0, "No submission found");
    
    job.status = JobStatus.Verified;
    job.verifiedAt = block.timestamp;
    job.verifier = msg.sender;
    
    uint256 reward = job.reward;
    uint256 platformFee = reward * platformFeePercent / 100;
    uint256 contractorPayout = reward - platformFee;
    
    // Release payment to contractor
    require(IERC20(synToken).transfer(job.contractor, contractorPayout), "Payout failed");
    
    // Platform fee to owner treasury
    if (platformFee > 0) {
        require(IERC20(synToken).transfer(owner, platformFee), "Fee transfer failed");
        totalPlatformFees += platformFee;
    }
    
    // Mint compliance NFT for the company
    uint256 tokenId = IComplianceNFT(complianceNFTContract).mint(
        job.company, 
        jobId, 
        job.description,
        job.proofPhotoHash
    );
    job.tokenId = tokenId;
    
    // Clear escrow
    escrowedAmount[jobId] = 0;
    totalJobsCompleted++;
    totalRewardsDistributed += contractorPayout;
    
    emit JobVerified(jobId, msg.sender, contractorPayout, tokenId);
}
```

### `cancelJob(uint256 jobId, string calldata reason)`

```solidity
function cancelJob(uint256 jobId, string calldata reason) external {
    Job storage job = jobs[jobId];
    require(job.company == msg.sender || msg.sender == owner, "Not authorized");
    require(job.status == JobStatus.Open || job.status == JobStatus.Accepted, "Cannot cancel");
    
    uint256 refund = escrowedAmount[jobId];
    escrowedAmount[jobId] = 0;
    job.status = JobStatus.Cancelled;
    job.cancellationReason = reason;
    
    if (refund > 0) {
        require(IERC20(synToken).transfer(job.company, refund), "Refund failed");
    }
    
    if (job.status == JobStatus.Open) {
        _removeOpenJob(jobId);
    }
    
    emit JobCancelled(jobId, msg.sender, reason);
}
```

### Open Jobs Index (Internal)

```solidity
function _removeOpenJob(uint256 jobId) internal {
    uint256 index = openJobIndex[jobId];
    uint256 lastIndex = openJobs.length - 1;
    uint256 lastJobId = openJobs[lastIndex];
    
    openJobs[index] = lastJobId;
    openJobIndex[lastJobId] = index;
    openJobs.pop();
    delete openJobIndex[jobId];
}

function getOpenJobs() external view returns (uint256[] memory) {
    return openJobs;
}

function getCompanyJobs(address company) external view returns (uint256[] memory) {
    return companyJobs[company];
}

function getContractorJobs(address contractor) external view returns (uint256[] memory) {
    return contractorJobs[contractor];
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

modifier onlyRegisteredCompany() {
    require(registeredCompanies[msg.sender], "Not registered company");
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

function setPlatformFee(uint256 feePercent) external onlyOwner {
    require(feePercent <= 20, "Fee too high");  // Max 20%
    platformFeePercent = feePercent;
    emit PlatformFeeUpdated(feePercent);
}

function setMinReward(uint256 min) external onlyOwner {
    minJobReward = min;
}

function setTokenAddresses(address _syn, address _nft) external onlyOwner {
    synToken = _syn;
    complianceNFTContract = _nft;
}
```

---

## Fee & Reward Flow

```
Company posts job (escrow 1000 SYN)
  → Contractor accepts
  → Contractor completes + submits proof
  → Verifier approves
    → Contractor receives 950 SYN (95%)
    → Platform treasury receives 50 SYN (5%)
    → Company receives Compliance NFT
```

---

## Deployment Checklist

- [ ] Deploy SYN token
- [ ] Deploy ComplianceNFT (ERC721 with job metadata)
- [ ] Deploy SynCarbon with owner = deployer
- [ ] Call `setTokenAddresses(synToken, nftContract)`
- [ ] Fund contract with minimal SYN for gas (optional)
- [ ] Add verifier addresses
- [ ] Set platform fee (default 5%)
- [ ] Set minimum reward threshold
