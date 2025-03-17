// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";

/**
 * @title ProtocolRegistry
 * @notice Registry for managing protocol adapters with allocation support
 */
contract ProtocolRegistry is IRegistry {
    // Protocol ID => Asset => Adapter
    mapping(uint256 => mapping(address => address)) public adapters;
    
    // Protocol ID => name
    mapping(uint256 => string) public protocolNames;
    
    // Valid protocol IDs
    uint256[] public protocolIds;
    
    // Currently active protocol ID
    uint256 public activeProtocolId;
    
    // Owner address
    address public owner;
    
    // Authorized external caller (e.g., YieldOptimizer)
    address public authorizedCaller;

    // Events
    event ProtocolRegistered(uint256 indexed protocolId, string name);
    event AdapterRegistered(uint256 indexed protocolId, address indexed asset, address adapter);
    event AdapterRemoved(uint256 indexed protocolId, address indexed asset);
    event ActiveProtocolSet(uint256 indexed protocolId);
    event AuthorizedCallerUpdated(address indexed oldCaller, address indexed newCaller);
    
    // Modifier to check if the caller is the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    // Modifier to check if the caller is either the owner or the authorized caller
    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner || msg.sender == authorizedCaller, "Caller is not authorized");
        _;
    }

    /**
     * @dev Constructor
     */
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Register a protocol
     * @param protocolId The unique ID for the protocol
     * @param name The name of the protocol
     */
    function registerProtocol(uint256 protocolId, string memory name) external override onlyOwnerOrAuthorized {
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
    function registerAdapter(uint256 protocolId, address asset, address adapter) external override onlyOwnerOrAuthorized {
        require(bytes(protocolNames[protocolId]).length > 0, "Protocol not registered");
        require(IProtocolAdapter(adapter).isAssetSupported(asset), "Asset not supported by adapter");
        
        adapters[protocolId][asset] = adapter;
        
        // If this is the first adapter or no active protocol is set, make this the active protocol
        if (activeProtocolId == 0) {
            activeProtocolId = protocolId;
            emit ActiveProtocolSet(protocolId);
        }
        
        emit AdapterRegistered(protocolId, asset, adapter);
    }
    
    /**
     * @dev Remove an adapter
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     */
    function removeAdapter(uint256 protocolId, address asset) external override onlyOwnerOrAuthorized {
        require(adapters[protocolId][asset] != address(0), "Adapter not registered");
        
        delete adapters[protocolId][asset];
        
        // If the active protocol's adapter was removed, set active to 0
        if (activeProtocolId == protocolId) {
            activeProtocolId = 0;
        }
        
        emit AdapterRemoved(protocolId, asset);
    }
    
    /**
     * @dev Set the active protocol ID
     * @param protocolId The protocol ID to set as active
     */
    function setActiveProtocol(uint256 protocolId) external override onlyOwnerOrAuthorized {
        require(bytes(protocolNames[protocolId]).length > 0, "Protocol not registered");
        activeProtocolId = protocolId;
        emit ActiveProtocolSet(protocolId);
    }
    
    /**
     * @dev Set an authorized external caller (e.g., YieldOptimizer)
     * @param newCaller The address of the new authorized contract
     */
    function setAuthorizedCaller(address newCaller) external onlyOwner {
        require(newCaller != address(0), "Invalid address");
        emit AuthorizedCallerUpdated(authorizedCaller, newCaller);
        authorizedCaller = newCaller;
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
     * @dev Get the active adapter for an asset
     * @param asset The address of the asset
     * @return The active protocol adapter
     */
    function getActiveAdapter(address asset) external view override returns (IProtocolAdapter) {
        address adapterAddress = adapters[activeProtocolId][asset];
        require(adapterAddress != address(0), "Active adapter not found");
        
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
     * @dev Get the current active protocol ID
     * @return The active protocol ID
     */
    function getActiveProtocolId() external view override returns (uint256) {
        return activeProtocolId;
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

    /**
     * @dev Transfer ownership to a new address
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external override onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        owner = newOwner;
    }
}
