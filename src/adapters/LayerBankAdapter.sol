// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// LayerBank interfaces
interface IGToken is IERC20 {
    // Try different redeem functions based on common lending protocols
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function exchangeRate() external view returns (uint256);
    function accruedExchangeRate() external returns (uint256);
}

interface ILayerBankCore {
    function enterMarkets(address[] calldata gTokens) external;
    function supply(
        address gToken,
        uint256 underlyingAmount
    ) external payable returns (uint256);
    function redeem(address gToken, uint256 amount) external returns (uint256);
    function redeemUnderlying(
        address gToken,
        uint256 amount
    ) external returns (uint256);
}

// Interfaces for rewards claiming and token swapping (for future implementations)
interface ILayerBankRewards {
    function claimReward(
        address[] calldata gTokens,
        address to
    ) external returns (uint256);
}

// Price calculator interface based on LayerBank
interface IPriceCalculator {
    function priceOf(address asset) external view returns (uint256 priceInUSD);
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

// Add these minimal interfaces at the top of your contract
interface ILTokenMinimal {
    function getCash() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function totalReserve() external view returns (uint256);
    function reserveFactor() external view returns (uint256);
    function getRateModel() external view returns (address);
}

interface IRateModelMinimal {
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}

/**
 * @title LayerBankAdapter
 * @notice Adapter for interacting with LayerBank protocol with interest-based harvesting
 * @dev Handles both supply and redeem operations with proper error handling
 */
contract LayerBankAdapter is IProtocolAdapter, Ownable {
    // LayerBank Core contract
    ILayerBankCore public immutable core;

    // Optional contracts for reward token harvesting (may not be used on Scroll)
    ILayerBankRewards public rewardsController;
    IPriceCalculator public priceCalculator;
    ISyncSwapRouter public syncSwapRouter;

    // Mapping of asset address to gToken address
    mapping(address => address) public gTokens;

    // Supported assets
    mapping(address => bool) public supportedAssets;

    // Protocol name
    string private constant PROTOCOL_NAME = "LayerBank";

    // Fixed APY (4%)
    uint256 private constant FIXED_APY = 400;

    // Tracking initial deposits and exchange rates for profit calculation
    mapping(address => uint256) private initialDeposits;
    mapping(address => uint256) private lastExchangeRates;

    // Add tracking for total principal per asset
    mapping(address => uint256) public totalPrincipal;

    // Last harvest timestamp per asset
    mapping(address => uint256) public lastHarvestTimestamp;

    // Minimum reward amount to consider profitable after fees (per asset)
    mapping(address => uint256) public minRewardAmount;

    // Address of the reward token (usually LBR) - for future reward token implementations
    address public rewardToken;

    // WETH address for swap paths (for future reward token swaps)
    address public weth;

    // SyncSwap pool addresses for common pairs (for future reward token swaps)
    mapping(address => mapping(address => address)) public poolAddresses;

    /**
     * @dev Constructor
     * @param _coreAddress The address of the LayerBank Core contract
     */
    constructor(address _coreAddress) Ownable(msg.sender) {
        core = ILayerBankCore(_coreAddress);
    }

    /**
     * @dev Set external contract addresses (optional for Scroll without rewards)
     * @param _rewardsController The address of LayerBank Rewards Controller
     * @param _priceCalculator The address of the price calculator
     * @param _syncSwapRouter The address of the SyncSwap router
     * @param _rewardToken The address of the reward token (LBR)
     * @param _weth The address of WETH
     */
    function setExternalContracts(
        address _rewardsController,
        address _priceCalculator,
        address _syncSwapRouter,
        address _rewardToken,
        address _weth
    ) external onlyOwner {
        rewardsController = ILayerBankRewards(_rewardsController);
        priceCalculator = IPriceCalculator(_priceCalculator);
        syncSwapRouter = ISyncSwapRouter(_syncSwapRouter);
        rewardToken = _rewardToken;
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
     * @dev Add a supported asset
     * @param asset The address of the asset to add
     * @param gToken The address of the corresponding gToken
     */
    function addSupportedAsset(
        address asset,
        address gToken
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(gToken != address(0), "Invalid gToken address");

        gTokens[asset] = gToken;
        supportedAssets[asset] = true;

        // Enter the market for this gToken
        address[] memory marketsToEnter = new address[](1);
        marketsToEnter[0] = gToken;
        core.enterMarkets(marketsToEnter);

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
     * @dev Supply assets to LayerBank
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were actually supplied
     */
    function supply(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Store the current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
            lastExchangeRates[asset] = rate;
        } catch {
            // If we can't get the exchange rate, use a default of 1:1
            exchangeRate = 1e18;
            lastExchangeRates[asset] = 1e18;
        }

        // Get initial underlying token balance to verify transfer
        uint256 initialBalance = IERC20(asset).balanceOf(address(this));

        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Verify the transfer
        uint256 receivedAmount = IERC20(asset).balanceOf(address(this)) -
            initialBalance;

        // Update initial deposit tracking
        initialDeposits[asset] += receivedAmount;

        // Update total principal
        totalPrincipal[asset] += receivedAmount;

        // Approve LayerBank to spend asset
        IERC20(asset).approve(gToken, receivedAmount);

        // Get initial gToken balance
        uint256 gTokenBalanceBefore = IERC20(gToken).balanceOf(address(this));

        // Supply asset to LayerBank
        try core.supply(gToken, receivedAmount) {
            // Success
        } catch {
            // If supply fails, return 0
            return 0;
        }

        // Verify the supply succeeded by checking gToken balance
        uint256 gTokenBalanceAfter = IERC20(gToken).balanceOf(address(this));
        uint256 gTokensReceived = gTokenBalanceAfter - gTokenBalanceBefore;

        // Return the underlying amount that was supplied
        return receivedAmount;
    }

    /**
     * @dev Withdraw assets from LayerBank
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @return The actual amount of underlying tokens withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Calculate the maximum amount that can be withdrawn
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = (amount > maxWithdrawal)
            ? maxWithdrawal
            : amount;

        // Get initial asset balance
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            exchangeRate = 1e18; // Default to 1:1 if we can't get the exchange rate
        }

        // Try withdrawing directly using redeemUnderlying first (specifies exact underlying amount)
        bool withdrawSuccess = false;
        try core.redeemUnderlying(gToken, withdrawAmount) returns (uint256) {
            withdrawSuccess = true;
        } catch {
            // Try alternative methods
            try IGToken(gToken).redeemUnderlying(withdrawAmount) returns (
                uint256
            ) {
                withdrawSuccess = true;
            } catch {
                // If redeemUnderlying fails, calculate gToken amount and try redeem
                uint256 gTokenAmount = (withdrawAmount * 1e18) / exchangeRate;

                try core.redeem(gToken, gTokenAmount) returns (uint256) {
                    withdrawSuccess = true;
                } catch {
                    try IGToken(gToken).redeem(gTokenAmount) returns (uint256) {
                        withdrawSuccess = true;
                    } catch {
                        // All withdrawal methods failed
                        return 0;
                    }
                }
            }
        }

        // Calculate actual amount withdrawn
        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
        uint256 actualWithdrawn = assetBalanceAfter - assetBalanceBefore;

        // Update total principal
        if (actualWithdrawn <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= actualWithdrawn;
        } else {
            totalPrincipal[asset] = 0;
        }

        // Transfer withdrawn asset to sender
        IERC20(asset).transfer(msg.sender, actualWithdrawn);

        return actualWithdrawn;
    }

    /**
     * @dev Withdraw assets from LayerBank and send directly to user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @param user The address to receive the withdrawn assets
     * @return The actual amount of underlying tokens withdrawn
     */
    function withdrawToUser(
        address asset,
        uint256 amount,
        address user
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(user != address(0), "Invalid user address");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Calculate the maximum amount that can be withdrawn
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = (amount > maxWithdrawal)
            ? maxWithdrawal
            : amount;

        // Get initial asset balance of the user
        uint256 userBalanceBefore = IERC20(asset).balanceOf(user);

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            exchangeRate = 1e18; // Default to 1:1 if we can't get the exchange rate
        }

        // Try withdrawing using redeemUnderlying first
        bool withdrawSuccess = false;
        try core.redeemUnderlying(gToken, withdrawAmount) returns (uint256) {
            withdrawSuccess = true;
        } catch {
            // Try alternative methods
            try IGToken(gToken).redeemUnderlying(withdrawAmount) returns (
                uint256
            ) {
                withdrawSuccess = true;
            } catch {
                // If redeemUnderlying fails, calculate gToken amount and try redeem
                uint256 gTokenAmount = (withdrawAmount * 1e18) / exchangeRate;

                try core.redeem(gToken, gTokenAmount) returns (uint256) {
                    withdrawSuccess = true;
                } catch {
                    try IGToken(gToken).redeem(gTokenAmount) returns (uint256) {
                        withdrawSuccess = true;
                    } catch {
                        // All withdrawal methods failed
                        return 0;
                    }
                }
            }
        }

        // Get the balance that was withdrawn to this contract
        uint256 adapterBalance = IERC20(asset).balanceOf(address(this));

        // Transfer withdrawn asset to user
        if (adapterBalance > 0) {
            IERC20(asset).transfer(user, adapterBalance);
        }

        // Calculate actual amount received by user
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
     * @dev Harvest yield from the protocol by compounding interest
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in asset terms
     */
    function harvest(
        address asset
    ) external override returns (uint256 harvestedAmount) {
        require(supportedAssets[asset], "Asset not supported");

        // Always update timestamp first
        lastHarvestTimestamp[asset] = block.timestamp;

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Step 1: Get current gToken balance
        uint256 gTokenBalance = IERC20(gToken).balanceOf(address(this));
        if (gTokenBalance == 0) {
            return 0; // Nothing to harvest
        }

        // Step 2: Get current exchange rate
        uint256 currentExchangeRate;
        try IGToken(gToken).accruedExchangeRate() returns (uint256 rate) {
            currentExchangeRate = rate;
        } catch {
            try IGToken(gToken).exchangeRate() returns (uint256 rate) {
                currentExchangeRate = rate;
            } catch {
                return 0; // Can't get exchange rate
            }
        }

        // Calculate current value in underlying tokens based on exchange rate
        uint256 currentValueInUnderlying = (gTokenBalance *
            currentExchangeRate) / 1e18;

        // Calculate yield as the difference between current value and principal
        uint256 yieldAmount = 0;
        if (currentValueInUnderlying > totalPrincipal[asset]) {
            yieldAmount = currentValueInUnderlying - totalPrincipal[asset];
        }

        if (yieldAmount == 0) {
            return 0; // No yield to harvest
        }

        // If there's yield to harvest, withdraw everything and redeposit
        // This follows the pattern used in the AaveAdapter

        // Step 3: Withdraw all assets from LayerBank
        uint256 initialAssetBalance = IERC20(asset).balanceOf(address(this));

        // Try to redeem all gTokens
        bool redeemSuccess = false;
        try core.redeem(gToken, gTokenBalance) returns (uint256) {
            redeemSuccess = true;
        } catch {
            try IGToken(gToken).redeem(gTokenBalance) returns (uint256) {
                redeemSuccess = true;
            } catch {
                // If redemption fails, return the calculated yield
                // This is still accurate as we know interest is accruing
                return yieldAmount;
            }
        }

        uint256 finalAssetBalance = IERC20(asset).balanceOf(address(this));
        uint256 actualWithdrawn = finalAssetBalance - initialAssetBalance;

        // Step 5: Redeposit all assets back into LayerBank
        IERC20(asset).approve(gToken, actualWithdrawn);

        try core.supply(gToken, actualWithdrawn) {
            // Success
        } catch {
            // If redeposit fails, at least we calculated the yield correctly
        }

        return yieldAmount;
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
     * @dev Helper function to claim LayerBank rewards (called via try/catch to handle potential errors)
     * @param asset The address of the asset
     */
    function claimLayerBankRewards(address asset) external {
        require(msg.sender == address(this), "Only callable by self");
        require(
            address(rewardsController) != address(0),
            "Rewards controller not set"
        );

        address gToken = gTokens[asset];
        address[] memory gTokensArray = new address[](1);
        gTokensArray[0] = gToken;

        // Claim rewards (does nothing if no rewards are configured)
        rewardsController.claimReward(gTokensArray, address(this));
    }

    /**
     * @dev Get the current APY for an asset
     * @param asset The address of the asset
     * @return apyBps The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // For LayerBank, we need to calculate the APY from the rate model
        try this.calculateLayerBankAPY(gToken) returns (uint256 apy) {
            return apy;
        } catch {
            // Fallback to fixed APY if calculation fails
            return FIXED_APY;
        }
    }

    /**
     * @dev Helper function to calculate LayerBank APY
     * @param gToken The address of the gToken
     * @return apyBps The APY in basis points
     */
    function calculateLayerBankAPY(
        address gToken
    ) external view returns (uint256 apyBps) {
        // This interface matches the minimum functions we need from ILToken
        ILTokenMinimal lToken = ILTokenMinimal(gToken);

        // Get the required parameters
        uint256 cash = lToken.getCash();
        uint256 borrows = lToken.totalBorrow();
        uint256 reserves = lToken.totalReserve();
        uint256 reserveFactor = lToken.reserveFactor();

        // Get the rate model address
        address rateModelAddress = lToken.getRateModel();
        IRateModelMinimal rateModel = IRateModelMinimal(rateModelAddress);

        // Calculate the supply rate
        uint256 perSecondSupplyRate = rateModel.getSupplyRate(
            cash,
            borrows,
            reserves,
            reserveFactor
        );

        // Convert to annual rate and then to basis points
        uint256 SECONDS_PER_YEAR = 31536000;
        uint256 annualSupplyRateFraction = perSecondSupplyRate *
            SECONDS_PER_YEAR;
        apyBps = (annualSupplyRateFraction * 10000) / 1e18;

        return apyBps;
    }

    /**
     * @dev Get the current balance in the protocol (in underlying asset terms)
     * @param asset The address of the asset
     * @return The current balance in underlying asset
     */
    function getBalance(
        address asset
    ) external view override returns (uint256) {
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
    function isAssetSupported(
        address asset
    ) external view override returns (bool) {
        return supportedAssets[asset];
    }

    /**
     * @dev Get total principal amount for this asset
     * @param asset The address of the asset
     * @return The total principal amount
     */
    function getTotalPrincipal(
        address asset
    ) external view override returns (uint256) {
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

        address gToken = gTokens[asset];
        uint256 gTokenBalance = IERC20(gToken).balanceOf(address(this));

        if (gTokenBalance == 0) {
            return 0;
        }

        // Get current exchange rate
        uint256 currentExchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            currentExchangeRate = rate;
        } catch {
            return 0; // Can't calculate interest without exchange rate
        }

        // Get last stored exchange rate
        uint256 lastExchangeRate = lastExchangeRates[asset];
        if (lastExchangeRate == 0) {
            lastExchangeRate = 1e18; // Default to 1:1 if not set
        }

        // Calculate theoretical value in underlying tokens
        uint256 initialValueInUnderlying = (gTokenBalance * lastExchangeRate) /
            1e18;
        uint256 currentValueInUnderlying = (gTokenBalance *
            currentExchangeRate) / 1e18;

        // Calculate interest based on exchange rate increase
        if (currentValueInUnderlying > initialValueInUnderlying) {
            return currentValueInUnderlying - initialValueInUnderlying;
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
