// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@account-abstraction/interfaces/IEntryPoint.sol";
import "./YieldVaultAccount.sol";

/**
 * @title YieldVaultAccountFactory
 * @notice Factory for creating YieldVaultAccount instances
 * @dev Uses Create2 for deterministic account addresses
 */
contract YieldVaultAccountFactory {
    // The EntryPoint contract
    IEntryPoint public immutable entryPoint;
    
    // Maps owner address to their account contract
    mapping(address => address) public getAccount;
    
    // Events
    event AccountCreated(address indexed owner, address indexed account, address indexed entryPoint);
    
    /**
     * @dev Constructor
     * @param _entryPoint The EntryPoint contract address
     */
    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }
    
    /**
     * @dev Create a new YieldVaultAccount for an owner
     * @param owner The owner of the account
     * @return account The created account contract address
     */
    function createAccount(address owner) external returns (address) {
        // Check if the owner already has an account
        address account = getAccount[owner];
        if (account != address(0)) {
            return account;
        }
        
        // Using salt based on owner address for deterministic deployment
        bytes32 salt = keccak256(abi.encodePacked(owner));
        
        // Create the account contract
        account = address(new YieldVaultAccount{salt: salt}(owner, entryPoint));
        
        // Store the account address
        getAccount[owner] = account;
        
        emit AccountCreated(owner, account, address(entryPoint));
        
        return account;
    }
    
    /**
     * @dev Calculate the counterfactual address of an account for an owner
     * @param owner The owner of the account
     * @return The account address (even if not yet deployed)
     */
    function getAccountAddress(address owner) public view returns (address) {
        // Check if account already exists
        address account = getAccount[owner];
        if (account != address(0)) {
            return account;
        }
        
        // Calculate the counterfactual address
        bytes32 salt = keccak256(abi.encodePacked(owner));
        bytes memory bytecode = _getCreationBytecode(owner);
        
        return Create2.computeAddress(salt, keccak256(bytecode));
    }
    
    /**
     * @dev Helper function to get the creation bytecode for an account
     * @param owner The owner of the account
     * @return The creation bytecode
     */
    function _getCreationBytecode(address owner) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(YieldVaultAccount).creationCode,
            abi.encode(owner, entryPoint)
        );
    }
}