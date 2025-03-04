// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../adapters/interfaces/IProtocolAdapter.sol";
import "./interfaces/IRegistry.sol";
import "./interfaces/IVault.sol";
import "../libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title YieldVault
 * @notice A yield-generating vault that forwards assets to multiple protocols
 * @dev Implements IVault and integrates with the protocol registry system
 */
contract YieldVault is IVault, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Protocol registry
    IRegistry public immutable registry;
    
    // Underlying asset (e.g., USDC)
    IERC20 public immutable asset;
    
    // Protocol allocation data
    struct ProtocolAllocation {
        bool active;
        uint256 allocationPercentage; // In basis points (e.g., 5000 = 50%)
    }
    
    // Mapping of protocol ID to allocation data
    mapping(uint256 => ProtocolAllocation) public protocolAllocations;
    
    // Active protocol IDs
    uint256[] public activeProtocolIds;
    
    // Total allocation percentage (should be 10000 = 100%)
    uint256 public totalAllocationPercentage;
    
    // Precision for share price calculations
    uint256 private constant PRECISION = 1e18;
    
    // Last rebalance timestamp
    uint256 public lastRebalanceTimestamp;
    
    // --- Events ---
    event Deposited(address indexed user, uint256 assetAmount, uint256 sharesAmount);
    event Withdrawn(address indexed user, uint256 assetAmount, uint256 sharesAmount);
    event ProtocolAdded(uint256 protocolId, uint256 allocationPercentage);
    event ProtocolRemoved(uint256 protocolId);
    event AllocationUpdated(uint256 protocolId, uint256 previousPercentage, uint256 newPercentage);
    event Rebalanced(uint256 timestamp);
    
    /**
     * @dev Constructor
     * @param _registry Address of the protocol registry
     * @param _asset Address of the underlying asset
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     */
    constructor(
        address _registry,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        registry = IRegistry(_registry);
        asset = IERC20(_asset);
    }
    
    /**
     * @dev Add a protocol to the vault's allocation
     * @param protocolId ID of the protocol to add
     * @param allocationPercentage Percentage to allocate to this protocol (in basis points)
     */
    function addProtocol(uint256 protocolId, uint256 allocationPercentage) external onlyOwner {
        require(!protocolAllocations[protocolId].active, "Protocol already active");
        require(allocationPercentage > 0, "Allocation must be greater than 0");
        require(totalAllocationPercentage + allocationPercentage <= 10000, "Total allocation exceeds 100%");
        require(registry.hasAdapter(protocolId, address(asset)), "No adapter registered for this protocol and asset");
        
        protocolAllocations[protocolId] = ProtocolAllocation({
            active: true,
            allocationPercentage: allocationPercentage
        });
        
        activeProtocolIds.push(protocolId);
        totalAllocationPercentage += allocationPercentage;
        
        emit ProtocolAdded(protocolId, allocationPercentage);
    }
    
    /**
     * @dev Remove a protocol from the vault's allocation
     * @param protocolId ID of the protocol to remove
     */
    function removeProtocol(uint256 protocolId) external onlyOwner {
        require(protocolAllocations[protocolId].active, "Protocol not active");
        
        // Withdraw all funds from this protocol first
        _withdrawFromProtocol(protocolId, type(uint256).max);
        
        // Update allocation tracking
        totalAllocationPercentage -= protocolAllocations[protocolId].allocationPercentage;
        delete protocolAllocations[protocolId];
        
        // Remove from active protocols array
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            if (activeProtocolIds[i] == protocolId) {
                // Replace with the last element and pop
                activeProtocolIds[i] = activeProtocolIds[activeProtocolIds.length - 1];
                activeProtocolIds.pop();
                break;
            }
        }
        
        emit ProtocolRemoved(protocolId);
    }
    
    /**
     * @dev Update the allocation percentage for a protocol
     * @param protocolId ID of the protocol to update
     * @param newAllocationPercentage New allocation percentage (in basis points)
     */
    function updateAllocation(uint256 protocolId, uint256 newAllocationPercentage) external onlyOwner {
        require(protocolAllocations[protocolId].active, "Protocol not active");
        require(newAllocationPercentage > 0, "Allocation must be greater than 0");
        
        uint256 oldAllocation = protocolAllocations[protocolId].allocationPercentage;
        uint256 newTotal = totalAllocationPercentage - oldAllocation + newAllocationPercentage;
        
        require(newTotal <= 10000, "Total allocation exceeds 100%");
        
        protocolAllocations[protocolId].allocationPercentage = newAllocationPercentage;
        totalAllocationPercentage = newTotal;
        
        emit AllocationUpdated(protocolId, oldAllocation, newAllocationPercentage);
    }
    
    /**
     * @dev Deposit assets into the vault
     * @param amount Amount of assets to deposit
     * @return shares Amount of shares minted
     */
    function deposit(uint256 amount) external override nonReentrant returns (uint256 shares) {
        require(amount > 0, "Amount must be greater than 0");
        require(activeProtocolIds.length > 0, "No active protocols");
        require(totalAllocationPercentage == 10000, "Incomplete allocation");
        
        // Calculate shares to mint based on the current share price
        shares = _calculateSharesToMint(amount);
        require(shares > 0, "Shares calculated is 0");
        
        // Transfer assets from user to vault
        asset.transferFrom(msg.sender, address(this), amount);
        
        // Mint shares to the user
        _mint(msg.sender, shares);
        
        // Distribute the newly deposited assets to protocols based on their allocations
        _distributeAssets();
        
        emit Deposited(msg.sender, amount, shares);
        return shares;
    }
    
    /**
     * @dev Withdraw assets from the vault
     * @param shares Amount of shares to burn
     * @return amount Amount of assets withdrawn
     */
    function withdraw(uint256 shares) external override nonReentrant returns (uint256 amount) {
        require(shares > 0, "Shares must be greater than 0");
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");
        
        // Calculate assets to withdraw based on the current share price
        amount = _calculateAssetsToWithdraw(shares);
        require(amount > 0, "Amount calculated is 0");
        
        // Burn shares first (to prevent reentrancy)
        _burn(msg.sender, shares);
        
        // Get balance in the vault
        uint256 vaultBalance = asset.balanceOf(address(this));
        
        // If we don't have enough in the vault, we need to withdraw from protocols
        if (vaultBalance < amount) {
            uint256 remainingToWithdraw = amount - vaultBalance;
            _withdrawFromProtocols(remainingToWithdraw);
            
            // Update the actual amount we can withdraw based on what we got
            vaultBalance = asset.balanceOf(address(this));
            if (vaultBalance < amount) {
                amount = vaultBalance;
            }
        }
        
        // Transfer assets to the user
        asset.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount, shares);
        return amount;
    }
    
    /**
     * @dev Rebalance assets across protocols based on the target allocations
     */
    function rebalance() external override onlyOwner {
        require(activeProtocolIds.length > 0, "No active protocols");
        require(totalAllocationPercentage == 10000, "Incomplete allocation");
        
        // Get total assets across all protocols and the vault
        uint256 totalAssetValue = _totalAssets();
        
        if (totalAssetValue == 0) {
            // Nothing to rebalance
            return;
        }
        
        // For each protocol, calculate target balance and adjust as needed
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            uint256 targetAmount = (totalAssetValue * protocolAllocations[protocolId].allocationPercentage) / 10000;
            
            IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
            uint256 currentAmount = adapter.getBalance(address(asset));
            
            if (currentAmount > targetAmount) {
                // Withdraw excess
                uint256 excessAmount = currentAmount - targetAmount;
                adapter.withdraw(address(asset), excessAmount);
            }
        }
        
        // Now distribute available assets in the vault
        _distributeAssets();
        
        lastRebalanceTimestamp = block.timestamp;
        emit Rebalanced(block.timestamp);
    }
    
    /**
     * @dev Get total assets managed by the vault (across all protocols and in the vault itself)
     * @return Total assets
     */
    function totalAssets() external view override returns (uint256) {
        return _totalAssets();
    }
    
    /**
     * @dev Get the price per share (assets per share)
     * @return Price per share with 18 decimals precision
     */
    function getPricePerShare() external view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return PRECISION; // Initial price: 1:1
        
        return (_totalAssets() * PRECISION) / supply;
    }
    
    /**
     * @dev Get the weighted average APY across all active protocols
     * @return Average APY in basis points
     */
    function getAverageAPY() public view returns (uint256) {
        if (activeProtocolIds.length == 0) return 0;
        
        uint256 weightedSum = 0;
        
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            ProtocolAllocation memory allocation = protocolAllocations[protocolId];
            
            if (allocation.active && allocation.allocationPercentage > 0) {
                IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
                uint256 apy = adapter.getAPY(address(asset));
                
                weightedSum += (apy * allocation.allocationPercentage) / 10000;
            }
        }
        
        return weightedSum;
    }
    
    /**
     * @dev Get the number of active protocols
     * @return Number of active protocols
     */
    function getActiveProtocolCount() external view returns (uint256) {
        return activeProtocolIds.length;
    }
    
    /**
     * @dev Rescue tokens accidentally sent to the vault
     * @param token Address of the token to rescue
     * @param to Address to send tokens to
     * @param amount Amount of tokens to rescue
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(asset), "Cannot rescue vault asset");
        
        IERC20(token).transfer(to, amount);
    }
    
    /**
     * @dev Internal function to calculate the total assets under management
     * @return Total assets
     */
    function _totalAssets() internal view returns (uint256) {
        // Start with balance in the vault
        uint256 total = asset.balanceOf(address(this));
        
        // Add balance in each protocol
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            if (protocolAllocations[protocolId].active) {
                IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
                total += adapter.getBalance(address(asset));
            }
        }
        
        return total;
    }
    
    /**
     * @dev Internal function to calculate shares to mint based on asset amount
     * @param amount Amount of assets
     * @return Amount of shares to mint
     */
    function _calculateSharesToMint(uint256 amount) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return amount; // Initial deposit: 1:1 ratio
        }
        
        uint256 totalAssetValue = _totalAssets();
        if (totalAssetValue == 0) {
            return amount; // No assets yet: 1:1 ratio
        }
        
        return (amount * supply) / totalAssetValue;
    }
    
    /**
     * @dev Internal function to calculate assets to withdraw based on share amount
     * @param shares Amount of shares
     * @return Amount of assets to withdraw
     */
    function _calculateAssetsToWithdraw(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        
        uint256 totalAssetValue = _totalAssets();
        return (shares * totalAssetValue) / supply;
    }
    
    /**
     * @dev Internal function to distribute assets to protocols based on allocations
     */
    function _distributeAssets() internal {
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance == 0) return;
        
        // Get total allocation percentage
        require(totalAllocationPercentage > 0, "No allocation defined");
        
        // Distribute assets based on allocation percentages
        uint256 remainingToDistribute = vaultBalance;
        
        for (uint i = 0; i < activeProtocolIds.length && remainingToDistribute > 0; i++) {
            uint256 protocolId = activeProtocolIds[i];
            ProtocolAllocation memory allocation = protocolAllocations[protocolId];
            
            if (allocation.active && allocation.allocationPercentage > 0) {
                // Calculate amount to allocate to this protocol
                uint256 amountToAllocate = (vaultBalance * allocation.allocationPercentage) / 10000;
                
                // Don't allocate more than we have left
                if (amountToAllocate > remainingToDistribute) {
                    amountToAllocate = remainingToDistribute;
                }
                
                if (amountToAllocate > 0) {
                    // Get the adapter and supply assets
                    IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
                    
                    // Approve the adapter to spend our assets
                    asset.approve(address(adapter), amountToAllocate);
                    
                    // Supply assets to the protocol
                    adapter.supply(address(asset), amountToAllocate);
                    
                    // Update remaining amount
                    remainingToDistribute -= amountToAllocate;
                }
            }
        }
    }
    
    /**
     * @dev Internal function to withdraw assets from protocols proportionally
     * @param amount Amount needed to withdraw
     */
    function _withdrawFromProtocols(uint256 amount) internal {
        if (amount == 0) return;
        
        // Keep track of total assets across all protocols
        uint256 totalInProtocols = 0;
        uint256[] memory protocolBalances = new uint256[](activeProtocolIds.length);
        
        // Get balances in each protocol
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
            uint256 balance = adapter.getBalance(address(asset));
            
            protocolBalances[i] = balance;
            totalInProtocols += balance;
        }
        
        if (totalInProtocols == 0) return;
        
        // Withdraw proportionally from each protocol
        uint256 remainingToWithdraw = amount;
        
        for (uint i = 0; i < activeProtocolIds.length && remainingToWithdraw > 0; i++) {
            uint256 protocolId = activeProtocolIds[i];
            uint256 balance = protocolBalances[i];
            
            if (balance > 0) {
                // Calculate amount to withdraw from this protocol
                uint256 amountToWithdraw = (amount * balance) / totalInProtocols;
                
                // Don't withdraw more than we need or more than available
                if (amountToWithdraw > remainingToWithdraw) {
                    amountToWithdraw = remainingToWithdraw;
                }
                if (amountToWithdraw > balance) {
                    amountToWithdraw = balance;
                }
                
                if (amountToWithdraw > 0) {
                    _withdrawFromProtocol(protocolId, amountToWithdraw);
                    remainingToWithdraw -= amountToWithdraw;
                }
            }
        }
    }
    
    /**
     * @dev Internal function to withdraw from a specific protocol
     * @param protocolId Protocol ID to withdraw from
     * @param amount Amount to withdraw (max uint if withdrawing all)
     */
    function _withdrawFromProtocol(uint256 protocolId, uint256 amount) internal {
        IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
        uint256 adapterBalance = adapter.getBalance(address(asset));
        
        if (adapterBalance == 0) return;
        
        // If amount is max uint, withdraw everything
        if (amount == type(uint256).max) {
            amount = adapterBalance;
        }
        
        // Cap at adapter balance
        if (amount > adapterBalance) {
            amount = adapterBalance;
        }
        
        if (amount > 0) {
            adapter.withdraw(address(asset), amount);
        }
    }
}