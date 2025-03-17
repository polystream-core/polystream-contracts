// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";


import "./interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";
import "./interfaces/IVault.sol";

/**
 * @title CombinedVault
 * @notice A yield-generating vault with improved time-weighted balance tracking
 * @dev Implements simple accounting without ERC20 shares
 */
contract CombinedVault is IVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Owner address
    address public owner;
    address public authorizedCaller; 

    // Protocol registry
    IRegistry public immutable registry;
    
    // Underlying asset (e.g., USDC)
    IERC20 public immutable asset;
    
    // Protocol IDs
    uint256[] public activeProtocolIds;
    
    // EPOCH_DURATION is 1 day
    // EPOCH DURATION for testing is 5 minutes
    uint256 public constant EPOCH_DURATION = 300;
    uint256 public lastEpochTime;
    
    // Tracking total balances
    uint256 public totalUserBalance;
    uint256 public totalAdapterBalance;
    
    // Fee constants
    uint256 public constant BASE_WITHDRAWAL_FEE = 0;     // 0%
    uint256 public constant EARLY_WITHDRAWAL_FEE = 500 ;  // 5%
    
    // Precision for calculations
    uint256 public constant PRECISION = 1e12;

    struct UserDeposit {
        uint256 amount;
        uint256 timestamp;
        uint256 epoch;
        uint256 timeWeightedAmount; // This gets updated at harvest time
    }

    struct UserData {
        uint256 balance;            // Total user balance (including rewards)
        uint256 timeWeightedBalance; // Time-weighted balance used for reward calculation
        UserDeposit[] deposits;     // Array of individual deposits
        uint256 totalRewardsClaimed; // Total rewards claimed
    }
    
    // User data tracking
    mapping(address => UserData) public userData;
    address[] public activeUsers;
    
    // Epoch data
    mapping(uint256 => uint256) public epochHarvestedAmount;
    uint256 public currentEpochNumber;
    
    // Events
    event Deposited(address indexed user, uint256 assetAmount, uint256 depositTimestamp);
    event Withdrawn(address indexed user, uint256 amount);
    event Harvested(uint256 timestamp, uint256 harvestedAmount);
    event ProtocolAdded(uint256 indexed protocolId);
    event ProtocolRemoved(uint256 indexed protocolId);
    event RewardDistributed(address indexed user, uint256 rewardAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AuthorizedCallerUpdated(address indexed previousCaller, address indexed newCaller);
    
    // Custom onlyOwner modifier
    modifier onlyOwner() {
        require(msg.sender == owner, "CombinedVault: caller is not the owner");
        _;
    }
    
    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner || msg.sender == authorizedCaller, "Not authorized");
        _;
    }

    /**
     * @dev Constructor
     * @param _registry Address of the protocol registry
     * @param _asset Address of the underlying asset
     */
    constructor(
        address _registry,
        address _asset
    ) {
        require(_registry != address(0), "Invalid registry address");
        require(_asset != address(0), "Invalid asset address");
        
        owner = msg.sender;
        registry = IRegistry(_registry);
        asset = IERC20(_asset);
        lastEpochTime = block.timestamp;
        currentEpochNumber = block.timestamp / EPOCH_DURATION;
    }
    
    /**
     * @dev Allows the owner to set an authorized caller (e.g., YieldOptimizer or Chainlink automation).
     * @param newCaller The new authorized caller address.
     */
    function setAuthorizedCaller(address newCaller) external onlyOwner {
        require(newCaller != address(0), "Invalid address");
        emit AuthorizedCallerUpdated(authorizedCaller, newCaller);
        authorizedCaller = newCaller;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "CombinedVault: new owner is the zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @dev Add a protocol to the vault
     * @param protocolId ID of the protocol to add
     */
    function addProtocol(uint256 protocolId) external onlyOwner {
        // Check if the protocol is registered in the registry
        require(bytes(registry.getProtocolName(protocolId)).length > 0, "Protocol not registered");
        require(registry.hasAdapter(protocolId, address(asset)), "No adapter for this asset");
        
        // Check if the protocol is already active
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            require(activeProtocolIds[i] != protocolId, "Protocol already active");
        }
        
        // Add to active protocols
        activeProtocolIds.push(protocolId);
        
        emit ProtocolAdded(protocolId);
    }
    
    /**
     * @dev Remove a protocol from the vault
     * @param protocolId ID of the protocol to remove
     */
    function removeProtocol(uint256 protocolId) external onlyOwner {
        // Check if the protocol is active
        bool found = false;
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            if (activeProtocolIds[i] == protocolId) {
                found = true;
                
                // Remove by replacing with the last element and popping
                activeProtocolIds[i] = activeProtocolIds[activeProtocolIds.length - 1];
                activeProtocolIds.pop();
                break;
            }
        }
        
        require(found, "Protocol not active");
        
        // Withdraw all funds from this protocol
        _withdrawAllFromProtocol(protocolId);
        
        emit ProtocolRemoved(protocolId);
    }
    
    /**
     * @dev Deposit assets into the vault
     * @param user Address of the user to deposit for
     * @param amount Amount of assets to deposit
     */
    function deposit(address user, uint256 amount) external override nonReentrant {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Deposit must be > 0");
        require(activeProtocolIds.length > 0, "No active protocols");
        
        // Transfer assets from sender to this contract
        asset.transferFrom(msg.sender, address(this), amount);
        
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();
        
        // Calculate time-weighted amount based on time left in epoch
        uint256 elapsedTime = block.timestamp - lastEpochTime;
        uint256 timeRemainingFraction = EPOCH_DURATION - elapsedTime;
        uint256 timeWeightedAmount = (amount * timeRemainingFraction) / EPOCH_DURATION;
        
        // Add new deposit to user's deposits array
        userData[user].deposits.push(UserDeposit({
            amount: amount,
            timestamp: block.timestamp,
            epoch: currentEpoch,
            timeWeightedAmount: timeWeightedAmount
        }));
        
        // Update user's total balance
        userData[user].balance += amount;
        
        // Update time-weighted balance
        userData[user].timeWeightedBalance += timeWeightedAmount;
        
        // Update total balances
        totalUserBalance += amount;
        totalAdapterBalance += amount; // Will be updated when distributed to protocols
        
        // First-time depositor logic
        if (userData[user].deposits.length == 1) {
            activeUsers.push(user);
        }
        
        // Distribute funds to protocols
        _distributeAssets();
        
        emit Deposited(user, amount, block.timestamp);
    }
    
    /**
     * @dev Withdraw assets from the vault
     * @param user Address of the user to withdraw for
     * @param amount Amount to withdraw
     */
    function withdraw(address user, uint256 amount) external override nonReentrant {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Withdraw amount must be > 0");
        require(userData[user].balance >= amount, "Insufficient balance");
        
        // Calculate early withdrawal fee if applicable
        uint256 currentEpoch = getCurrentEpoch();
        uint256 feeAmount = 0;
        
        // Check for current epoch deposits to apply early withdrawal fee
        uint256 currentEpochDepositTotal = 0;
        for (uint i = 0; i < userData[user].deposits.length; i++) {
            if (userData[user].deposits[i].epoch == currentEpoch) {
                currentEpochDepositTotal += userData[user].deposits[i].amount;
            }
        }
        
        if (currentEpochDepositTotal > 0) {
            uint256 earlyWithdrawalAmount = amount <= currentEpochDepositTotal ? 
            amount : currentEpochDepositTotal;
            feeAmount = (earlyWithdrawalAmount * EARLY_WITHDRAWAL_FEE) / 10000;
        }
        
        // Calculate final withdrawal amount
        uint256 finalWithdrawAmount = amount - feeAmount;
        
        // Convert fee to reward if applicable
        if (feeAmount > 0) {
            _convertFeeToReward(feeAmount);
        }
        
        // Withdraw funds from protocols
        uint256 actualWithdrawnAmount = _withdrawFromProtocols(finalWithdrawAmount, user);
        
        // Update accounting
        userData[user].balance -= amount;
        
        // Update time-weighted balance proportionally
        if (userData[user].balance > 0) {
            userData[user].timeWeightedBalance = (userData[user].timeWeightedBalance * userData[user].balance) / (userData[user].balance + amount);
        } else {
            userData[user].timeWeightedBalance = 0;
            
            // If balance is zero, remove user from tracking
            _removeUser(user);
        }
        
        // Update total balances
        totalUserBalance -= amount;
        totalAdapterBalance -= finalWithdrawAmount;
        
        emit Withdrawn(user, actualWithdrawnAmount);
    }
    
    /**
     * @dev Check and harvest yield from all protocols
     */
    function checkAndHarvest() external override nonReentrant returns (uint256 harvestedAmount) {
        if (block.timestamp >= lastEpochTime + EPOCH_DURATION) {
            uint256 totalHarvested = _harvestAllProtocols();
            epochHarvestedAmount[currentEpochNumber] = totalHarvested;
            
            // Get total time-weighted balance across all users
            uint256 totalTimeWeightedBalance = 0;
            for (uint256 i = 0; i < activeUsers.length; i++) {
                address user = activeUsers[i];
                totalTimeWeightedBalance += userData[user].timeWeightedBalance;
            }
            
            // Distribute rewards to users based on time-weighted balance
            if (totalTimeWeightedBalance > 0 && totalHarvested > 0) {
                for (uint256 i = 0; i < activeUsers.length; i++) {
                    address user = activeUsers[i];
                    uint256 userShare = userData[user].timeWeightedBalance;
                    
                    if (userShare > 0) {
                        // Calculate user's reward
                        uint256 userReward = (totalHarvested * userShare) / totalTimeWeightedBalance;
                        
                        // Add reward to user's balance
                        userData[user].balance += userReward;
                        
                        // Update total user balance
                        totalUserBalance += userReward;
                        
                        
                        emit RewardDistributed(user, userReward);
                    }
                }
            }
            
            // Reset time-weighted balances for the new epoch
            _resetTimeWeightedBalances();
            
            // Update epoch tracking
            lastEpochTime = block.timestamp;
            currentEpochNumber = getCurrentEpoch();
            
            emit Harvested(block.timestamp, totalHarvested);
            return totalHarvested;
        }
        
        return 0;
    }

    function supplyToProtocol(uint256 protocolId, uint256 amount) external onlyOwnerOrAuthorized {
        require(amount > 0, "Amount must be greater than zero");
        
        IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
        require(address(adapter) != address(0), "Invalid protocol adapter");

        // Approve the protocol adapter to spend the vault's funds
        asset.approve(address(adapter), amount);

        // Supply funds to the new protocol
        uint256 supplied = adapter.supply(address(asset), amount);
        require(supplied > 0, "Supply failed");
    }

    /**
     * @dev Get the current epoch
     * @return Current epoch number
     */
    function getCurrentEpoch() public view override returns (uint256) {
        return (block.timestamp / EPOCH_DURATION);
    }
    
    /**
     * @dev Get all active users
     * @return Array of active user addresses
     */
    function getUsers() external view override returns (address[] memory) {
        return activeUsers;
    }
    
    /**
     * @dev Get user entry time (time of first deposit)
     * @param user Address of the user
     * @return Entry time of the user
     */
    function getUserEntryTime(address user) external view override returns (uint256) {
        if (userData[user].deposits.length > 0) {
            return userData[user].deposits[0].timestamp;
        }
        return 0;
    }
    
    /**
     * @dev Get total supply of user balances
     * @return Total supply
     */
    function getTotalSupply() public view override returns (uint256) {
        return totalUserBalance;
    }
    
    /**
     * @dev Get total time-weighted balances across all users
     * @return Total time-weighted balance
     */
    function getTotalTimeWeightedShares() external view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            total += userData[activeUsers[i]].timeWeightedBalance;
        }
        return total;
    }
    
    /**
     * @dev Get user time-weighted balance
     * @param user Address of the user
     * @return User's time-weighted balance
     */
    function getUserTimeWeightedShares(address user) external view override returns (uint256) {
        return userData[user].timeWeightedBalance;
    }
    
    /**
     * @dev Get user balance 
     * @param account Address of the account
     * @return Balance of the account
     */
    function balanceOf(address account) public view override returns (uint256) {
        return userData[account].balance;
    }
    
    /**
     * @dev Internal function to distribute assets to protocols
     */
    function _distributeAssets() internal {
        // Get the current active protocol from the registry
        uint256 activeProtocolId = registry.getActiveProtocolId();
        require(activeProtocolId != 0, "No active protocol");

        IProtocolAdapter adapter = registry.getAdapter(activeProtocolId, address(asset));
        require(address(adapter) != address(0), "Invalid adapter");

        uint256 balance = asset.balanceOf(address(this));
        if (balance == 0) return;

        console.log("Distributing assets to Active Protocol ID:", activeProtocolId);
        
        // Approve the protocol adapter to spend our funds
        asset.approve(address(adapter), balance);

        // Supply the entire balance to the active protocol
        uint256 supplied = adapter.supply(address(asset), balance);
        console.log("Supplied to Protocol ID:", activeProtocolId, "Amount:", supplied);
    }

        
    /**
     * @dev Internal function to withdraw from protocols
     * @param amount Amount to withdraw
     * @param user User to receive the withdrawn assets (if null, send to this contract)
     * @return Amount withdrawn
     */
    function _withdrawFromProtocols(uint256 amount, address user) internal returns (uint256) {
        if (activeProtocolIds.length == 0 || amount == 0) return 0;
        
        // Distribute withdrawal evenly across all active protocols
        uint256 amountPerProtocol = amount / activeProtocolIds.length;
        uint256 totalWithdrawn = 0;
        
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
            
            // Withdraw using appropriate method based on whether user is specified
            uint256 withdrawn;
            if (user != address(0)) {
                withdrawn = adapter.withdrawToUser(address(asset), amountPerProtocol, user);
            } else {
                withdrawn = adapter.withdraw(address(asset), amountPerProtocol);
            }
            
            totalWithdrawn += withdrawn;
        }
        
        return totalWithdrawn;
    }
    
    /**
     * @dev Internal function to withdraw all funds from a specific protocol
     * @param protocolId ID of the protocol
     */
    function _withdrawAllFromProtocol(uint256 protocolId) public onlyOwnerOrAuthorized {
        IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
        
        // Get current balance in the protocol
        uint256 balance = adapter.getBalance(address(asset));
        
        if (balance > 0) {
            // Withdraw all funds
            uint256 withdrawn = adapter.withdraw(address(asset), balance);
            console.log("Amount withdrawn:", withdrawn);
        }
    }

    /**
     * @dev Internal function to harvest yield from all protocols
     * @return totalHarvested The total amount harvested from all protocols
     */
    function _harvestAllProtocols() internal returns (uint256 totalHarvested) {
        // Reset adapter balance for recalculation
        totalAdapterBalance = 0;
        
        
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
            
            // Attempt to harvest
            uint256 harvested = adapter.harvest(address(asset));
            if (harvested > 0) {
                totalHarvested += harvested;
            }
            
            // Update adapter balance
            uint256 postHarvestBalance = adapter.getBalance(address(asset));
            totalAdapterBalance += postHarvestBalance;
        }
        
        return totalHarvested;
    }
    
    /**
     * @dev Internal function to reset time-weighted balances for the new epoch
     * Each user's time-weighted balance is set to their actual balance
     */
    function _resetTimeWeightedBalances() internal {
        
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            
            // Reset time-weighted amount for each deposit to its actual amount
            for (uint j = 0; j < userData[user].deposits.length; j++) {
                userData[user].deposits[j].timeWeightedAmount = userData[user].deposits[j].amount;
            }
            
            // Reset user's time-weighted balance to match their actual balance
            userData[user].timeWeightedBalance = userData[user].balance;
            
        }
    }
    
    /**
     * @dev Internal function to remove a user from tracking
     * @param user Address of the user to remove
     */
    function _removeUser(address user) internal {
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (activeUsers[i] == user) {
                activeUsers[i] = activeUsers[activeUsers.length - 1];
                activeUsers.pop();
                delete userData[user];
                break;
            }
        }
    }
    
    /**
     * @dev Internal function to convert fees to rewards
     * @param fee Fee amount to convert
     */
    function _convertFeeToReward(uint256 fee) internal {
        if (fee == 0 || activeProtocolIds.length == 0) return;
        
        // Convert fee to reward in each protocol
        uint256 feePerProtocol = fee / activeProtocolIds.length;
        
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            IProtocolAdapter adapter = registry.getAdapter(protocolId, address(asset));
            
            adapter.convertFeeToReward(address(asset), feePerProtocol);
        }
    }
}