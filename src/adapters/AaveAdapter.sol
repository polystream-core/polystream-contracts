// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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

// Adding IPool interface for getReserveData
interface IPool {
    function getReserveData(address asset) external view returns (DataTypes.ReserveDataLegacy memory);
}

library DataTypes {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveDataLegacy {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}

// Aave price oracle interface
interface IPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256);
    function BASE_CURRENCY_UNIT() external view returns (uint256);
}

// Aave rewards interface
interface IRewardsController {
    function claimAllRewards(
        address[] calldata assets,
        address to
    )
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

// SyncSwap Router interface for future reward token swaps
interface ISyncSwapRouter {
    struct TokenInput {
        address token;
        uint amount;
    }

    // Swap function
    function swap(
        address[] calldata paths,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

/**
 * @title AaveAdapter
 * @notice Adapter for interacting with Aave protocol with interest-based harvesting
 * @dev Implements the IProtocolAdapter interface
 */
contract AaveAdapter is IProtocolAdapter, Ownable {
    // Aave Pool contract
    IAavePoolMinimal public immutable pool;

    // Optional contracts for reward token harvesting (may not be used on Scroll)
    IRewardsController public rewardsController;
    IPriceOracleGetter public priceOracle;
    ISyncSwapRouter public syncSwapRouter;

    // Mapping of asset address to aToken address
    mapping(address => address) public aTokens;

    // Supported assets
    mapping(address => bool) public supportedAssets;

    // Protocol name
    string private constant PROTOCOL_NAME = "Aave V3";

    // Tracking initial deposits for profit calculation
    mapping(address => uint256) private initialDeposits;

    // Last harvest timestamp per asset
    mapping(address => uint256) public lastHarvestTimestamp;

    // Minimum reward amount to consider profitable after fees (per asset)
    mapping(address => uint256) public minRewardAmount;

    // Add tracking for total principal per asset
    mapping(address => uint256) public totalPrincipal;

    // WETH address for swap paths (for future reward token swaps)
    address public weth;

    // SyncSwap pool addresses for common pairs (for future reward token swaps)
    mapping(address => mapping(address => address)) public poolAddresses;

    /**
     * @dev Constructor
     * @param _poolAddress The address of the Aave Pool contract
     */
    constructor(address _poolAddress) Ownable(msg.sender) {
        pool = IAavePoolMinimal(_poolAddress);
    }

    /**
     * @dev Set external contract addresses (optional for Scroll without rewards)
     * @param _rewardsController The address of Aave Rewards Controller
     * @param _priceOracle The address of Aave price oracle
     * @param _syncSwapRouter The address of the SyncSwap router
     * @param _weth The address of WETH
     */
    function setExternalContracts(
        address _rewardsController,
        address _priceOracle,
        address _syncSwapRouter,
        address _weth
    ) external onlyOwner {
        rewardsController = IRewardsController(_rewardsController);
        priceOracle = IPriceOracleGetter(_priceOracle);
        syncSwapRouter = ISyncSwapRouter(_syncSwapRouter);
        weth = _weth;
    }

    /**
     * @dev Configure a pool for a token pair in SyncSwap (for future reward token swaps)
     * @param tokenA First token in the pair
     * @param tokenB Second token in the pair
     * @param poolAddress Address of the SyncSwap pool
     */
    function configurePool(
        address tokenA,
        address tokenB,
        address poolAddress
    ) external onlyOwner {
        require(
            tokenA != address(0) && tokenB != address(0),
            "Invalid token addresses"
        );
        require(poolAddress != address(0), "Invalid pool address");

        // Configure pool for both directions
        poolAddresses[tokenA][tokenB] = poolAddress;
        poolAddresses[tokenB][tokenA] = poolAddress;
    }

    /**
     * @dev Add a supported asset with its corresponding aToken
     * @param asset The address of the asset to add
     * @param aToken The address of the corresponding aToken
     */
    function addSupportedAsset(
        address asset,
        address aToken
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(aToken != address(0), "Invalid aToken address");

        aTokens[asset] = aToken;
        supportedAssets[asset] = true;

        // Set default min reward amount (0.1 units)
        uint8 decimals = IERC20Metadata(asset).decimals();
        minRewardAmount[asset] = 1 * 10 ** (decimals - 1); // 0.1 units
    }

    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset to remove
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
    }

    /**
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(
        address asset,
        uint256 amount
    ) external override onlyOwner {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }

    /**
     * @dev Supply assets to Aave
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were successfully supplied
     */
    function supply(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Get initial aToken balance
        uint256 balanceBefore = IERC20(aToken).balanceOf(address(this));

        // Get initial underlying token balance to verify transfer
        uint256 initialBalance = IERC20(asset).balanceOf(address(this));

        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Verify the transfer
        uint256 receivedAmount = IERC20(asset).balanceOf(address(this)) - initialBalance;

        // Update initial deposit tracking
        initialDeposits[asset] += amount;

        // Update total principal tracking
        totalPrincipal[asset] += amount;

        // Approve Aave pool to spend asset
        IERC20(asset).approve(address(pool), amount);

        // Supply asset to Aave
        pool.supply(asset, amount, address(this), 0);

        // return the underlying amount that was supplied
        return receivedAmount;
    }

    /**
     * @dev Withdraw assets from Aave
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

        // Calculate max withdrawal amount (total principal)
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;

        //get initial asset balance
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));

        // Withdraw asset from Aave to this contract
        uint256 withdrawn = pool.withdraw(asset, withdrawAmount, address(this));

        // Verify the withdrawal - calculate actual amount received
        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
        uint256 actualWithdrawn = assetBalanceAfter - assetBalanceBefore;

        //Update total principal
        if( actualWithdrawn <= totalPrincipal[asset]){
            totalPrincipal[asset] -= actualWithdrawn;
        } else {
            totalPrincipal[asset] = 0;
        }

        //transfer withdrawn assets to sender
        IERC20(asset).approve(address(pool), actualWithdrawn);
        IERC20(asset).transfer(msg.sender, actualWithdrawn);

        return actualWithdrawn;
    }

      /**
     * @dev Withdraw assets from Aave and send directly to user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @param user The address to receive the withdrawn assets
     * @return The actual amount withdrawn
     */
    function withdrawToUser(address asset, uint256 amount, address user) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(user != address(0), "Invalid user address");

        // Calculate the maximum amount that can be withdrawn
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;

        // Get initial user balance
        uint256 userBalanceBefore = IERC20(asset).balanceOf(user);

        // Withdraw asset from Aave directly to the user
        uint256 withdrawn = pool.withdraw(asset, withdrawAmount, user);
        
        // Verify the withdrawal - calculate actual amount received
        uint256 userBalanceAfter = IERC20(asset).balanceOf(user);
        uint256 actualReceived = userBalanceAfter - userBalanceBefore;

        // Update total principal
        if (actualReceived <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= actualReceived;
        } else {
            totalPrincipal[asset] = 0;
        }

        return actualReceived;
    }

