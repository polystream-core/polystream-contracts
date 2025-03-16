// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IVault
 * @notice Interface defining the required functions for the Vault contract
 */
interface IVault {
    /**
     * @dev Deposit assets into the vault
     * @param user Address of the user to deposit for
     * @param amount Amount of assets to deposit
     */
    function deposit(address user, uint256 amount) external;
    
    /**
     * @dev Withdraw assets from the vault
     * @param user Address of the user to withdraw for
     * @param amount Amount to withdraw
     */
    function withdraw(address user, uint256 amount) external;
    
    /**
     * @dev Check and harvest yield from all protocols
     */
    function checkAndHarvest() external returns (uint256 harvestedAmount);
    
    /**
     * @dev Get the current epoch
     * @return Current epoch number
     */
    function getCurrentEpoch() external view returns (uint256);
    
    /**
     * @dev Get all active users
     * @return Array of active user addresses
     */
    function getUsers() external view returns (address[] memory);
    
    /**
     * @dev Get user entry time (time of first deposit)
     * @param user Address of the user
     * @return Entry time of the user
     */
    function getUserEntryTime(address user) external view returns (uint256);
    
    /**
     * @dev Get total supply of user balances
     * @return Total supply
     */
    function getTotalSupply() external view returns (uint256);
    
    /**
     * @dev Get total time-weighted balances across all users
     * @return Total time-weighted balance
     */
    function getTotalTimeWeightedShares() external view returns (uint256);
    
    /**
     * @dev Get user time-weighted balance
     * @param user Address of the user
     * @return User's time-weighted balance
     */
    function getUserTimeWeightedShares(address user) external view returns (uint256);
    
    /**
     * @dev Get user balance 
     * @param account Address of the account
     * @return Balance of the account
     */
    function balanceOf(address account) external view returns (uint256);
}