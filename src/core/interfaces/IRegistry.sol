// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../adapters/interfaces/IProtocolAdapter.sol";

/**
 * @title IRegistry
 * @notice Interface for the protocol registry
 * @dev Registry for managing protocol adapters
 */
interface IRegistry {
    /**
     * @dev Register a protocol
     * @param protocolId The unique ID for the protocol
     * @param name The name of the protocol
     */
    function registerProtocol(uint256 protocolId, string memory name) external;
    
    /**
     * @dev Register an adapter for a specific protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @param adapter The address of the adapter
     */
    function registerAdapter(uint256 protocolId, address asset, address adapter) external;
    
    /**
     * @dev Remove an adapter
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     */
    function removeAdapter(uint256 protocolId, address asset) external;
    
    /**
     * @dev Get the adapter for a specific protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return The protocol adapter
     */
    function getAdapter(uint256 protocolId, address asset) external view returns (IProtocolAdapter);
    
    /**
     * @dev Get all registered protocol IDs
     * @return Array of protocol IDs
     */
    function getAllProtocolIds() external view returns (uint256[] memory);
    
    /**
     * @dev Get the name of a protocol
     * @param protocolId The ID of the protocol
     * @return The name of the protocol
     */
    function getProtocolName(uint256 protocolId) external view returns (string memory);
    
    /**
     * @dev Check if an adapter is registered for a protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return True if an adapter is registered
     */
    function hasAdapter(uint256 protocolId, address asset) external view returns (bool);
}