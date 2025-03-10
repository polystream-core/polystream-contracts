// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVault
 * @notice Interface defining the required functions for the Vault contract.
 */
interface IVault {
    function deposit(address user, uint256 amount) external;
    function withdraw(address user, uint256 shareAmount) external;
    
    function getTotalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    
    function getUsers() external view returns (address[] memory);
    function getUserEntryTime(address user) external view returns (uint256);
    
    function checkAndHarvest() external;
    function getCurrentEpoch() external view returns (uint256);
    function getTotalTimeWeightedShares() external view returns (uint256 total);
    function getUserTimeWeightedShares(address user) external view returns (uint256);
}
