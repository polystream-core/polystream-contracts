// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// SyncSwap interfaces for router
interface ISyncSwapRouter {
    struct TokenInput {
        address token;
        uint amount;
    }

    // Add liquidity function
    function addLiquidity(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        address callback,
        bytes calldata callbackData
    ) external payable returns (uint liquidity);

    // Burn liquidity function
    function burnLiquidity(
        address pool,
        uint liquidity,
        bytes calldata data,
        uint[] calldata minAmounts,
        address callback,
        bytes calldata callbackData
    ) external returns (TokenAmount[] memory amounts);

    // Swap function
    function swap(
        address[] calldata paths,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external returns (uint256 amountOut);

    // Define TokenAmount struct to match what the contract expects
    struct TokenAmount {
        address token;
        uint amount;
    }
}

// Interface for the SyncSwap pool
interface ISyncSwapPool is IERC20 {
    function getTokens() external view returns (address token0, address token1);
    function swapFeeRate() external view returns (uint256);
}

// Interface for SyncSwap harvesting (if supported in the future)
interface ISyncSwapGauge {
    function getReward(address pool, address account) external returns (address[] memory rewardTokens, uint256[] memory amounts);
}

// Interface for price oracle
interface IPriceCalculator {
    function priceOf(address asset) external view returns (uint256 priceInUSD);
}

/**
 * @title SyncSwapAdapter
 * @notice Adapter for interacting with SyncSwap protocol with interest-based harvesting
 * @dev Implements the IProtocolAdapter interface
 */
contract SyncSwapAdapter is IProtocolAdapter, Ownable {
    // SyncSwap Router contract
    ISyncSwapRouter public immutable router;

    // Optional contracts for reward token harvesting (may not be used on Scroll)
    ISyncSwapGauge public gauge;
    IPriceCalculator public priceCalculator;
    
    // Mapping of asset address to pool address
    mapping(address => address) public pools;

    // Mapping of asset address to paired asset
    mapping(address => address) public pairedAssets;

    // Supported assets
    mapping(address => bool) public supportedAssets;

    // Protocol name
    string private constant PROTOCOL_NAME = "SyncSwap";

    // Fixed APY (3%)
    uint256 private constant FIXED_APY = 300;
    
    // Tracking initial deposits for profit calculation
    mapping(address => uint256) private initialDeposits;
    
    // Last harvest timestamp per asset
    mapping(address => uint256) public lastHarvestTimestamp;
    
    // Minimum reward amount to consider profitable after fees (per asset)
    mapping(address => uint256) public minRewardAmount;
    
    // WETH address for swap paths (for future reward token swaps)
    address public weth;
    
    /**
     * @dev Constructor
     * @param _routerAddress The address of the SyncSwap Router contract
     */
    constructor(address _routerAddress) Ownable(msg.sender) {
        router = ISyncSwapRouter(_routerAddress);
    }
    
    /**
     * @dev Set external contract addresses (optional for Scroll without rewards)
     * @param _gauge The address of SyncSwap Gauge contract
     * @param _priceCalculator The address of the price calculator
     * @param _weth The address of WETH
     */
    function setExternalContracts(
        address _gauge,
        address _priceCalculator,
        address _weth
    ) external onlyOwner {
        gauge = ISyncSwapGauge(_gauge);
        priceCalculator = IPriceCalculator(_priceCalculator);
        weth = _weth;
    }
    
    /**
     * @dev Add a supported stable pool
     * @param asset The primary asset (e.g., USDC)
     * @param pairedAsset The paired asset (e.g., USDT)
     * @param poolAddress The address of the stable pool
     */
    function addSupportedStablePool(
        address asset,
        address pairedAsset,
        address poolAddress
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(pairedAsset != address(0), "Invalid paired asset address");
        require(poolAddress != address(0), "Invalid pool address");

        pools[asset] = poolAddress;
        pairedAssets[asset] = pairedAsset;
        supportedAssets[asset] = true;
        
        // Set default min reward amount (0.1 units)
        uint8 decimals = IERC20Metadata(asset).decimals();
        minRewardAmount[asset] = 1 * 10**(decimals - 1); // 0.1 units
    }

    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset to remove
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        delete pools[asset];
        delete pairedAssets[asset];
        supportedAssets[asset] = false;
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
     * @dev Supply assets to SyncSwap
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of LP tokens received
     */
    function supply(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address poolAddress = pools[asset];
        require(poolAddress != address(0), "Pool not found");

        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
        // Update initial deposit tracking
        initialDeposits[asset] += amount;

        // Prepare inputs for addLiquidity
        ISyncSwapRouter.TokenInput[]
            memory inputs = new ISyncSwapRouter.TokenInput[](1);
        inputs[0] = ISyncSwapRouter.TokenInput({token: asset, amount: amount});

        // Approve router to spend asset
        IERC20(asset).approve(address(router), amount);

        // No slippage protection for simplicity
        uint256 minLiquidity = 0;

        // Encode recipient data (this contract, withdrawMode = 0)
        bytes memory data = abi.encode(address(this), uint8(0));

        // Add liquidity to SyncSwap
        uint256 liquidity = router.addLiquidity(
            poolAddress,
            inputs,
            data,
            minLiquidity,
            address(0), // No callback
            "" // No callback data
        );

        return liquidity;
    }

    /**
     * @dev Withdraw assets from SyncSwap
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address poolAddress = pools[asset];
        require(poolAddress != address(0), "Pool not found");

        // Get LP token balance
        uint256 lpBalance = IERC20(poolAddress).balanceOf(address(this));
        require(lpBalance > 0, "No LP tokens to withdraw");

        // For simplicity, we'll withdraw a fixed percentage of LP tokens
        uint256 lpToWithdraw = lpBalance / 10; // 10% of LP tokens

        // Approve ROUTER to spend LP tokens (not the pool itself)
        IERC20(poolAddress).approve(address(router), lpToWithdraw);

        // Prepare min amounts array (we need an array equal to the number of tokens in the pool)
        uint[] memory minAmounts = new uint[](2); // For a pair, we need 2 values
        minAmounts[0] = 1; // Minimal amount to allow any output
        minAmounts[1] = 1; // Minimal amount for the second token

        // Encode recipient data (this contract, withdrawMode = 1 for single asset, asset address)
        bytes memory data = abi.encode(address(this), uint8(1), asset);

        // Try to burn liquidity
        try
            router.burnLiquidity(
                poolAddress,
                lpToWithdraw,
                data,
                minAmounts,
                address(0), // No callback
                "" // No callback data
            )
        returns (ISyncSwapRouter.TokenAmount[] memory amounts) {
            // Find the amount of the asset received
            uint256 receivedAmount = 0;
            for (uint i = 0; i < amounts.length; i++) {
                if (amounts[i].token == asset) {
                    receivedAmount = amounts[i].amount;
                    break;
                }
            }

            // Transfer the asset to the sender
            if (receivedAmount > 0) {
                IERC20(asset).transfer(msg.sender, receivedAmount);
            }

            return receivedAmount;
        } catch {
            revert("Failed to burn liquidity");
        }
    }
    
    /**
     * @dev Harvest yield from the protocol by compounding interest
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in asset terms
     */
    function harvest(address asset) external override returns (uint256 harvestedAmount) {
        require(supportedAssets[asset], "Asset not supported");
        
        address poolAddress = pools[asset];
        require(poolAddress != address(0), "Pool not found");
        
        // Step 1: Withdraw all assets by burning all LP tokens
        uint256 lpBalance = IERC20(poolAddress).balanceOf(address(this));
        if (lpBalance == 0) {
            return 0; // Nothing to harvest
        }
        
        // Get initial asset balance
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));
        
