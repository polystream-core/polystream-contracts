// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IVault
 * @notice Interface for the yield-generating vault
 */
interface IVault {
    /**
     * @dev Deposit assets into the vault
     * @param amount Amount of assets to deposit
     * @return shares Amount of shares minted
     */
    function deposit(uint256 amount) external returns (uint256 shares);
    
    /**
     * @dev Withdraw assets from the vault
     * @param shares Amount of shares to burn
     * @return amount Amount of assets withdrawn
     */
    function withdraw(uint256 shares) external returns (uint256 amount);
    
    /**
     * @dev Rebalance assets across protocols based on the target allocations
     */
    function rebalance() external;
    
    /**
     * @dev Get total assets managed by the vault (across all protocols and in the vault itself)
     * @return Total assets
     */
    function totalAssets() external view returns (uint256);
    
    /**
     * @dev Get the price per share (assets per share)
     * @return Price per share with 18 decimals precision
     */
    function getPricePerShare() external view returns (uint256);
}