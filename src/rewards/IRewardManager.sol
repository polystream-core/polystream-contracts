// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewardManager {
    function pendingReward(address user) external view returns (uint256);
    function updateUserRewardDebt(address user) external;
    function claimReward(address user) external;
    function updateRewardState(uint256 epochReward) external;
    function getAccRewardPerShare() external view returns (uint256);
    function recordClaimedReward(address user, uint256 amount) external;
    function getUserRewardDebt(address user) external view returns (uint256);
    function getUserClaimedReward(address user) external view returns (uint256);
    function resetClaimedReward(address user) external;
    function getUserRewardPerSharePaid(address user) external view returns (uint256);
    function getPendingReward(address user) external view returns (uint256);
}
