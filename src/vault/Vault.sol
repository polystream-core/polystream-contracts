// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
// import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
// import "./interfaces/IVault.sol";
// import "../rewards/IRewardManager.sol";
// import "../MockProtocolAdapter.sol";
// import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import "forge-std/console.sol";

// contract Vault is ERC20, IVault, ReentrancyGuard {
//     IERC20 public immutable underlying;
//     IRewardManager public rewardManager;
//     ProtocolAdapter public protocolAdapter;
//     uint256 public totalPrincipal;

//     uint256 public constant EPOCH_DURATION = 86400;
//     uint256 public lastEpochTime;
//     uint256 public beforeBalance;

//     uint256 public constant BASE_WITHDRAWAL_FEE = 0;
//     uint256 public constant EARLY_WITHDRAWAL_FEE = 500;

//     uint256 public constant PRECISION = 1e12;

//     mapping(address => uint256) public userEntryTime;
//     mapping(address => bool) public hasDepositedBefore;
//     mapping(uint256 => mapping(address => uint256)) public userEpochDeposits;
//     mapping(address => uint256) public userShares;
//     mapping(address => uint256) public timeWeightedShares;
//     address[] public activeUsers;

//     constructor(address _underlying, address _protocolAdapter) ERC20("Vault Share", "vUSDC") {
//         require(_underlying != address(0), "Invalid underlying address");
//         require(_protocolAdapter != address(0), "Invalid adapter address");

//         underlying = IERC20(_underlying);
//         protocolAdapter = ProtocolAdapter(_protocolAdapter);
//         lastEpochTime = block.timestamp;

//         beforeBalance = underlying.balanceOf(address(protocolAdapter));
//     }

//     function setRewardManager(address _rewardManager) external {
//         require(address(rewardManager) == address(0), "RewardManager already set");
//         require(_rewardManager != address(0), "Invalid reward manager address");
//         rewardManager = IRewardManager(_rewardManager);
//         console.log("RewardManager set to:", _rewardManager);
//     }

//     // **Deposits USDC into the vault, adjusts user shares and time weight**
//     function deposit(address user, uint256 amount) external nonReentrant {
//         require(user != address(0), "Invalid user");
//         require(amount > 0, "Deposit must be > 0");

//         require(underlying.transferFrom(msg.sender, address(this), amount), "Transfer failed");

//         require(underlying.approve(address(protocolAdapter), amount), "Approval failed");
//         protocolAdapter.deposit(amount);

//         uint256 sharesToMint = amount;
//         _mint(user, sharesToMint);
//         userShares[user] += amount;
//         totalPrincipal += amount;

//         uint256 currentEpoch = getCurrentEpoch();
//         uint256 elapsedTime = block.timestamp - lastEpochTime;
//         uint256 weightFactor = elapsedTime * PRECISION / EPOCH_DURATION;
//         console.log("Elapsed time", elapsedTime);
//         console.log("Weight factor", weightFactor);

//         userEpochDeposits[currentEpoch][user] += amount;

//         if (!hasDepositedBefore[user]) {
//             hasDepositedBefore[user] = true;
//             activeUsers.push(user);

//             if (totalPrincipal == 0) {
//                 console.log("First depositor detected, full weight assigned.");
//                 timeWeightedShares[user] = amount; // First deposit gets full weight
//             } else {
//                 timeWeightedShares[user] = (amount * weightFactor) / PRECISION;
//             }
//         }


//         userEntryTime[user] = block.timestamp;

//         console.log("User deposited:", amount);
//         console.log("Epoch:", currentEpoch);
//         console.log("User time-weighted shares:", timeWeightedShares[user]);
//     }

//     function normalizeUserWeights() internal {
//         for (uint256 i = 0; i < activeUsers.length; i++) {
//             address user = activeUsers[i];

//             timeWeightedShares[user] = userShares[user]; 
//         }
//     }

//     function withdraw(address user, uint256 shareAmount) external nonReentrant {
//         require(user != address(0), "Invalid user");
//         require(shareAmount > 0, "Withdraw amount must be > 0");
//         require(userShares[user] >= shareAmount, "Insufficient shares");

//         claimReward(user);

//         uint256 currentEpoch = getCurrentEpoch();
//         uint256 penaltyFee = BASE_WITHDRAWAL_FEE;
//         uint256 currentEpochDeposit = userEpochDeposits[currentEpoch][user];

