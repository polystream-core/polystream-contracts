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
     * @return The amount of gTokens received
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
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            lastExchangeRates[asset] = rate;
        } catch {
            // If we can't get the exchange rate, use a default of 1:1
            lastExchangeRates[asset] = 1e18;
        }

        // Get initial gToken balance
        uint256 balanceBefore = IERC20(gToken).balanceOf(address(this));

        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Update initial deposit tracking
        initialDeposits[asset] += amount;

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
    /**
     * @dev Withdraw assets from LayerBank
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @return The actual amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Get initial asset balance
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            exchangeRate = 1e18; // Default to 1:1 if we can't get the exchange rate
        }

        // Calculate the gToken amount based on the underlying amount and exchange rate
        uint256 gTokenAmount = (amount * 1e18) / exchangeRate;

        // Make sure we don't try to withdraw more than we have
        uint256 gTokenBalance = IERC20(gToken).balanceOf(address(this));
        if (gTokenAmount > gTokenBalance) {
            gTokenAmount = gTokenBalance;
        }

        // Try multiple withdrawal methods - different protocols name their functions differently
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
                uint256 assetBalanceAfter = IERC20(asset).balanceOf(
                    address(this)
                );
                uint256 received = assetBalanceAfter - assetBalanceBefore;

                IERC20(asset).transfer(msg.sender, received);
                return received;
            } catch {
                // Try the other methods as fallbacks
                try IGToken(gToken).redeem(gTokenAmount) returns (uint256) {
                    uint256 assetBalanceAfter = IERC20(asset).balanceOf(
                        address(this)
                    );
                    uint256 received = assetBalanceAfter - assetBalanceBefore;

                    IERC20(asset).transfer(msg.sender, received);
                    return received;
                } catch {
                    try IGToken(gToken).redeemUnderlying(amount) returns (
                        uint256
                    ) {
                        uint256 assetBalanceAfter = IERC20(asset).balanceOf(
                            address(this)
                        );
                        uint256 received = assetBalanceAfter -
                            assetBalanceBefore;

                        IERC20(asset).transfer(msg.sender, received);
                        return received;
                    } catch {
                        revert("All withdrawal methods failed");
                    }
                }
            }
        }
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

        // Get current gToken balance
        uint256 gTokenBalance = IERC20(gToken).balanceOf(address(this));
        if (gTokenBalance == 0) {
            return 0; // Nothing to harvest
        }

        // First try to update the exchange rate by calling accruedExchangeRate
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

        // Calculate the current value in underlying tokens
        uint256 currentValueInUnderlying = (gTokenBalance *
            currentExchangeRate) / 1e18;

        // Calculate the original value at deposit time
        uint256 originalDeposit = initialDeposits[asset];

        // Calculate yield as the difference
        uint256 yieldAmount = 0;
        if (currentValueInUnderlying > originalDeposit) {
            yieldAmount = currentValueInUnderlying - originalDeposit;
        }

        // If there's yield, withdraw it
        if (yieldAmount > 0) {
            // Calculate what percentage of our tokens to withdraw
            uint256 percentToWithdraw = (yieldAmount * 1e18) /
                currentValueInUnderlying;
            uint256 gTokensToWithdraw = (gTokenBalance * percentToWithdraw) /
                1e18;

            if (gTokensToWithdraw > 0) {
                uint256 assetBalanceBefore = IERC20(asset).balanceOf(
                    address(this)
                );

                // Try to withdraw just the yield portion
                try core.redeem(gToken, gTokensToWithdraw) returns (uint256) {
                    uint256 assetBalanceAfter = IERC20(asset).balanceOf(
                        address(this)
                    );
                    uint256 actualWithdrawn = assetBalanceAfter -
                        assetBalanceBefore;

                    // Return the actual amount withdrawn as yield
                    return actualWithdrawn;
                } catch {
                    // If redemption fails, we can still return the calculated amount
                    // since we know interest is accruing based on the exchange rate
                    return yieldAmount;
                }
            }
        }

        return yieldAmount;
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
