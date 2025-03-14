// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/vault/CombinedVault.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/adapters/AaveAdapter.sol";
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
        console.log("User 1 USDC balance:", IERC20(USDC_ADDRESS).balanceOf(user1));
        console.log("User 2 USDC balance:", IERC20(USDC_ADDRESS).balanceOf(user2));

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
            USDC_ADDRESS
        );
        
        // Add Aave protocol to vault
        vault.addProtocol(Constants.AAVE_PROTOCOL_ID);
        
        vm.stopPrank();
        
        // Initialize token instance
        usdc = IERC20(USDC_ADDRESS);
    }
    
    function testSingleUserDepositWithdraw() public {
        // User 1 deposits
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(user1, depositAmount);
        
        // Verify deposit was successful
        assertEq(vault.balanceOf(user1), depositAmount, "User balance should match deposit amount");
        assertEq(vault.getUserTimeWeightedShares(user1), depositAmount, "Time-weighted shares should match deposit for first deposit");
        
        // Withdraw full amount
        uint256 initialBalance = usdc.balanceOf(user1);
        vault.withdraw(user1, depositAmount);
        vm.stopPrank();
        
        // Verify withdrawal
        uint256 finalBalance = usdc.balanceOf(user1);
        assertEq(vault.balanceOf(user1), 0, "User balance should be zero after full withdrawal");
        
        console.log("Single user deposit and withdraw test passed");
    }
    
    function testSingleUserLateWithdraw() public {
        // User 1 deposits
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(user1, depositAmount);
        vm.stopPrank();
        
        // Fast forward past the epoch
        console.log("Fast-forwarding past the epoch...");
        vm.warp(block.timestamp + vault.EPOCH_DURATION());
        
        // Execute checkAndHarvest to transition epoch
        vm.prank(admin);
        uint256 harvestedYield = vault.checkAndHarvest();
        console.log("Harvested yield:", harvestedYield);
        
        // Calculate expected total with yield
        uint256 expectedTotal = depositAmount + harvestedYield;
        
        // Now withdraw in the new epoch (should have no early withdrawal fee)
        uint256 withdrawAmount = expectedTotal;
        
        // Get initial balance before withdrawal
        uint256 initialBalance = usdc.balanceOf(user1);
        
        vm.prank(user1);
        vault.withdraw(user1, withdrawAmount);
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(user1);
        console.log("Initial balance:", initialBalance);
        console.log("Final balance:", finalBalance);
        console.log("Difference:", finalBalance - initialBalance);
        
        // Should be close to the withdraw amount (no fee) plus any accrued yield
        assertApproxEqRel(finalBalance - initialBalance, withdrawAmount, 0.01e18, "User should receive deposit plus yield");
        
        console.log("Single user late withdraw test passed");
    }
    
    function testTwoUsersSameEpoch() public {
        // User 1 and User 2 deposit in the same epoch
        uint256 depositAmount1 = 200 * 1e6; // 200 USDC
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
        
        // Verify both users have correct balances
        assertEq(vault.balanceOf(user1), depositAmount1, "User 1 balance incorrect");
        assertEq(vault.balanceOf(user2), depositAmount2, "User 2 balance incorrect");
        
        // Both deposits were made in the same epoch at the same time,
        // so time-weighted balances should match actual balances
        assertEq(vault.getUserTimeWeightedShares(user1), depositAmount1, "User 1 time-weighted shares incorrect");
        assertEq(vault.getUserTimeWeightedShares(user2), depositAmount2, "User 2 time-weighted shares incorrect");
        
        // Fast forward to the end of the epoch
        vm.warp(block.timestamp + vault.EPOCH_DURATION());
        
        // Harvest the yield
        vm.prank(admin);
        uint256 yieldAmount = vault.checkAndHarvest();
        console.log("Harvested yield:", yieldAmount);
        
        // Expected rewards based on proportional deposits
        uint256 totalDeposits = depositAmount1 + depositAmount2;
        uint256 expectedReward1 = (yieldAmount * depositAmount1) / totalDeposits;
        uint256 expectedReward2 = (yieldAmount * depositAmount2) / totalDeposits;
        
        console.log("Expected reward for User 1:", expectedReward1);
        console.log("Expected reward for User 2:", expectedReward2);
        
        // Check balances after rewards
        uint256 balanceAfter1 = vault.balanceOf(user1);
        uint256 balanceAfter2 = vault.balanceOf(user2);
        
        console.log("User 1 balance after rewards:", balanceAfter1);
        console.log("User 2 balance after rewards:", balanceAfter2);
        
        // Verify rewards were distributed correctly
        assertApproxEqRel(balanceAfter1, depositAmount1 + expectedReward1, 0.01e18, "User 1 reward incorrect");
        assertApproxEqRel(balanceAfter2, depositAmount2 + expectedReward2, 0.01e18, "User 2 reward incorrect");
        
        console.log("Two users same epoch test passed");
    }
    
    function testTwoUsersSameEpochDifferentTime() public {
        // User 1 deposits at the start of the epoch
        uint256 depositAmount1 = 200 * 1e6; // 200 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1);
        vault.deposit(user1, depositAmount1);
        vm.stopPrank();
        
        console.log("User 1 deposited at epoch start:", depositAmount1);
        console.log("User 1 time-weighted initial:", vault.getUserTimeWeightedShares(user1));
        
        // Advance time to 60% through the epoch
        vm.warp(block.timestamp + (vault.EPOCH_DURATION() * 60) / 100);
        
        // User 2 deposits when 60% of the epoch has passed (only 40% time remaining)
        uint256 depositAmount2 = 500 * 1e6; // 500 USDC (larger amount)
        
        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount2);
        vault.deposit(user2, depositAmount2);
        vm.stopPrank();
        
        console.log("User 2 deposited at 60% of epoch:", depositAmount2);
        
        // User 2's time-weighted amount should be proportional to time remaining in epoch
        uint256 expectedTimeWeighted2 = (depositAmount2 * 40) / 100; // 40% of the deposit
        uint256 actualTimeWeighted2 = vault.getUserTimeWeightedShares(user2);
        
        console.log("User 2 expected time-weighted:", expectedTimeWeighted2);
        console.log("User 2 actual time-weighted:", actualTimeWeighted2);
        
        assertApproxEqRel(actualTimeWeighted2, expectedTimeWeighted2, 0.01e18, "User 2 time-weighted incorrect");
        
        // Fast forward to the end of the epoch
        vm.warp(block.timestamp + vault.EPOCH_DURATION() * 40 / 100);
        
        // Harvest the yield
        vm.prank(admin);
        uint256 yieldAmount = vault.checkAndHarvest();
        console.log("Harvested yield:", yieldAmount);
        
        // Expected rewards based on time-weighted deposits
        uint256 user1TimeWeighted = depositAmount1; // Full weight for first depositor
        uint256 totalTimeWeighted = user1TimeWeighted + expectedTimeWeighted2;
        uint256 expectedReward1 = (yieldAmount * user1TimeWeighted) / totalTimeWeighted;
        uint256 expectedReward2 = (yieldAmount * expectedTimeWeighted2) / totalTimeWeighted;
        
        console.log("Total time-weighted:", totalTimeWeighted);
        console.log("Expected reward for User 1:", expectedReward1);
        console.log("Expected reward for User 2:", expectedReward2);
        
        // Check balances after rewards
        uint256 balanceAfter1 = vault.balanceOf(user1);
        uint256 balanceAfter2 = vault.balanceOf(user2);
        
        console.log("User 1 balance after rewards:", balanceAfter1);
        console.log("User 2 balance after rewards:", balanceAfter2);
        
        // Verify rewards were distributed correctly based on time-weighting
        assertApproxEqRel(balanceAfter1, depositAmount1 + expectedReward1, 0.02e18, "User 1 reward incorrect");
        assertApproxEqRel(balanceAfter2, depositAmount2 + expectedReward2, 0.02e18, "User 2 reward incorrect");
        
        console.log("Two users same epoch different time test passed");
    }
    
    function testTwoUsersDifferentEpoch() public {
        // User 1 deposits in first epoch
        uint256 depositAmount1 = 100 * 1e6; // 100 USDC
        
        console.log("=== EPOCH 0 ===");
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1);
        vault.deposit(user1, depositAmount1);
        vm.stopPrank();
        
        console.log("User 1 deposited in epoch 0:", depositAmount1);
        
        // Fast forward to epoch 200
        vm.warp(block.timestamp + vault.EPOCH_DURATION() * 200);
        console.log("=== EPOCH 200 ===");
        
        // Harvest at end of epoch 200
        vm.prank(admin);
        uint256 accrued1 = vault.checkAndHarvest();
        console.log("Harvested after 200 epochs:", accrued1);
        
        // Check user1 balance after 200 epochs of yield
        uint256 balanceAfter200 = vault.balanceOf(user1);
        console.log("User 1 balance after 200 epochs:", balanceAfter200);
        
        // User 2 deposits in epoch 200
        uint256 depositAmount2 = 200 * 1e6; // 200 USDC
        
        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount2);
        vault.deposit(user2, depositAmount2);
        vm.stopPrank();
        
        console.log("User 2 deposited in epoch 200:", depositAmount2);
        
        // Fast forward to epoch 300
        vm.warp(block.timestamp + vault.EPOCH_DURATION() * 100);
        console.log("=== EPOCH 300 ===");
        
        // Harvest at end of epoch 300
        vm.prank(admin);
        uint256 accrued2 = vault.checkAndHarvest();
        console.log("Harvested after epochs 200-300:", accrued2);
        
        // Expected rewards for epoch 200-300 based on proportional deposits
        uint256 userBalance1 = balanceAfter200;
        uint256 userBalance2 = depositAmount2;
        uint256 totalBalance = userBalance1 + userBalance2;
        
        uint256 expectedReward1 = (accrued2 * userBalance1) / totalBalance;
        uint256 expectedReward2 = (accrued2 * userBalance2) / totalBalance;
        
        console.log("User 1 expected reward for epochs 200-300:", expectedReward1);
        console.log("User 2 expected reward for epochs 200-300:", expectedReward2);
        
        // Check balances after rewards
        uint256 balanceAfter300_1 = vault.balanceOf(user1);
        uint256 balanceAfter300_2 = vault.balanceOf(user2);
        
        console.log("User 1 balance after 300 epochs:", balanceAfter300_1);
        console.log("User 2 balance after 300 epochs:", balanceAfter300_2);
        
        // Verify rewards were distributed correctly
        assertApproxEqRel(balanceAfter300_1, userBalance1 + expectedReward1, 0.01e18, "User 1 reward incorrect");
        assertApproxEqRel(balanceAfter300_2, userBalance2 + expectedReward2, 0.01e18, "User 2 reward incorrect");
        
        // Fast forward to epoch 500
        vm.warp(block.timestamp + vault.EPOCH_DURATION() * 200);
        console.log("=== EPOCH 500 ===");
        
        // Harvest at end of epoch 500
        vm.prank(admin);
        uint256 accrued3 = vault.checkAndHarvest();
        console.log("Harvested after epochs 300-500:", accrued3);
        
        // Check final balances after 500 epochs
        uint256 balanceAfter500_1 = vault.balanceOf(user1);
        uint256 balanceAfter500_2 = vault.balanceOf(user2);
        
        console.log("User 1 final balance after 500 epochs:", balanceAfter500_1);
        console.log("User 2 final balance after 500 epochs:", balanceAfter500_2);
        
        // Verify final balances are greater than previous balances (rewards were added)
        assertGt(balanceAfter500_1, balanceAfter300_1, "User 1 should have earned rewards in epochs 300-500");
        assertGt(balanceAfter500_2, balanceAfter300_2, "User 2 should have earned rewards in epochs 300-500");
        
        console.log("Two users different epoch test passed");
    }
    
    function testEarlyWithdrawalFee() public {
        // User 1 deposits
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(user1, depositAmount);
        
        // Try to withdraw in the same epoch (should incur early withdrawal fee)
        uint256 withdrawAmount =100 * 1e6; // 50 USDC
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
        
        console.log("Early withdrawal fee test passed");
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
        
        console.log("Withdrawal proportional time-weighted reduction test passed");
    }

    function testSingleUserMultipleDeposits() public {
        // User 1 deposits at the start of the epoch
        uint256 depositAmount1 = 200 * 1e6; // 200 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1 * 2); // Approve for both deposits
        vault.deposit(user1, depositAmount1);
        vm.stopPrank();
        
        console.log("User 1 first deposit at epoch start:", depositAmount1);
        
        // First deposit should have full time weight
        uint256 timeWeightedAfterFirstDeposit = vault.getUserTimeWeightedShares(user1);
        console.log("User 1 time-weighted after first deposit:", timeWeightedAfterFirstDeposit);
        assertEq(timeWeightedAfterFirstDeposit, depositAmount1, "First deposit should have full time weight");
        
        // Advance time to 60% through the epoch
        vm.warp(block.timestamp + (vault.EPOCH_DURATION() * 60) / 100);
        
        // User 1 makes a second deposit when 60% of the epoch has passed (only 40% time remaining)
        uint256 depositAmount2 = 300 * 1e6; // 300 USDC (different amount)
        
        vm.startPrank(user1);
        console.log(IERC20(USDC_ADDRESS).balanceOf(user1));
        IERC20(USDC_ADDRESS).approve(address(vault), depositAmount2);
        vault.deposit(user1, depositAmount2);
        console.log("deposited");
        vm.stopPrank();
        
        console.log("User 1 second deposit at 60% of epoch:", depositAmount2);
        
        // Second deposit's time-weighted amount should be proportional to time remaining in epoch
        uint256 expectedTimeWeightedForSecondDeposit = (depositAmount2 * 40) / 100; // 40% of the second deposit
        uint256 expectedTotalTimeWeighted = depositAmount1 + expectedTimeWeightedForSecondDeposit;
        uint256 actualTotalTimeWeighted = vault.getUserTimeWeightedShares(user1);
        
        console.log("Expected time-weighted for second deposit:", expectedTimeWeightedForSecondDeposit);
        console.log("Expected total time-weighted:", expectedTotalTimeWeighted);
        console.log("Actual total time-weighted:", actualTotalTimeWeighted);
        
        assertApproxEqRel(actualTotalTimeWeighted, expectedTotalTimeWeighted, 0.01e18, "Total time-weighted shares incorrect");
        
        // Fast forward to the end of the epoch
        vm.warp(block.timestamp + vault.EPOCH_DURATION() * 40 / 100);
        
        // Harvest the yield
        vm.prank(admin);
        uint256 yieldAmount = vault.checkAndHarvest();
        console.log("Harvested yield:", yieldAmount);
        
        // User should receive all yield since they're the only one in the vault
        uint256 expectedFinalBalance = depositAmount1 + depositAmount2 + yieldAmount;
        uint256 actualFinalBalance = vault.balanceOf(user1);
        
        console.log("Total deposits:", depositAmount1 + depositAmount2);
        console.log("Expected final balance with yield:", expectedFinalBalance);
        console.log("Actual final balance:", actualFinalBalance);
        
        assertApproxEqRel(actualFinalBalance, expectedFinalBalance, 0.01e18, "Final balance with yield incorrect");
        
        // After harvest, the time-weighted shares should equal the actual balance
        uint256 timeWeightedAfterHarvest = vault.getUserTimeWeightedShares(user1);
        console.log("Time-weighted shares after harvest:", timeWeightedAfterHarvest);
        assertEq(timeWeightedAfterHarvest, actualFinalBalance, "Time-weighted shares should match balance after harvest");
        
        console.log("Single user multiple deposits test passed");
    }
}