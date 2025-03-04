// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    // Define TokenAmount struct to match what the contract expects
    struct TokenAmount {
        address token;
        uint amount;
    }
}

// Interface for the SyncSwap pool
interface ISyncSwapPool is IERC20 {
    function getTokens() external view returns (address token0, address token1);
}

/**
 * @title SyncSwapAdapter
 * @notice Adapter for interacting with SyncSwap protocol using burnLiquidity
 * @dev Implements the IProtocolAdapter interface
 */
contract SyncSwapAdapter is IProtocolAdapter, Ownable {
    // SyncSwap Router contract
    ISyncSwapRouter public immutable router;

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

    /**
     * @dev Constructor
     * @param _routerAddress The address of the SyncSwap Router contract
     */
    constructor(address _routerAddress) Ownable(msg.sender) {
        router = ISyncSwapRouter(_routerAddress);
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
