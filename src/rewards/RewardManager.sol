// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/interfaces/IVault.sol";

/**
 * @title RewardManager
 * @notice Manages reward distribution for vault users based on their balances and time-weighted contributions
 * @dev Simplified to work with the direct balance tracking approach of the refactored vault
 */
contract RewardManager {
    IERC20 public immutable underlying;
    IVault public immutable vault;

    // Accumulated reward per share, multiplied by precision factor for accuracy
    uint256 public accRewardPerShare;
    
    // Precision factor to handle small decimal values
    uint256 public constant PRECISION = 1e12;

    // Tracks the accumulated reward per share paid to each user
    mapping(address => uint256) public userRewardPerSharePaid;
    
    // Tracks rewards already claimed by users
    mapping(address => uint256) public claimedRewards;
    
    // Tracks the last epoch in which a user claimed rewards
    mapping(address => uint256) public lastClaimEpoch;

    /**
     * @dev Constructor
     * @param _underlying The underlying asset token (e.g., USDC)
     * @param _vault The vault contract address
     */
    constructor(address _underlying, address _vault) {
        require(_underlying != address(0), "Invalid underlying address");
        require(_vault != address(0), "Invalid vault address");

        underlying = IERC20(_underlying);
        vault = IVault(_vault);
    }

    /**
     * @dev Updates the global reward state with new rewards
     * @param epochReward The amount of rewards accrued in the current epoch
     */
    function updateRewardState(uint256 epochReward) external {
        uint256 totalWeightedShares = vault.getTotalTimeWeightedShares();
        
        if (totalWeightedShares == 0) return;

        // Calculate the reward per share and add to accumulator
        uint256 rewardPerShare = (epochReward * PRECISION) / totalWeightedShares;
        accRewardPerShare += rewardPerShare;
        
    }

    /**
     * @dev Updates the user's reward checkpoint
     * This marks that the user has been paid rewards up to the current accRewardPerShare
     * @param user The user address to update
     */
    function updateUserRewardDebt(address user) external {
        userRewardPerSharePaid[user] = accRewardPerShare;
        lastClaimEpoch[user] = vault.getCurrentEpoch();
    }

    /**
     * @dev Calculates pending rewards for a user
     * @param user The user address
     * @return Pending rewards for the user
     */
    function getPendingReward(address user) external view returns (uint256) {
        uint256 weightedShares = vault.getUserTimeWeightedShares(user);
        
        // No shares means no rewards
        if (weightedShares == 0) return 0;
        
        // Calculate rewards based on change in accRewardPerShare since last checkpoint
        uint256 rewardDelta = accRewardPerShare - userRewardPerSharePaid[user];
        uint256 pendingReward = (weightedShares * rewardDelta) / PRECISION;
        
        return pendingReward;
    }
    
    /**
     * @dev Records rewards claimed by a user
     * @param user The user address
     * @param amount The amount of rewards claimed
     */
    function recordClaimedReward(address user, uint256 amount) external {
        claimedRewards[user] += amount;
        lastClaimEpoch[user] = vault.getCurrentEpoch();
    }
    
    /**
     * @dev Gets the last epoch in which a user claimed rewards
     * @param user The user address
     * @return The last claim epoch
     */
    function getLastClaimEpoch(address user) external view returns (uint256) {
        return lastClaimEpoch[user];
    }
    
    /**
     * @dev Gets the current accumulated reward per share
     * @return The accumulated reward per share
     */
    function getAccRewardPerShare() external view returns (uint256) {
        return accRewardPerShare;
    }
    
    /**
     * @dev Gets the user's reward checkpoint
     * @param user The user address
     * @return The user's reward per share paid (checkpoint)
     */
    function getUserRewardPerSharePaid(address user) external view returns (uint256) {
        return userRewardPerSharePaid[user];
    }
    
    /**
     * @dev Gets the user's reward debt (alias for getUserRewardPerSharePaid for backward compatibility)
     * @param user The user address
     * @return The user's reward per share paid (checkpoint)
     */
    function getUserRewardDebt(address user) external view returns (uint256) {
        return userRewardPerSharePaid[user];
    }
    
    /**
     * @dev Gets the total rewards claimed by a user
     * @param user The user address
     * @return The total claimed rewards
     */
    function getUserClaimedReward(address user) external view returns (uint256) {
        return claimedRewards[user];
    }
    
    /**
     * @dev Resets a user's claimed rewards (typically when they exit completely)
     * @param user The user address
     */
    function resetClaimedReward(address user) external {
        claimedRewards[user] = 0;
        userRewardPerSharePaid[user] = 0;
        lastClaimEpoch[user] = 0;
    }
}