//         if (currentEpochDeposit > 0) {
//             penaltyFee = EARLY_WITHDRAWAL_FEE;
//             console.log("Applying early withdrawal fee on:", currentEpochDeposit);
//         }

//         uint256 fee = (currentEpochDeposit * penaltyFee) / 10_000;
//         uint256 finalWithdrawAmount = shareAmount - fee;

//         console.log("Fee permanently deducted:", fee);
//         protocolAdapter.convertFeeToReward(fee);
//         console.log("Final withdraw amount:", finalWithdrawAmount);

//         uint256 actualWithdrawAmount = protocolAdapter.withdraw(finalWithdrawAmount, user);
//         require(actualWithdrawAmount == finalWithdrawAmount, "Protocol withdraw mismatch");

//         userShares[user] -= shareAmount; 
//         totalPrincipal -= shareAmount;

//         rewardManager.updateUserRewardDebt(user);

//         _burn(user, shareAmount);
//         userShares[user] = balanceOf(user);

//         rewardManager.updateUserRewardDebt(user);

//         console.log("User withdrawn:", actualWithdrawAmount);
//         console.log("Remaining Shares after deduction:", userShares[user]);

//         if (userShares[user] == 0) {
//             _removeUser(user);
//         }
//     }

//     function claimReward(address user) public {
//         uint256 userRewardDebt = rewardManager.getUserRewardDebt(user);
//         uint256 totalAccumulatedReward = (userShares[user] * rewardManager.getAccRewardPerShare()) / PRECISION;

//         uint256 pending = totalAccumulatedReward - userRewardDebt;
//         if (pending == 0) return;

//         uint256 protocolBalance = underlying.balanceOf(address(protocolAdapter));
//         require(protocolBalance >= pending, "Insufficient balance in protocol");

//         require(underlying.transferFrom(address(protocolAdapter), user, pending), "Reward transfer failed");

//         rewardManager.recordClaimedReward(user, pending);

//         rewardManager.updateUserRewardDebt(user);

//         console.log("User claimed rewards:", user, "Amount:", pending);
//     }

//     function _removeUser(address user) internal {
//         for (uint256 i = 0; i < activeUsers.length; i++) {
//             if (activeUsers[i] == user) {
//                 activeUsers[i] = activeUsers[activeUsers.length - 1];
//                 activeUsers.pop();
//                 delete userEntryTime[user];
//                 rewardManager.resetClaimedReward(user);
//                 break;
//             }
//         }
//     }

//     function checkAndHarvest() public override nonReentrant {
//         if (block.timestamp >= lastEpochTime + EPOCH_DURATION) {
//             uint256 totalBalanceAfterHarvest = protocolAdapter.harvest();
//             uint256 actualRewards = totalBalanceAfterHarvest - beforeBalance;
//             if (actualRewards > 0) {
//                 rewardManager.updateRewardState(actualRewards);
//             }

//             for (uint256 i = 0; i < activeUsers.length; i++) {
//                 address user = activeUsers[i];
//                 rewardManager.updateUserRewardDebt(user);
//                 console.log("Updated reward debt for user:", user);
//             }

//             lastEpochTime = block.timestamp;
//             beforeBalance = totalBalanceAfterHarvest;

//             normalizeUserWeights();
//         }
//     }

//     function getTotalTimeWeightedShares() external view returns (uint256 total) {
//         for (uint256 i = 0; i < activeUsers.length; i++) {
//             total += timeWeightedShares[activeUsers[i]];
//         }
//     }

//     function getUserTimeWeightedShares(address user) external view returns (uint256) {
//         return timeWeightedShares[user];
//     }

//     function getCurrentEpoch() public view override returns (uint256) {
//         return block.timestamp / EPOCH_DURATION;
//     }

//     function getUsers() external view override returns (address[] memory) {
//         return activeUsers;
//     }

//     function getUserEntryTime(address user) external view override returns (uint256) {
//         return userEntryTime[user];
//     }

//     function getTotalSupply() external view override returns (uint256) {
//         return totalSupply();
//     }

//     function balanceOf(address account) public view override(ERC20, IVault) returns (uint256) {
//         return super.balanceOf(account);
//     }
// }
