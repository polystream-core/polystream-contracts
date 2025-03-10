// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../vault/IVault.sol";
import "forge-std/console.sol";

contract RewardManager {
    IERC20 public immutable underlying;
    IVault public immutable vault;

    uint256 public accRewardPerShare;
    uint256 public constant PRECISION = 1e12;

    mapping(address => uint256) public rewardDebt;
    mapping(address => uint256) public claimedRewards;

    constructor(address _underlying, address _vault) {
        require(_underlying != address(0), "Invalid underlying address");
        require(_vault != address(0), "Invalid vault address");

        underlying = IERC20(_underlying);
        vault = IVault(_vault);
    }

    function updateRewardState(uint256 epochReward) external {
        uint256 totalWeightedShares = vault.getTotalTimeWeightedShares();
        if (totalWeightedShares == 0) return;

        console.log("Epoch reward:", epochReward);
        console.log("Total weighted shares:", totalWeightedShares);

        uint256 totalShares = vault.getTotalSupply();
        uint256 totalWeight = vault.getTotalTimeWeightedShares();
        uint256 rewardPerShare = totalWeight > 0 
            ? (epochReward * PRECISION) / totalWeight 
            : (epochReward * PRECISION) / totalShares;


        require(rewardPerShare < 1e18, "Reward per share is too large");

        accRewardPerShare += rewardPerShare;
        console.log("Updated accRewardPerShare:", accRewardPerShare);
    }

    function updateUserRewardDebt(address user) external {
        uint256 weightedShares = vault.getUserTimeWeightedShares(user);
        if (weightedShares == 0) {
            weightedShares = vault.balanceOf(user);
        }

        uint256 accumulatedReward = (weightedShares * accRewardPerShare) / PRECISION;

        uint256 newRewardDebt = accumulatedReward > claimedRewards[user]
            ? accumulatedReward - claimedRewards[user]
            : 0; 

        console.log("Updating reward debt...");
        console.log("User weighted shares:", weightedShares);
        console.log("accRewardPerShare:", accRewardPerShare);
        console.log("Total Claimed Rewards:", claimedRewards[user]);
        console.log("New rewardDebt:", newRewardDebt);

        rewardDebt[user] = newRewardDebt;
    }

    function recordClaimedReward(address user, uint256 amount) external {
        claimedRewards[user] += amount;
        console.log("User claimed reward updated:", user, "Total claimed:", claimedRewards[user]);
    }

    function getAccRewardPerShare() external view returns (uint256) {
        return accRewardPerShare;
    }

    function getUserRewardDebt(address user) external view returns (uint256) {
        return rewardDebt[user];
    }

    function getUserClaimedReward(address user) external view returns (uint256) {
        return claimedRewards[user];
    }

    function resetClaimedReward(address user) external {
        console.log("Resetting claimed rewards for user:", user);
        claimedRewards[user] = 0;
    }
}
