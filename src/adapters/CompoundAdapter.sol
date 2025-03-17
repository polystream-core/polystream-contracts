// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@compound/CometMainInterface.sol";
import "./interfaces/IProtocolAdapter.sol";

/**
 * @title CompoundAdapter
 * @notice Adapter for interacting with Compound v3 (Comet)
 * @dev Implements the IProtocolAdapter interface
 */
contract CompoundAdapter is IProtocolAdapter, Ownable {
    // Reference to the Comet contract (Compound v3 instance)
    CometMainInterface public immutable comet;

    // Mapping of supported assets
    mapping(address => bool) public supportedAssets;
    
    // Tracking total principal per asset
    mapping(address => uint256) public totalPrincipal;

    // Minimum reward threshold per asset
    mapping(address => uint256) public minRewardAmount;

    // Protocol name
    string private constant PROTOCOL_NAME = "Compound V3";

    /**
     * @dev Constructor
     * @param _cometAddress The address of the Comet contract
     */
    constructor(address _cometAddress) Ownable(msg.sender) {
        comet = CometMainInterface(_cometAddress);
    }

    /**
     * @dev Add a supported asset
     * @param asset The address of the asset
     */
    function addSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = true;
    }

    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
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
     * @dev Supply assets to Compound
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were successfully supplied
     */
    function supply(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Approve Comet contract to spend asset
        IERC20(asset).approve(address(comet), amount);

        // Supply base token or collateral
        comet.supply(asset, amount);

        // Update total principal
        totalPrincipal[asset] += amount;

        return amount;
    }

    /**
     * @dev Withdraw assets from Compound
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(address asset, uint256 amount) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        // Withdraw from Comet
        comet.withdraw(asset, amount);
        
        // Transfer asset to caller
        IERC20(asset).transfer(msg.sender, amount);

        // Update total principal
        if (amount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= amount;
        } else {
            totalPrincipal[asset] = 0;
        }

        return amount;
    }

    /**
     * @dev Withdraw assets from Compound and send directly to a user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @param user The address of the user to receive the withdrawn assets
     * @return The amount of underlying tokens successfully withdrawn and sent to the user
     */
    function withdrawToUser(address asset, uint256 amount, address user) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        // Withdraw from Comet
        comet.withdraw(asset, amount);

        // Transfer asset to the user
        IERC20(asset).transfer(user, amount);

        // Update total principal
        if (amount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= amount;
        } else {
            totalPrincipal[asset] = 0;
        }

        return amount;
    }

    /**
     * @dev Get the total principal amount deposited in this protocol
     * @param asset The address of the asset
     * @return The total principal amount in underlying asset units
     */
    function getTotalPrincipal(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return totalPrincipal[asset];
    }

    /**
     * @dev Get the current APY for an asset (directly from Compound)
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        return comet.getSupplyRate(utilization);
    }

    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The current balance
     */
    function getBalance(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return comet.balanceOf(address(this));
    }

    /**
     * @dev Harvest accrued interest from Compound
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in underlying asset terms
     */
    function harvest(address asset) external view override returns (uint256 harvestedAmount) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        uint interestRate = comet.getSupplyRate(utilization);
        
        uint balance = comet.balanceOf(address(this));

        // Calculate estimated interest earned
        harvestedAmount = (balance * interestRate) / 1e18;

        return harvestedAmount;
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
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(address asset, uint256 amount) external override {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }

    /**
     * @dev Get the estimated interest for an asset (fetching from Compound)
     * @param asset The address of the asset
     * @return The estimated interest amount based on Compound's calculations
     */
    function getEstimatedInterest(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        uint interestRate = comet.getSupplyRate(utilization);
        
        uint balance = comet.balanceOf(address(this));

        // Calculate estimated interest: (balance * rate) / scaling factor
        return (balance * interestRate) / 1e18;
    }

    /**
     * @dev Get the name of the protocol
     * @return The protocol name
     */
    function getProtocolName() external pure override returns (string memory) {
        return PROTOCOL_NAME;
    }
}
