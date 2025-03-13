// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/vault/CombinedVault.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/rewards/RewardManager.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CombinedVaultTest is Test {
    // Contract addresses on Scroll
    address constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_ATOKEN_ADDRESS = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    
    // Test users
    address public admin;
    address public user1;
    address public user2;
    
    // Core contracts
    ProtocolRegistry public registry;
    AaveAdapter public aaveAdapter;
    CombinedVault public vault;
    RewardManager public rewardManager;
    
    // Token
    IERC20 public usdc;
    
    function setUp() public {
        // Create test accounts
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Give test users some USDC
        deal(USDC_ADDRESS, user1, 1000 * 1e6);
        deal(USDC_ADDRESS, user2, 1000 * 1e6);
        
        // Set up as admin for all deployments and admin operations
        vm.startPrank(admin);
        
        // Deploy registry
        registry = new ProtocolRegistry();
        
        // Deploy Aave adapter
        aaveAdapter = new AaveAdapter(AAVE_POOL_ADDRESS);
        
        // Register protocol in registry
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Aave V3");
        
        // Add USDC as supported asset in Aave adapter
        aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS);
        
        // Register adapter in registry
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS, address(aaveAdapter));
        
        // Deploy vault
        vault = new CombinedVault(
            address(registry),
            USDC_ADDRESS,
            "Yield Vault USDC",
            "yvUSDC"
        );
        
        // Add Aave protocol to vault
        vault.addProtocol(Constants.AAVE_PROTOCOL_ID);
        
        // Deploy reward manager
        rewardManager = new RewardManager(USDC_ADDRESS, address(vault));
        
        // Set reward manager in vault
        vault.setRewardManager(address(rewardManager));
        
        vm.stopPrank();
        
        // Initialize token instance
        usdc = IERC20(USDC_ADDRESS);
    }
    
    function testDepositAndTimeWeightedShares() public {
        // User 1 deposits first
        uint256 depositAmount1 = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1);
        vault.deposit(user1, depositAmount1);
        vm.stopPrank();
        
        console.log("User 1 deposited:", depositAmount1);
        
        // Check initial time-weighted shares (first depositor gets full weight)
        uint256 user1Shares = vault.userShares(user1);
        uint256 user1TimeWeighted = vault.getUserTimeWeightedShares(user1);
        
        console.log("User 1 shares:", user1Shares);
        console.log("User 1 time-weighted shares:", user1TimeWeighted);
        
        assertEq(user1TimeWeighted, user1Shares, "First depositor should get full weight");
        
        // Advance time partially through the epoch
        vm.warp(block.timestamp + vault.EPOCH_DURATION() / 2);
        
        // User 2 deposits in the middle of the epoch
        uint256 depositAmount2 = 200 * 1e6; // 200 USDC
        
        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount2);
        vault.deposit(user2, depositAmount2);
        vm.stopPrank();
        
        console.log("User 2 deposited:", depositAmount2);
        
        // Check time-weighted shares (second depositor gets partial weight)
        uint256 user2Shares = vault.userShares(user2);
        uint256 user2TimeWeighted = vault.getUserTimeWeightedShares(user2);
        
        console.log("User 2 shares:", user2Shares);
        console.log("User 2 time-weighted shares:", user2TimeWeighted);
        
        // Mid-epoch depositor should have time-weighted shares less than actual shares
        assertLt(user2TimeWeighted, user2Shares, "Mid-epoch depositor should have partial weight");
        
        // Complete the epoch and check and harvest
        vm.warp(block.timestamp + vault.EPOCH_DURATION() / 2);
        
        vm.prank(admin);
        vault.checkAndHarvest();
        
        // After epoch transition, time-weighted shares should be normalized to actual shares
        uint256 user1TimeWeightedAfter = vault.getUserTimeWeightedShares(user1);
        uint256 user2TimeWeightedAfter = vault.getUserTimeWeightedShares(user2);
        
        console.log("User 1 time-weighted shares after epoch:", user1TimeWeightedAfter);
        console.log("User 2 time-weighted shares after epoch:", user2TimeWeightedAfter);
        
        assertEq(user1TimeWeightedAfter, user1Shares, "Time-weighted shares should normalize after epoch");
        assertEq(user2TimeWeightedAfter, user2Shares, "Time-weighted shares should normalize after epoch");
    }
    
    function testEarlyWithdrawalFee() public {
        // User 1 deposits
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(user1, depositAmount);
        
        // Try to withdraw in the same epoch (should incur early withdrawal fee)
        uint256 withdrawAmount = 50 * 1e6; // 50 USDC
        uint256 expectedFee = (withdrawAmount * vault.EARLY_WITHDRAWAL_FEE()) / 10000; // 5%
        uint256 expectedWithdrawal = withdrawAmount - expectedFee;
        
        // Get initial balance before withdrawal
        uint256 initialBalance = usdc.balanceOf(user1);
        console.log("Initial USDC balance before withdrawal:", initialBalance);
        
        // Withdraw
        vault.withdraw(user1, withdrawAmount);
        vm.stopPrank();
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(user1);
        console.log("Final USDC balance after withdrawal:", finalBalance);
        console.log("Actual received:", finalBalance - initialBalance);
        console.log("Expected to receive:", expectedWithdrawal);
        
        // Should be close to expected (allow for small rounding differences)
        assertApproxEqRel(finalBalance - initialBalance, expectedWithdrawal, 0.01e18, "Early withdrawal amount incorrect");
    }
    
    function testLateWithdrawalNoFee() public {
        // User 1 deposits
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(user1, depositAmount);
        vm.stopPrank();
        
        // Fast forward past the epoch
        vm.warp(block.timestamp + vault.EPOCH_DURATION() + 1);
        
        // Execute checkAndHarvest to transition epoch
        vm.prank(admin);
        vault.checkAndHarvest();
        
        // Now withdraw in the new epoch (should have no early withdrawal fee)
        uint256 withdrawAmount = 50 * 1e6; // 50 USDC
        
        // Get initial balance before withdrawal
        uint256 initialBalance = usdc.balanceOf(user1);
        console.log("Initial USDC balance before withdrawal:", initialBalance);
        
        vm.prank(user1);
        vault.withdraw(user1, withdrawAmount);
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(user1);
        console.log("Final USDC balance after withdrawal:", finalBalance);
        console.log("Actual received:", finalBalance - initialBalance);
        
        // Should be close to the withdraw amount (no fee)
        assertApproxEqRel(finalBalance - initialBalance, withdrawAmount, 0.01e18, "Late withdrawal should have no fee");
    }
    
    function testHarvestAndRewards() public {
        // User 1 and User 2 deposit with different amounts
        uint256 depositAmount1 = 100 * 1e6; // 100 USDC
        uint256 depositAmount2 = 300 * 1e6; // 300 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1);
        vault.deposit(user1, depositAmount1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount2);
        vault.deposit(user2, depositAmount2);
        vm.stopPrank();
        
        console.log("User 1 deposited:", depositAmount1);
        console.log("User 2 deposited:", depositAmount2);
        
        // Fast forward time to simulate interest accrual (30 days)
        vm.warp(block.timestamp + 30 days);
        console.log("Fast-forwarded 30 days to accrue interest");
        
        // Trigger harvest to capture yield
        vm.prank(admin);
        vault.checkAndHarvest();
        
        // Check reward debt for both users
        uint256 user1RewardDebt = rewardManager.getUserRewardDebt(user1);
        uint256 user2RewardDebt = rewardManager.getUserRewardDebt(user2);
        
        console.log("User 1 reward debt:", user1RewardDebt);
        console.log("User 2 reward debt:", user2RewardDebt);
        
        // User 2 should have higher reward debt due to larger deposit
        assertGt(user2RewardDebt, user1RewardDebt, "User with larger deposit should have more rewards");
        
        // Reward proportions should roughly match deposit proportions
        uint256 depositRatio = (depositAmount2 * 100) / depositAmount1; // User2 / User1 deposit ratio in percentage
        uint256 rewardRatio = (user2RewardDebt * 100) / user1RewardDebt; // User2 / User1 reward ratio in percentage
        
        console.log("Deposit ratio (User2/User1):", depositRatio, "%");
        console.log("Reward ratio (User2/User1):", rewardRatio, "%");
        
        // Ratios should be roughly the same (allow for some deviation due to time-weighting)
        assertApproxEqRel(depositRatio, rewardRatio, 0.1e18, "Reward ratio should be close to deposit ratio");
    }
    
    function testMultipleEpochsRewards() public {
        // User 1 deposits in first epoch
        uint256 depositAmount1 = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1);
        vault.deposit(user1, depositAmount1);
        vm.stopPrank();
        console.log("User 1 deposited in epoch 1:", depositAmount1);
        
        // Fast forward to end of epoch 1 and harvest
        vm.warp(block.timestamp + vault.EPOCH_DURATION());
        
        vm.prank(admin);
        vault.checkAndHarvest();
        console.log("Harvested at end of epoch 1");
        
        // User 2 deposits in second epoch (same amount as User 1)
        uint256 depositAmount2 = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount2);
        vault.deposit(user2, depositAmount2);
        vm.stopPrank();
        console.log("User 2 deposited in epoch 2:", depositAmount2);
        
        // Fast forward through epoch 2 to simulate interest accrual
        vm.warp(block.timestamp + vault.EPOCH_DURATION());
        
        // Harvest again at end of epoch 2
        vm.prank(admin);
        vault.checkAndHarvest();
        console.log("Harvested at end of epoch 2");
        
        // Fast forward through epoch 3 to simulate more interest accrual
        vm.warp(block.timestamp + vault.EPOCH_DURATION());
        
        // Harvest again at end of epoch 3
        vm.prank(admin);
        vault.checkAndHarvest();
        console.log("Harvested at end of epoch 3");
        
        // Check reward debt after multiple epochs
        uint256 user1RewardDebt = rewardManager.getUserRewardDebt(user1);
        uint256 user2RewardDebt = rewardManager.getUserRewardDebt(user2);
        
        console.log("User 1 reward debt after 3 epochs:", user1RewardDebt);
        console.log("User 2 reward debt after 2 epochs:", user2RewardDebt);
        
        // User 1 should have more rewards (participated in all three epochs)
        assertGt(user1RewardDebt, user2RewardDebt, "User who deposited earlier should have more rewards");
        
        // Fast forward more time for claim test
        vm.warp(block.timestamp + 10 days);
        
        // Test reward claiming
        vm.prank(user1);
        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        vm.prank(admin); // Simulate vault calling _claimReward
        vault.withdraw(user1, 10 * 1e6); // Withdraw small amount to trigger reward claim
        uint256 user1BalanceAfter = usdc.balanceOf(user1);
        
        console.log("User 1 received from withdrawal + rewards:", user1BalanceAfter - user1BalanceBefore);
        assertGt(user1BalanceAfter, user1BalanceBefore, "User should receive rewards when withdrawing");
    }
    
    function testWithdrawalProportionalTimeWeightedReduction() public {
        // User deposits
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(user1, depositAmount);
        
        // Check initial time-weighted shares
        uint256 initialTimeWeighted = vault.getUserTimeWeightedShares(user1);
        console.log("Initial time-weighted shares:", initialTimeWeighted);
        
        // Withdraw half
        uint256 withdrawAmount = 50 * 1e6; // 50 USDC
        vault.withdraw(user1, withdrawAmount);
        vm.stopPrank();
        
        // Check final time-weighted shares (should be halved)
        uint256 finalTimeWeighted = vault.getUserTimeWeightedShares(user1);
        console.log("Final time-weighted shares after 50% withdrawal:", finalTimeWeighted);
        
        // Should be approximately half the initial value
        assertApproxEqRel(finalTimeWeighted, initialTimeWeighted / 2, 0.01e18, "Time-weighted shares should be reduced proportionally on withdrawal");
    }
}