    /**
     * @dev Convert fees to rewards in the protocol
     * @param asset The address of the asset
     * @param fee The amount of fee to convert
     */
    function convertFeeToReward(address asset, uint256 fee) external override {
        require(supportedAssets[asset], "Asset not supported");
        require(fee > 0, "Fee must be greater than 0");
        require(fee <= totalPrincipal[asset], "Fee exceeds total principal");
        
        // Reduce the total principal to convert fee to yield
        totalPrincipal[asset] -= fee;
    }

    /**
     * @dev Harvest yield from the protocol by compounding interest
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in asset terms
     */
    function harvest(
        address asset
    ) external override returns (uint256 harvestedAmount) {
        require(supportedAssets[asset], "Asset not supported");

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Step 1: Withdraw all assets from Aave
        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
        if (aTokenBalance == 0) {
            return 0; // Nothing to harvest
        }

        uint256 withdrawnAmount = pool.withdraw(
            asset,
            type(uint256).max,
            address(this)
        );

        // Step 2: Calculate yield (withdrawn - initial deposit)
        uint256 initialDeposit = initialDeposits[asset];
        uint256 yieldAmount = 0;

        if (withdrawnAmount > initialDeposit) {
            yieldAmount = withdrawnAmount - initialDeposit;
        }

        // Step 3: Claim any available reward tokens (even if not expected on Scroll)
        if (address(rewardsController) != address(0)) {
            try this.claimAaveRewards(asset) {
                // Rewards claimed successfully (if any)
            } catch {
                // Ignore errors in reward claiming
            }
        }

        // Step 4: Redeposit all assets back into Aave
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));

        // Update initial deposit tracking with new balance
        initialDeposits[asset] = assetBalance;

        // Approve Aave pool to spend asset
        IERC20(asset).approve(address(pool), assetBalance);

        // Supply asset back to Aave
        pool.supply(asset, assetBalance, address(this), 0);

        // Update last harvest timestamp
        lastHarvestTimestamp[asset] = block.timestamp;

        return yieldAmount;
    }

    /**
     * @dev Get total principal amount for this asset
     * @param asset The address of the asset
     * @return The total principal amount
     */
    function getTotalPrincipal(address asset) external view override returns (uint256) {
        return totalPrincipal[asset];
    }

    /**
     * @dev Helper function to claim Aave rewards (called via try/catch to handle potential errors)
     * @param asset The address of the asset
     */
    function claimAaveRewards(address asset) external {
        require(msg.sender == address(this), "Only callable by self");
        require(
            address(rewardsController) != address(0),
            "Rewards controller not set"
        );

        address aToken = aTokens[asset];
        address[] memory assets = new address[](1);
        assets[0] = aToken;

        // Claim rewards (does nothing if no rewards are configured)
        rewardsController.claimAllRewards(assets, address(this));
    }

    /**
     * @dev Get the current APY for an asset
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        // Get the current liquidity rate from Aave's pool
        DataTypes.ReserveDataLegacy memory reserveData = IPool(address(pool))
            .getReserveData(asset);

        // Convert the liquidity rate from RAY units (1e27) to basis points (1% = 100)
        uint256 ONE_RAY = 1e27;
        uint256 apyBps = (reserveData.currentLiquidityRate * 10000) / ONE_RAY;

        return apyBps;
    }

    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The current balance in aTokens
     */
    function getBalance(
        address asset
    ) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address aToken = aTokens[asset];
        return IERC20(aToken).balanceOf(address(this));
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
    function getTimeSinceLastHarvest(
        address asset
    ) external view returns (uint256) {
        if (lastHarvestTimestamp[asset] == 0) {
            return 0;
        }
        return block.timestamp - lastHarvestTimestamp[asset];
    }

    /**
     * @dev Get current accrued interest (estimated)
     * @param asset The address of the asset
     * @return Estimated interest accrued since last harvest
     */
    function getEstimatedInterest(
        address asset
    ) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address aToken = aTokens[asset];
        uint256 currentBalance = IERC20(aToken).balanceOf(address(this));

        if (currentBalance == 0) {
            return 0;
        }

        // Calculate estimated interest based on aToken balance vs initial deposit
        uint256 initialDeposit = initialDeposits[asset];
        if (currentBalance > initialDeposit) {
            return currentBalance - initialDeposit;
        }

        return 0;
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
}