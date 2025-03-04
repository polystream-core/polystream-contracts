// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";

/**
 * @title ProtocolRegistry
 * @notice Registry for managing protocol adapters
 * @dev Implements the IRegistry interface
 */
contract ProtocolRegistry is IRegistry, Ownable {
    // Protocol ID => Asset => Adapter
    mapping(uint256 => mapping(address => address)) public adapters;
    
    // Protocol ID => name
    mapping(uint256 => string) public protocolNames;
    
    // Valid protocol IDs
    uint256[] public protocolIds;
    
    // Events
    event ProtocolRegistered(uint256 indexed protocolId, string name);
    event AdapterRegistered(uint256 indexed protocolId, address indexed asset, address adapter);
    event AdapterRemoved(uint256 indexed protocolId, address indexed asset);
    
    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Register a protocol
     * @param protocolId The unique ID for the protocol
     * @param name The name of the protocol
     */
    function registerProtocol(uint256 protocolId, string memory name) external override onlyOwner {
        require(bytes(protocolNames[protocolId]).length == 0, "Protocol ID already used");
        
        protocolNames[protocolId] = name;
        protocolIds.push(protocolId);
        
        emit ProtocolRegistered(protocolId, name);
    }
    
    /**
     * @dev Register an adapter for a specific protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @param adapter The address of the adapter
     */
    function registerAdapter(uint256 protocolId, address asset, address adapter) external override onlyOwner {
        require(bytes(protocolNames[protocolId]).length > 0, "Protocol not registered");
        require(IProtocolAdapter(adapter).isAssetSupported(asset), "Asset not supported by adapter");
        
        adapters[protocolId][asset] = adapter;
        
        emit AdapterRegistered(protocolId, asset, adapter);
    }
    
    /**
     * @dev Remove an adapter
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     */
    function removeAdapter(uint256 protocolId, address asset) external override onlyOwner {
        require(adapters[protocolId][asset] != address(0), "Adapter not registered");
        
        delete adapters[protocolId][asset];
        
        emit AdapterRemoved(protocolId, asset);
    }
    
    /**
     * @dev Get the adapter for a specific protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return The protocol adapter
     */
    function getAdapter(uint256 protocolId, address asset) external view override returns (IProtocolAdapter) {
        address adapterAddress = adapters[protocolId][asset];
        require(adapterAddress != address(0), "Adapter not found");
        
        return IProtocolAdapter(adapterAddress);
    }
    
    /**
     * @dev Get all registered protocol IDs
     * @return Array of protocol IDs
     */
    function getAllProtocolIds() external view override returns (uint256[] memory) {
        return protocolIds;
    }
    
    /**
     * @dev Get the name of a protocol
     * @param protocolId The ID of the protocol
     * @return The name of the protocol
     */
    function getProtocolName(uint256 protocolId) external view override returns (string memory) {
        string memory name = protocolNames[protocolId];
        require(bytes(name).length > 0, "Protocol not registered");
        
        return name;
    }
    
    /**
     * @dev Check if an adapter is registered for a protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return True if an adapter is registered
     */
    function hasAdapter(uint256 protocolId, address asset) external view override returns (bool) {
        return adapters[protocolId][asset] != address(0);
    }
}