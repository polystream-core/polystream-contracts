// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IProtocolAdapter
 * @notice Enhanced interface for protocol adapters with consistent return values
 */
interface IProtocolAdapter {
    /**
     * @dev Supply assets to the underlying protocol
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were successfully supplied
     */
    function supply(address asset, uint256 amount) external returns (uint256);
    
    /**
     * @dev Withdraw assets from the underlying protocol
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @return The amount of underlying tokens successfully withdrawn
     */
    function withdraw(address asset, uint256 amount) external returns (uint256);
    
    /**
     * @dev Withdraw assets from the underlying protocol and send directly to a user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @param user The address of the user to receive the withdrawn assets
     * @return The amount of underlying tokens successfully withdrawn and sent to user
     */
    function withdrawToUser(address asset, uint256 amount, address user) external returns (uint256);
    
    /**
     * @dev Harvest yield from the protocol by compounding interest
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in underlying asset terms
     */
    function harvest(address asset) external returns (uint256 harvestedAmount);
    
    /**
     * @dev Convert fees to additional yield in the protocol
     * @param asset The address of the asset
     * @param fee The amount of fee to convert to yield
     */
    function convertFeeToReward(address asset, uint256 fee) external;

    /**
     * @dev Get the current APY for a specific asset
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view returns (uint256);
    
    /**
     * @dev Get the current balance in the protocol in underlying asset terms
     * @param asset The address of the asset
     * @return The current balance in underlying asset units
     */
    function getBalance(address asset) external view returns (uint256);
    
    /**
     * @dev Get the total principal amount deposited in this protocol
     * @param asset The address of the asset
     * @return The total principal amount in underlying asset units
     */
    function getTotalPrincipal(address asset) external view returns (uint256);
    
    /**
     * @dev Check if an asset is supported by this protocol adapter
     * @param asset The address of the asset to check
     * @return True if the asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool);

    /**
     * @dev Get the name of the protocol
     * @return The name of the protocol
     */
    function getProtocolName() external view returns (string memory);
    
    /**
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(address asset, uint256 amount) external;
    
    /**
     * @dev Get the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @return The minimum reward amount
     */
    function getEstimatedInterest(address asset) external view returns (uint256);
}