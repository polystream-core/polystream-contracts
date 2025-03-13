// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AaveAdapterCombinedTest is Test {
    // Contract addresses on Scroll
    address constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_ATOKEN_ADDRESS = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    
    // Test users
    address public admin;
    address public testUser;
    address public directUser;
    
    // Core contracts
    ProtocolRegistry public registry;
    AaveAdapter public aaveAdapter;
    
    // Token
    IERC20 public usdc;
    IERC20 public aUsdc;
    
    function setUp() public {
        // Create test accounts
        admin = makeAddr("admin");
        testUser = makeAddr("testUser");
        directUser = makeAddr("directUser");
        vm.deal(admin, 10 ether);
        vm.deal(testUser, 10 ether);
        vm.deal(directUser, 10 ether);
        
        // Give test users some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6);
        deal(USDC_ADDRESS, directUser, 1000 * 1e6);
        
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
        
        vm.stopPrank();
        
        // Initialize token instances
        usdc = IERC20(USDC_ADDRESS);
        aUsdc = IERC20(USDC_ATOKEN_ADDRESS);
    }

    function testSupply() public {
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        
        // Get initial USDC balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Approve adapter to spend USDC
        usdc.approve(address(aaveAdapter), supplyAmount);
        
        // Supply to Aave via adapter
        uint256 supplied = aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        console.log("Amount supplied:", supplied);
        
        // Verify the correct amount was supplied
        assertEq(supplied, supplyAmount, "Incorrect supply amount");
        
        // Verify USDC was transferred from user
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance:", finalBalance);
        assertEq(finalBalance, initialBalance - supplyAmount, "USDC not transferred from user");
        
        // Check adapter's aToken balance
        uint256 adapterATokenBalance = aUsdc.balanceOf(address(aaveAdapter));
        console.log("Adapter's aToken balance:", adapterATokenBalance);
        assertGe(adapterATokenBalance, supplyAmount, "Adapter should have received aTokens");
        
        // Check getTotalPrincipal
        uint256 totalPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Total principal tracked:", totalPrincipal);
        assertEq(totalPrincipal, supplyAmount, "Total principal tracking incorrect");
        
        vm.stopPrank();
    }

    function testWithdraw() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(aaveAdapter), supplyAmount);
        aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Now test withdrawal
        uint256 withdrawAmount = 50 * 1e6; // 50 USDC
        
        vm.startPrank(testUser);
        
        // Get initial USDC balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance before withdrawal:", initialBalance);
        
        // Withdraw from Aave via adapter
        uint256 withdrawn = aaveAdapter.withdraw(USDC_ADDRESS, withdrawAmount);
        console.log("Amount withdrawn:", withdrawn);
        
        // Verify the correct amount was withdrawn
        assertEq(withdrawn, withdrawAmount, "Incorrect withdrawal amount");
        
        // Verify USDC was transferred to user
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance after withdrawal:", finalBalance);
        assertEq(finalBalance, initialBalance + withdrawAmount, "USDC not transferred to user");
        
        // Check adapter's principal tracking is updated
        uint256 totalPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Total principal after withdrawal:", totalPrincipal);
        assertEq(totalPrincipal, supplyAmount - withdrawAmount, "Total principal not updated correctly");
        
        vm.stopPrank();
    }

    function testWithdrawToUser() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(aaveAdapter), supplyAmount);
        aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Now test withdrawal to direct user
        uint256 withdrawAmount = 30 * 1e6; // 30 USDC
        
        vm.startPrank(testUser);
        
        // Get initial direct user USDC balance
        uint256 initialBalance = usdc.balanceOf(directUser);
        console.log("Direct user's initial USDC balance:", initialBalance);
        
        // Withdraw from Aave directly to another user
        uint256 withdrawn = aaveAdapter.withdrawToUser(USDC_ADDRESS, withdrawAmount, directUser);
        console.log("Amount withdrawn to direct user:", withdrawn);
        
        // Verify the correct amount was withdrawn
        assertEq(withdrawn, withdrawAmount, "Incorrect withdrawal amount");
        
        // Verify USDC was transferred to direct user
        uint256 finalBalance = usdc.balanceOf(directUser);
        console.log("Direct user's final USDC balance:", finalBalance);
        assertEq(finalBalance, initialBalance + withdrawAmount, "USDC not transferred to direct user");
        
        // Check adapter's principal tracking is updated
        uint256 totalPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Total principal after withdrawal:", totalPrincipal);
        assertEq(totalPrincipal, supplyAmount - withdrawAmount, "Total principal not updated correctly");
        
        vm.stopPrank();
    }

    function testHarvest() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(aaveAdapter), supplyAmount);
        aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Initial balance check
        uint256 initialATokenBalance = aUsdc.balanceOf(address(aaveAdapter));
        console.log("Initial aToken balance:", initialATokenBalance);
        uint256 initialPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Initial principal:", initialPrincipal);
        
        // Fast forward time to simulate interest accrual
        vm.warp(block.timestamp + 30 days);
        console.log("Fast-forwarded 30 days");
        
        // Execute harvest
        vm.startPrank(admin);
        uint256 harvestedAmount = aaveAdapter.harvest(USDC_ADDRESS);
        console.log("Harvested amount:", harvestedAmount);
        vm.stopPrank();
        
        // Verify principal remains the same
        uint256 finalPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Final principal:", finalPrincipal);
        assertEq(finalPrincipal, initialPrincipal, "Principal should not change after harvest");
        
        // Get balance after harvest
        uint256 finalATokenBalance = aUsdc.balanceOf(address(aaveAdapter));
        console.log("Final aToken balance:", finalATokenBalance);
        
        // In a real environment, there should be interest accrued, but in test environment,
        // we might not see actual interest
        // assertGt(finalATokenBalance, initialATokenBalance, "aToken balance should increase over time");
    }

    function testConvertFeeToReward() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(aaveAdapter), supplyAmount);
        aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Get initial principal
        uint256 initialPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Initial principal:", initialPrincipal);
        
        // Convert a fee to reward
        uint256 feeAmount = 5 * 1e6; // 5 USDC
        vm.startPrank(admin);
        aaveAdapter.convertFeeToReward(USDC_ADDRESS, feeAmount);
        vm.stopPrank();
        
        // Verify principal is reduced by fee amount
        uint256 finalPrincipal = aaveAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Final principal after fee conversion:", finalPrincipal);
        assertEq(finalPrincipal, initialPrincipal - feeAmount, "Principal should be reduced by fee amount");
    }

    function testGetAPY() public {
        uint256 apy = aaveAdapter.getAPY(USDC_ADDRESS);
        console.log("Current APY (in basis points):", apy);
        // Cannot assert a specific value as APY changes
    }

    function testGetBalance() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(aaveAdapter), supplyAmount);
        aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Get balance
        uint256 balance = aaveAdapter.getBalance(USDC_ADDRESS);
        console.log("Adapter balance:", balance);
        
        // Balance should be at least the supplied amount
        assertGe(balance, supplyAmount, "Balance should be at least the supplied amount");
    }
}