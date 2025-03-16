// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IProtocolAdapter.sol";
import "../../tokens/mocks/MockUSDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockAaveAdapter
 * @notice A mock implementation of the Aave adapter for testing
 * @dev Implements the IProtocolAdapter interface with simulated yield generation
 */
contract MockAaveAdapter is IProtocolAdapter, Ownable {
    // Token instance
    IERC20 public immutable stakingToken;
    
    // Protocol name
    string private constant PROTOCOL_NAME = "Mock Aave V3";
    
    // Mapping of asset => aToken (mocked)
    mapping(address => address) public aTokens;
    
    // Supported assets
    mapping(address => bool) public supportedAssets;
    
    // Tracking total deposits
    mapping(address => uint256) public totalDeposits;
    
    // Track user balances (asset => user => balance)
    mapping(address => mapping(address => uint256)) private userBalances;
    
    // Track total principal per asset
    mapping(address => uint256) public totalPrincipal;
    
    // Minimum reward amount to consider profitable after fees (per asset)
    mapping(address => uint256) public minRewardAmount;
    
    // APY settings (in basis points - 1% = 100)
    mapping(address => uint256) private assetAPY;
    
    // Last harvest timestamp per asset
    mapping(address => uint256) public lastHarvestTimestamp;
    
    // Last exchange rate (for interest calculation)
    mapping(address => uint256) public lastExchangeRate;
    
    // Current exchange rate
    mapping(address => uint256) public currentExchangeRate;
    
    /**
     * @dev Constructor
     * @param _stakingToken The asset token this adapter supports
     */
    constructor(address _stakingToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        
        // Initialize with exchange rate of 1:1
        lastExchangeRate[_stakingToken] = 1e18;
        currentExchangeRate[_stakingToken] = 1e18;
        
        // Default APY of 5%
        assetAPY[_stakingToken] = 500;
    }
    
    /**
     * @dev Set the APY for an asset
     * @param asset The asset address
     * @param apy The APY in basis points (e.g., 500 = 5%)
     */
    function setAPY(address asset, uint256 apy) external onlyOwner {
        assetAPY[asset] = apy;
    }
    
    /**
     * @dev Register a supported asset
     * @param asset The address of the supported asset
     * @param aToken The mocked aToken address (can be the same as asset for testing)
     */
    function addSupportedAsset(address asset, address aToken) external onlyOwner {
        supportedAssets[asset] = true;
        aTokens[asset] = aToken;
        
        // Set default min reward amount (0.1 units)
        uint8 decimals = IERC20Metadata(asset).decimals();
        minRewardAmount[asset] = 1 * 10 ** (decimals - 1); // 0.1 units
        
        // Initialize exchange rates if not set
        if (lastExchangeRate[asset] == 0) {
            lastExchangeRate[asset] = 1e18;
            currentExchangeRate[asset] = 1e18;
        }
    }
    
    /**
     * @dev Supply assets to the protocol
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount that was actually supplied
     */
    function supply(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        // Get initial underlying token balance to verify transfer
        uint256 initialBalance = stakingToken.balanceOf(address(this));
        
        // Transfer asset from sender to this contract
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        // Verify the transfer
        uint256 receivedAmount = stakingToken.balanceOf(address(this)) - initialBalance;
        
        // Update total principal tracking
        totalPrincipal[asset] += receivedAmount;
        
        // Update total deposits
        totalDeposits[asset] += receivedAmount;
        
        // Update user balance (for tracking purposes)
        userBalances[asset][msg.sender] += receivedAmount;
        
        return receivedAmount;
    }
    
    /**
     * @dev Withdraw assets from the protocol
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        // Calculate max withdrawal amount (total principal)
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;
        
        // Update total principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }
        
        // Transfer the asset to the sender
        stakingToken.transfer(msg.sender, withdrawAmount);
        
        // Update user balance (for tracking purposes)
        if (userBalances[asset][msg.sender] >= withdrawAmount) {
            userBalances[asset][msg.sender] -= withdrawAmount;
        } else {
            userBalances[asset][msg.sender] = 0;
        }
        
        return withdrawAmount;
    }
    
    /**
     * @dev Withdraw assets from the protocol and send directly to user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @param user The address to receive the withdrawn assets
     * @return The actual amount withdrawn
     */
    function withdrawToUser(address asset, uint256 amount, address user) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(user != address(0), "Invalid user address");
        
        // Calculate max withdrawal amount (total principal)
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;
        
        // Update total principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }
        
        // Transfer the asset directly to the user
        stakingToken.transfer(user, withdrawAmount);
        
        // Update user balance (for tracking purposes)
        if (userBalances[asset][msg.sender] >= withdrawAmount) {
            userBalances[asset][msg.sender] -= withdrawAmount;
        } else {
            userBalances[asset][msg.sender] = 0;
        }
        
        return withdrawAmount;
    }
    
    /**
     * @dev Harvest yield by simulating interest accrual
     * @param asset The address of the asset
     * @return The harvested amount
     */
    function harvest(address asset) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        // Calculate time since last harvest
        uint256 timeElapsed;
        if (lastHarvestTimestamp[asset] == 0) {
            timeElapsed = 1 days; // Default to 1 day for first harvest
        } else {
            timeElapsed = block.timestamp - lastHarvestTimestamp[asset];
        }
        
        // Calculate yield (simple APY formula)
        // yield = principal * APY * timeElapsed / year
        uint256 principal = totalPrincipal[asset];
        uint256 yieldAmount = (principal * assetAPY[asset] * timeElapsed) / (365 days * 10000);
        
        // Increase exchange rate to simulate yield accrual
        if (principal > 0) {
            uint256 ratio = (yieldAmount * 1e18) / principal;
            currentExchangeRate[asset] = lastExchangeRate[asset] + ratio;
            
            // For mock purposes, mint the yield directly to this adapter
            // This simulates the actual tokens that would be available in a real lending protocol
            MockUSDC(asset).mint(address(this), yieldAmount);
        }
        
        // Update last harvest timestamp
        lastHarvestTimestamp[asset] = block.timestamp;
        
        // Store current exchange rate as last for next cycle
        lastExchangeRate[asset] = currentExchangeRate[asset];
        
        return yieldAmount;
    }
    
    /**
     * @dev Convert fee to reward
     * @param asset The address of the asset
     * @param fee The amount of fee to convert
     */
    function convertFeeToReward(address asset, uint256 fee) external override {
        require(supportedAssets[asset], "Asset not supported");
        require(fee > 0, "Fee must be greater than 0");
        require(fee <= totalPrincipal[asset], "Fee exceeds total principal");
        
        // Reduce total principal by the fee amount
        totalPrincipal[asset] -= fee;

    }
    
    /**
     * @dev Get the current APY
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return assetAPY[asset];
    }
    
    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The current balance
     */
    function getBalance(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        // For testing, the "aToken" balance is just the balance of the underlying asset
        return stakingToken.balanceOf(address(this));
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
     * @dev Get the total principal amount
     * @param asset The address of the asset
     * @return The total principal amount
     */
    function getTotalPrincipal(address asset) external view override returns (uint256) {
        return totalPrincipal[asset];
    }
    
    /**
     * @dev Get the name of the protocol
     * @return The protocol name
     */
    function getProtocolName() external pure override returns (string memory) {
        return PROTOCOL_NAME;
    }
    
    /**
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(address asset, uint256 amount) external override onlyOwner {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }
    
    /**
     * @dev Get the estimated interest
     * @param asset The address of the asset
     * @return The estimated interest
     */
    function getEstimatedInterest(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        // Calculate time since last harvest
        uint256 timeElapsed;
        if (lastHarvestTimestamp[asset] == 0) {
            timeElapsed = 1 days; // Default to 1 day for first estimate
        } else {
            timeElapsed = block.timestamp - lastHarvestTimestamp[asset];
        }
        
        // Calculate yield (simple APY formula)
        // yield = principal * APY * timeElapsed / year
        uint256 principal = totalPrincipal[asset];
        uint256 yieldAmount = (principal * assetAPY[asset] * timeElapsed) / (365 days * 10000);
        
        return yieldAmount;
    }
}