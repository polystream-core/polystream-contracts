// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Simplified Aave interfaces
interface IAavePoolMinimal {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
    
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

/**
 * @title AaveAdapter
 * @notice Adapter for interacting with Aave protocol
 * @dev Implements the IProtocolAdapter interface without using getReserveData
 */
contract AaveAdapter is IProtocolAdapter, Ownable {
    // Aave Pool contract
    IAavePoolMinimal public immutable pool;
    
    // Mapping of asset address to aToken address
    mapping(address => address) public aTokens;
    
    // Supported assets
    mapping(address => bool) public supportedAssets;
    
    // Protocol name
    string private constant PROTOCOL_NAME = "Aave V3";
    
    /**
     * @dev Constructor
     * @param _poolAddress The address of the Aave Pool contract
     */
    constructor(address _poolAddress) Ownable(msg.sender) {
        pool = IAavePoolMinimal(_poolAddress);
    }
    
    /**
     * @dev Add a supported asset with its corresponding aToken
     * @param asset The address of the asset to add
     * @param aToken The address of the corresponding aToken
     */
    function addSupportedAsset(address asset, address aToken) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(aToken != address(0), "Invalid aToken address");
        
        aTokens[asset] = aToken;
        supportedAssets[asset] = true;
    }
    
    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset to remove
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
    }
    
    /**
     * @dev Supply assets to Aave
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of aTokens received
     */
    function supply(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");
        
        // Get initial aToken balance
        uint256 balanceBefore = IERC20(aToken).balanceOf(address(this));
        
        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
        // Approve Aave pool to spend asset
        IERC20(asset).approve(address(pool), amount);
        
        // Supply asset to Aave
        pool.supply(asset, amount, address(this), 0);
        
        // Calculate aTokens received
        uint256 balanceAfter = IERC20(aToken).balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }
    
    /**
     * @dev Withdraw assets from Aave
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        // Withdraw asset from Aave
        uint256 withdrawn = pool.withdraw(asset, amount, msg.sender);
        
        return withdrawn;
    }
    
    //  TODO: Implement ACTUAL APY Calculation
    /**
     * @dev Get the current APY for an asset
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        // In this simplified version, we return a fixed APY
        // A real implementation would get this from Aave's data provider
        return 400; // 4.00% APY
    }
    
    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The current balance
     */
    function getBalance(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        address aToken = aTokens[asset];
        return IERC20(aToken).balanceOf(address(this));
    }
    
    /**
     * @dev Check if an asset is supported
     * @param asset The address of the asset
     * @return True if the asset is supported
     */
    function isAssetSupported(address asset) external view override returns (bool) {
        return supportedAssets[asset];
    }
    
    /**
     * @dev Get the name of the protocol
     * @return The protocol name
     */
    function getProtocolName() external pure override returns (string memory) {
        return PROTOCOL_NAME;
    }
    
    /**
     * @dev Rescue tokens that are stuck in this contract
     * @param token The address of the token to rescue
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to rescue
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}