        // Approve router to spend LP tokens
        IERC20(poolAddress).approve(address(router), lpBalance);
        
        // Prepare min amounts array (we need an array equal to the number of tokens in the pool)
        uint[] memory minAmounts = new uint[](2); // For a pair, we need 2 values
        minAmounts[0] = 1; // Minimal amount to allow any output
        minAmounts[1] = 1; // Minimal amount for the second token
        
        // Encode recipient data (this contract, withdrawMode = 1 for single asset, asset address)
        bytes memory data = abi.encode(address(this), uint8(1), asset);
        
        // Withdraw all assets as a single token
        ISyncSwapRouter.TokenAmount[] memory withdrawnAmounts;
        try router.burnLiquidity(
            poolAddress,
            lpBalance,
            data,
            minAmounts,
            address(0), // No callback
            "" // No callback data
        ) returns (ISyncSwapRouter.TokenAmount[] memory amounts) {
            withdrawnAmounts = amounts;
        } catch {
            revert("Failed to burn liquidity");
        }
        
        // Calculate withdrawn amount
        uint256 withdrawnAmount = 0;
        for (uint i = 0; i < withdrawnAmounts.length; i++) {
            if (withdrawnAmounts[i].token == asset) {
                withdrawnAmount = withdrawnAmounts[i].amount;
                break;
            }
        }
        
        if (withdrawnAmount == 0) {
            return 0; // Nothing was withdrawn
        }
        
        // Step 2: Calculate profit (withdrawn - initial deposit)
        uint256 initialDeposit = initialDeposits[asset];
        uint256 yieldAmount = 0;
        
        if (withdrawnAmount > initialDeposit) {
            yieldAmount = withdrawnAmount - initialDeposit;
        }
        
        // Step 3: Claim any reward tokens (if SyncSwap has a gauge for rewards in the future)
        if (address(gauge) != address(0)) {
            try this.claimSyncSwapRewards(poolAddress) {
                // Rewards claimed successfully (if any)
            } catch {
                // Ignore errors in reward claiming
            }
        }
        
        // Step 4: Redeposit all assets back into SyncSwap
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        
        // Update initial deposit tracking with new balance
        initialDeposits[asset] = assetBalance;
        
