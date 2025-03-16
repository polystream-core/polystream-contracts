// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IProtocolAdapter.sol";
import "../../tokens/mocks/MockUSDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockLayerBankAdapter
 * @notice A mock implementation of the LayerBank adapter for testing
 * @dev Implements the IProtocolAdapter interface with simulated exchange rates and yield
 */
contract MockLayerBankAdapter is IProtocolAdapter, Ownable {
    // Token instance
    IERC20 public immutable stakingToken;
    
    // Protocol name
    string private constant PROTOCOL_NAME = "Mock LayerBank";
    
    // Mapping of asset => gToken (mocked)
    mapping(address => address) public gTokens;
    
    // Supported assets
    mapping(address => bool) public supportedAssets;
    
    // Track total deposits
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
    
    // Exchange rates for gTokens (1 gToken = x underlying tokens)
    mapping(address => uint256) public exchangeRates;
    
    // gToken balances (mocked as if we held them)
    mapping(address => uint256) public gTokenBalances;
    
    // Events
    event Supplied(address indexed asset, uint256 amount, uint256 gTokensMinted);
    event Withdrawn(address indexed asset, uint256 amount, uint256 gTokensBurned);
    event Harvested(address indexed asset, uint256 yieldAmount);
    
    /**
     * @dev Constructor
     * @param _stakingToken The asset token this adapter supports
     */
    constructor(address _stakingToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        
        // Initialize with exchange rate of 1:1
        exchangeRates[_stakingToken] = 1e18;
        
        // Default APY of 4%
        assetAPY[_stakingToken] = 400;
    }
    
    /**
     * @dev Set the APY for an asset
     * @param asset The asset address
     * @param apy The APY in basis points (e.g., 400 = 4%)
     */
    function setAPY(address asset, uint256 apy) external onlyOwner {
        assetAPY[asset] = apy;
    }
    
    /**
     * @dev Register a supported asset
     * @param asset The address of the supported asset
     * @param gToken The mocked gToken address (can be the same as asset for testing)
     */
    function addSupportedAsset(address asset, address gToken) external onlyOwner {
        supportedAssets[asset] = true;
        gTokens[asset] = gToken;
        
        // Set default min reward amount (0.1 units)
        uint8 decimals = IERC20Metadata(asset).decimals();
        minRewardAmount[asset] = 1 * 10 ** (decimals - 1); // 0.1 units
        
        // Initialize exchange rate if not set
        if (exchangeRates[asset] == 0) {
            exchangeRates[asset] = 1e18;
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
        
        // Calculate gTokens based on the current exchange rate
        uint256 gTokenAmount = (receivedAmount * 1e18) / exchangeRates[asset];
        
        // Update total principal tracking
        totalPrincipal[asset] += receivedAmount;
        
        // Update total deposits
        totalDeposits[asset] += receivedAmount;
        
        // Update user balance (for tracking purposes)
        userBalances[asset][msg.sender] += receivedAmount;
        
        // Update gToken balance
        gTokenBalances[asset] += gTokenAmount;
        
        emit Supplied(asset, receivedAmount, gTokenAmount);
        
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
        
        // Calculate gTokens to burn based on current exchange rate
        uint256 gTokensToBurn = (withdrawAmount * 1e18) / exchangeRates[asset];
        
        // Ensure we don't burn more gTokens than we have
        if (gTokensToBurn > gTokenBalances[asset]) {
            gTokensToBurn = gTokenBalances[asset];
            withdrawAmount = (gTokensToBurn * exchangeRates[asset]) / 1e18;
        }
        
        // Update total principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }
        
        // Update gToken balance
        if (gTokensToBurn <= gTokenBalances[asset]) {
            gTokenBalances[asset] -= gTokensToBurn;
        } else {
            gTokenBalances[asset] = 0;
        }
        
        // Transfer the asset to the sender
        stakingToken.transfer(msg.sender, withdrawAmount);
        
        // Update user balance (for tracking purposes)
        if (userBalances[asset][msg.sender] >= withdrawAmount) {
            userBalances[asset][msg.sender] -= withdrawAmount;
        } else {
            userBalances[asset][msg.sender] = 0;
        }
        
        emit Withdrawn(asset, withdrawAmount, gTokensToBurn);
        
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
        
        // Calculate gTokens to burn based on current exchange rate
        uint256 gTokensToBurn = (withdrawAmount * 1e18) / exchangeRates[asset];
        
        // Ensure we don't burn more gTokens than we have
        if (gTokensToBurn > gTokenBalances[asset]) {
            gTokensToBurn = gTokenBalances[asset];
            withdrawAmount = (gTokensToBurn * exchangeRates[asset]) / 1e18;
        }
        
        // Update total principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }
        
        // Update gToken balance
        if (gTokensToBurn <= gTokenBalances[asset]) {
            gTokenBalances[asset] -= gTokensToBurn;
        } else {
            gTokenBalances[asset] = 0;
        }
        
        // Transfer the asset directly to the user
        stakingToken.transfer(user, withdrawAmount);
        
        // Update user balance (for tracking purposes)
        if (userBalances[asset][msg.sender] >= withdrawAmount) {
            userBalances[asset][msg.sender] -= withdrawAmount;
        } else {
            userBalances[asset][msg.sender] = 0;
        }
        
        emit Withdrawn(asset, withdrawAmount, gTokensToBurn);
        
        return withdrawAmount;
    }
    
    /**
     * @dev Harvest yield by simulating interest accrual through exchange rate changes
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
        
        // Calculate the increase in exchange rate based on APY
        // exchangeRateIncrease = currentExchangeRate * APY * timeElapsed / year
        uint256 currentRate = exchangeRates[asset];
        uint256 rateIncrease = (currentRate * assetAPY[asset] * timeElapsed) / (365 days * 10000);
        
        // Update exchange rate
        exchangeRates[asset] = currentRate + rateIncrease;
        
        // Calculate yield amount based on the current principal and exchange rate change
        uint256 oldValue = (gTokenBalances[asset] * currentRate) / 1e18;
        uint256 newValue = (gTokenBalances[asset] * exchangeRates[asset]) / 1e18;
        uint256 yieldAmount = newValue > oldValue ? newValue - oldValue : 0;
        
        // For mock purposes, mint the yield directly to this adapter
        // This simulates the actual tokens that would be available in a real lending protocol
        if (yieldAmount > 0) {
            MockUSDC(asset).mint(address(this), yieldAmount);
        }
        
        // Update last harvest timestamp
        lastHarvestTimestamp[asset] = block.timestamp;
        
        emit Harvested(asset, yieldAmount);
        
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
        
        // Calculate and reduce gTokens equivalent to the fee
        uint256 gTokensToReduce = (fee * 1e18) / exchangeRates[asset];
        if (gTokensToReduce <= gTokenBalances[asset]) {
            gTokenBalances[asset] -= gTokensToReduce;
        }
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
        
        // Calculate the underlying balance based on gToken balance and exchange rate
        return (gTokenBalances[asset] * exchangeRates[asset]) / 1e18;
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
        
        // Calculate the increase in exchange rate based on APY
        uint256 currentRate = exchangeRates[asset];
        uint256 rateIncrease = (currentRate * assetAPY[asset] * timeElapsed) / (365 days * 10000);
        
        // Calculate yield amount based on the current gToken balance and expected exchange rate
        uint256 oldValue = (gTokenBalances[asset] * currentRate) / 1e18;
        uint256 newValue = (gTokenBalances[asset] * (currentRate + rateIncrease)) / 1e18;
        
        return newValue > oldValue ? newValue - oldValue : 0;
    }
    
    /**
     * @dev Set the exchange rate for an asset
     * @param asset The asset address
     * @param newRate The new exchange rate
     */
    function setExchangeRate(address asset, uint256 newRate) external onlyOwner {
        require(supportedAssets[asset], "Asset not supported");
        require(newRate > 0, "Exchange rate must be greater than 0");
        
        exchangeRates[asset] = newRate;
    }
    
    /**
     * @dev Get the current exchange rate
     * @param asset The asset address
     * @return The current exchange rate
     */
    function getExchangeRate(address asset) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return exchangeRates[asset];
    }
    
    /**
     * @dev Get the current gToken balance
     * @param asset The asset address
     * @return The current gToken balance
     */
    function getGTokenBalance(address asset) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return gTokenBalances[asset];
    }
}