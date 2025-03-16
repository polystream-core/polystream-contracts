// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice A mock USDC token for testing purposes
 * @dev Implements the ERC20 standard with 6 decimals like real USDC
 */
contract MockUSDC is ERC20, Ownable {
    uint8 private constant _decimals = 6;
    
    // Mapping of approved minters
    mapping(address => bool) public minters;
    
    // Events
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    
    /**
     * @dev Constructor
     * @param initialOwner The initial owner of the contract
     */
    constructor(address initialOwner) ERC20("Mock USDC", "mUSDC") Ownable(initialOwner) {}
    
    /**
     * @dev Returns the number of decimals used for the token
     * @return The number of decimals (6 for USDC)
     */
    function decimals() public pure override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Add a new minter
     * @param minter The address to add as a minter
     */
    function addMinter(address minter) external onlyOwner {
        minters[minter] = true;
        emit MinterAdded(minter);
    }
    
    /**
     * @dev Remove a minter
     * @param minter The address to remove as a minter
     */
    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }
    
    /**
     * @dev Mints tokens to a specified address (owner or approved minters can call)
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == owner() || minters[msg.sender], "Only owner or minters can mint");
        _mint(to, amount);
    }
    
    /**
     * @dev Burns tokens from the caller's address
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev Faucet function to get test tokens (anyone can call)
     * @return true if successful
     */
    function faucet() external returns (bool) {
        // Mint 1000 USDC (1000 * 10^6)
        _mint(msg.sender, 1000 * 10**_decimals);
        return true;
    }
}