        // Redeposit into SyncSwap
        if (assetBalance > 0) {
            // Prepare inputs for addLiquidity
            ISyncSwapRouter.TokenInput[] memory inputs = new ISyncSwapRouter.TokenInput[](1);
            inputs[0] = ISyncSwapRouter.TokenInput({token: asset, amount: assetBalance});
            
            // Approve router to spend asset
            IERC20(asset).approve(address(router), assetBalance);
            
            // No slippage protection for simplicity
            uint256 minLiquidity = 0;
            
            // Encode recipient data (this contract, withdrawMode = 0)
            bytes memory redeposidData = abi.encode(address(this), uint8(0));
            
            // Add liquidity to SyncSwap
            router.addLiquidity(
                poolAddress,
                inputs,
                redeposidData,
                minLiquidity,
                address(0), // No callback
                "" // No callback data
            );
        }
        
        // Update last harvest timestamp
        lastHarvestTimestamp[asset] = block.timestamp;
        
        return yieldAmount;
    }
    
    /**
     * @dev Helper function to claim SyncSwap rewards (called via try/catch to handle potential errors)
     * @param poolAddress The address of the LP pool
     */
    function claimSyncSwapRewards(address poolAddress) external {
        require(msg.sender == address(this), "Only callable by self");
        require(address(gauge) != address(0), "Gauge not set");
        
        // Claim rewards (does nothing if no rewards are configured)
        gauge.getReward(poolAddress, address(this));
    }

    /**
     * @dev Get the current APY for an asset
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        // Fixed APY for simplicity
        return FIXED_APY;
    }

    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The current balance (estimated)
     */
    function getBalance(
        address asset
    ) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address poolAddress = pools[asset];
        if (poolAddress == address(0)) {
            return 0;
        }

        // Get LP tokens held by this contract
        uint256 lpBalance = IERC20(poolAddress).balanceOf(address(this));
        if (lpBalance == 0) {
            return 0;
        }

        // For a SyncSwap pool, a very rough estimation is that our stake represents
        // a fraction of the total asset in the pool. We'll use lpBalance / 1000
        // as an extremely simplified approximation.
        return lpBalance / 1000;
    }
    
    /**
     * @dev Check if an asset is supported
     * @param asset The address of the asset
     * @return True if the asset is supported
     */
    function isAssetSupported(
        address asset
    ) external view override returns (bool) {
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
     * @dev Get time since last harvest
     * @param asset The address of the asset
     * @return Time in seconds since last harvest (or 0 if never harvested)
     */
    function getTimeSinceLastHarvest(address asset) external view returns (uint256) {
        if (lastHarvestTimestamp[asset] == 0) {
            return 0;
        }
        return block.timestamp - lastHarvestTimestamp[asset];
    }
    
    /**
     * @dev Get estimated trading fees earned (very rough approximation)
     * @param asset The address of the asset
     * @return Estimated fees earned since initial deposit
     */
    function getEstimatedFees(address asset) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        
        address poolAddress = pools[asset];
        uint256 lpBalance = IERC20(poolAddress).balanceOf(address(this));
        
        if (lpBalance == 0) {
            return 0;
        }
        
        // Calculate estimated fees based on initial deposit and time elapsed
        uint256 initialDeposit = initialDeposits[asset];
        
        // Very rough estimation of 3% annual yield
        // (initialDeposit * 3% * timeElapsed / 365 days)
        uint256 timeElapsed = block.timestamp - lastHarvestTimestamp[asset];
        if (timeElapsed == 0 || lastHarvestTimestamp[asset] == 0) {
            timeElapsed = block.timestamp; // Assume from deployment time
        }
        
        return (initialDeposit * 3 * timeElapsed) / (365 days * 100);
    }

    /**
     * @dev Rescue tokens that are stuck in this contract
     * @param token The address of the token to rescue
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to rescue
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    function convertFeeToReward(address asset, uint256 fee) external {}

    function getTotalPrincipal(address asset) external view returns (uint256){
        return 1;
    }

    function withdrawToUser(address asset, uint256 amount, address user) external returns (uint256){
        return 1;
    }

    function getEstimatedInterest(
        address asset
    ) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address poolAddress = pools[asset];
        uint256 lpBalance = IERC20(poolAddress).balanceOf(address(this));

        if (lpBalance == 0) {
            return 0;
        }

        // Calculate estimated interest based on initial deposit and time elapsed
        uint256 initialDeposit = initialDeposits[asset];

        // Very rough estimation of 3% annual yield
        // (initialDeposit * 3% * timeElapsed / 365 days)
        uint256 timeElapsed = block.timestamp - lastHarvestTimestamp[asset];
        if (timeElapsed == 0 || lastHarvestTimestamp[asset] == 0) {
            timeElapsed = block.timestamp; // Assume from deployment time
        }

        return (initialDeposit * 3 * timeElapsed) / (365 days * 100);
    }



}