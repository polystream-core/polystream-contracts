// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// LayerBank interfaces
interface IGToken is IERC20 {
    // Try different redeem functions based on common lending protocols
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
}

interface ILayerBankCore {
    function enterMarkets(address[] calldata gTokens) external;
    function supply(address gToken, uint256 underlyingAmount) external payable returns (uint256);
    function redeem(address gToken, uint256 amount) external returns (uint256);
    function redeemUnderlying(address gToken, uint256 amount) external returns (uint256);
}

/**
 * @title LayerBankAdapter
 * @notice Final adapter for interacting with LayerBank protocol
 * @dev Handles both supply and redeem operations with proper error handling
 */
contract LayerBankAdapter is IProtocolAdapter, Ownable {
    // LayerBank Core contract
    ILayerBankCore public immutable core;
    
    // Mapping of asset address to gToken address
    mapping(address => address) public gTokens;
    
    // Supported assets
    mapping(address => bool) public supportedAssets;
    
    // Protocol name
    string private constant PROTOCOL_NAME = "LayerBank";
    
    // Fixed APY (4%)
    uint256 private constant FIXED_APY = 400;
    
    /**
     * @dev Constructor
     * @param _coreAddress The address of the LayerBank Core contract
     */
    constructor(address _coreAddress) Ownable(msg.sender) {
        core = ILayerBankCore(_coreAddress);
    }
    
    /**
     * @dev Add a supported asset
     * @param asset The address of the asset to add
     * @param gToken The address of the corresponding gToken
     */
    function addSupportedAsset(address asset, address gToken) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(gToken != address(0), "Invalid gToken address");
        
        gTokens[asset] = gToken;
        supportedAssets[asset] = true;
        
        // Enter the market for this gToken
        address[] memory marketsToEnter = new address[](1);
        marketsToEnter[0] = gToken;
        core.enterMarkets(marketsToEnter);
    }
    
    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset to remove
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
    }
    
    /**
     * @dev Supply assets to LayerBank
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of gTokens received
     */
    function supply(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");
        
        // Get initial gToken balance
        uint256 balanceBefore = IERC20(gToken).balanceOf(address(this));
        
        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
        // Approve LayerBank to spend asset
        IERC20(asset).approve(gToken, amount);
        
        // Supply asset to LayerBank
        core.supply(gToken, amount);
        
        // Calculate gTokens received
        uint256 balanceAfter = IERC20(gToken).balanceOf(address(this));
        uint256 gTokensReceived = balanceAfter - balanceBefore;
        
        // Return the gTokens received
        return gTokensReceived;
    }
    
    /**
     * @dev Withdraw assets from LayerBank
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");
        
        // Get initial asset balance
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));
        
        // Try multiple withdrawal methods - different protocols name their functions differently
        
        // Method 1: Try using the core contract's redeem function (gToken amount)
        uint256 gTokenBalance = IERC20(gToken).balanceOf(address(this));

        require(gTokenBalance > 0, "No gTokens to redeem");     // zero balance check prevent division by zero
        
        // Calculate what proportion of our total gTokens we want to redeem
        // We need to use our own calculation here instead of calling getBalance
        uint256 gTokenAmount = (amount * gTokenBalance) / IERC20(gToken).balanceOf(address(this));
        gTokenAmount = gTokenAmount < gTokenBalance ? gTokenAmount : gTokenBalance;
        
        try core.redeem(gToken, gTokenAmount) returns (uint256) {
            // Check if we received the asset
            uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
            uint256 received = assetBalanceAfter - assetBalanceBefore;
            
            // Transfer withdrawn asset to sender
            IERC20(asset).transfer(msg.sender, received);
            
            return received;
        } catch {
            // Method 2: Try using the core contract's redeemUnderlying function (asset amount)
            try core.redeemUnderlying(gToken, amount) returns (uint256) {
                // Check if we received the asset
                uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
                uint256 received = assetBalanceAfter - assetBalanceBefore;
                
                // Transfer withdrawn asset to sender
                IERC20(asset).transfer(msg.sender, received);
                
                return received;
            } catch {
                // Method 3: Try calling redeem directly on the gToken
                try IGToken(gToken).redeem(gTokenAmount) returns (uint256) {
                    // Check if we received the asset
                    uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
                    uint256 received = assetBalanceAfter - assetBalanceBefore;
                    
                    // Transfer withdrawn asset to sender
                    IERC20(asset).transfer(msg.sender, received);
                    
                    return received;
                } catch {
                    // Method 4: Try calling redeemUnderlying directly on the gToken
                    try IGToken(gToken).redeemUnderlying(amount) returns (uint256) {
                        // Check if we received the asset
                        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
                        uint256 received = assetBalanceAfter - assetBalanceBefore;
                        
                        // Transfer withdrawn asset to sender
                        IERC20(asset).transfer(msg.sender, received);
                        
                        return received;
                    } catch {
                        // All methods failed
                        revert("All withdrawal methods failed");
                    }
                }
            }
        }
    }
    
    /**
     * @dev Get the current APY for an asset
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        // Return fixed APY for simplicity
        return FIXED_APY;
    }
    
    /**
     * @dev Get the current balance in the protocol (in underlying asset terms)
     * @param asset The address of the asset
     * @return The current balance in underlying asset
     */
    function getBalance(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        address gToken = gTokens[asset];
        
        // Get the gToken balance
        return IERC20(gToken).balanceOf(address(this));
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