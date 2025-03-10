// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "../vault/IVault.sol";
// import "../rewards/IRewardManager.sol";
// import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import "forge-std/console.sol";

// contract Aggregator {
//     IVault public vault;
//     IRewardManager public rewardManager;
//     IERC20 public underlying;

//     mapping(address => uint256) public userShares;
//     address[] public trackedUsers;

//     event DepositedForUser(address indexed user, uint256 amount, uint256 totalUserShares);
//     event WithdrawnForUser(address indexed user, uint256 shareAmount, uint256 underlyingReturned);
//     event RewardClaimedForUser(address indexed user, uint256 reward);
//     event YieldDeposited(uint256 amount);

//     constructor(address _vault, address _rewardManager, address _underlying) {
//         require(_vault != address(0), "Invalid vault address");
//         require(_rewardManager != address(0), "Invalid reward manager address");
//         require(_underlying != address(0), "Invalid underlying address");
//         vault = IVault(_vault);
//         rewardManager = IRewardManager(_rewardManager);
//         underlying = IERC20(_underlying);
//     }

//     function depositForUser(address user, uint256 amount) external {
//         require(amount > 0, "Amount must be > 0");

//         require(underlying.transferFrom(msg.sender, address(this), amount), "Transfer failed");
//         require(underlying.approve(address(vault), amount), "Approve failed");

//         vault.deposit(user, amount);
//         userShares[user] += amount;
//         _updateTrackedUsers();
        
//         rewardManager.updateUserRewardDebt(user);
//     }

//     function withdrawForUser(address user, uint256 shareAmount) external {
//         require(userShares[user] >= shareAmount, "Insufficient user shares");

//         vault.withdraw(user, shareAmount);
//         userShares[user] -= shareAmount;

//         rewardManager.updateUserRewardDebt(user);
        
//         if (userShares[user] == 0) {
//             _removeTrackedUser(user);
//         }

//         emit WithdrawnForUser(user, shareAmount, shareAmount);
//     }

//     function _updateTrackedUsers() internal {
//         address[] memory users = vault.getUsers();
//         for (uint256 i = 0; i < users.length; i++) {
//             if (!_isUserTracked(users[i])) {
//                 trackedUsers.push(users[i]);
//             }
//         }
//     }

//     function _removeTrackedUser(address user) internal {
//         for (uint256 i = 0; i < trackedUsers.length; i++) {
//             if (trackedUsers[i] == user) {
//                 trackedUsers[i] = trackedUsers[trackedUsers.length - 1];
//                 trackedUsers.pop();
//                 break;
//             }
//         }
//     }

//     function _isUserTracked(address user) internal view returns (bool) {
//         for (uint256 i = 0; i < trackedUsers.length; i++) {
//             if (trackedUsers[i] == user) {
//                 return true;
//             }
//         }
//         return false;
//     }

//     function depositYield(uint256 amount) external {
//         require(amount > 0, "Amount must be > 0");

//         // Ensure the Aggregator has enough USDC before transferring
//         uint256 aggregatorBalance = underlying.balanceOf(address(this));
//         require(aggregatorBalance >= amount, "Aggregator lacks enough USDC");

//         require(underlying.approve(address(rewardManager), amount), "Approval to RewardManager failed");
//         require(underlying.transfer(address(rewardManager), amount), "Transfer failed");

//         rewardManager.depositReward(amount);
//         emit YieldDeposited(amount);
//     }

// }
