// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title YieldToken
 * @notice Yield-generating token that represents a share in the vault
 * @dev This token (pyUSDC) is minted when users deposit and burned when they withdraw
 */
contract YieldToken is ERC20, ERC20Burnable, Ownable {
    // Only the vault can mint tokens
    address public vault;
    
    // The underlying asset (USDC)
    IERC20 public immutable asset;
    
    // Events
    event VaultUpdated(address indexed newVault);
    
    /**
     * @dev Modifier to restrict functions to the vault
     */
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }
    
    /**
     * @dev Constructor
     * @param _asset The address of the underlying asset (USDC)
     * @param name The name of the token (e.g., "Protected Yield USDC")
     * @param symbol The symbol of the token (e.g., "pyUSDC")
     */
    constructor(
        address _asset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) Ownable(msg.sender) {
        require(_asset != address(0), "Invalid asset address");
        asset = IERC20(_asset);
    }
    
    /**
     * @dev Set the vault address
     * @param _vault The address of the vault
     */
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault address");
        vault = _vault;
        emit VaultUpdated(_vault);
    }
    
    /**
     * @dev Mint new tokens (only callable by the vault)
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }
    
    /**
     * @dev Burn tokens (only callable by the vault)
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address from, uint256 amount) public override onlyVault {
        _burn(from, amount);
    }
    
    /**
     * @dev Get the decimals of the token
     * @return The number of decimals
     */
    function decimals() public view virtual override returns (uint8) {
        // Match the decimals of the underlying asset
        return IERC20Metadata(address(asset)).decimals();
    }
}