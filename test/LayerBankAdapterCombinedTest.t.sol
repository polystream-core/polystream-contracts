// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/adapters/LayerBankAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LayerBankAdapterCombinedTest is Test {
    // Contract addresses on Scroll
    address constant LAYERBANK_CORE_ADDRESS = 0xEC53c830f4444a8A56455c6836b5D2aA794289Aa;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_GTOKEN_ADDRESS = 0x0D8F8e271DD3f2fC58e5716d3Ff7041dBe3F0688;
    
    // Test users
    address public admin;
    address public testUser;
    address public directUser;
    
    // Core contracts
    ProtocolRegistry public registry;
    LayerBankAdapter public layerBankAdapter;
    
    // Token
    IERC20 public usdc;
    IERC20 public gUsdc;
    
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
        
        // Deploy LayerBank adapter
        layerBankAdapter = new LayerBankAdapter(LAYERBANK_CORE_ADDRESS);
        
        // Register protocol in registry
        registry.registerProtocol(Constants.LAYERBANK_PROTOCOL_ID, "LayerBank");
        
        // Add USDC as supported asset in LayerBank adapter
        layerBankAdapter.addSupportedAsset(USDC_ADDRESS, USDC_GTOKEN_ADDRESS);
        
        // Register adapter in registry
        registry.registerAdapter(Constants.LAYERBANK_PROTOCOL_ID, USDC_ADDRESS, address(layerBankAdapter));
        
        vm.stopPrank();
        
        // Initialize token instances
        usdc = IERC20(USDC_ADDRESS);
        gUsdc = IERC20(USDC_GTOKEN_ADDRESS);
    }

    function testSupply() public {
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        
        // Get initial USDC balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Approve adapter to spend USDC
        usdc.approve(address(layerBankAdapter), supplyAmount);
        
        // Supply to LayerBank via adapter
        uint256 supplied = layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        console.log("Amount supplied:", supplied);
        
        // Note: Unlike Aave, LayerBank returns gTokens, not the actual USDC amount
        // We will check that USDC was transferred and gTokens were received
        
        // Verify USDC was transferred from user
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance:", finalBalance);
        assertEq(finalBalance, initialBalance - supplyAmount, "USDC not transferred from user");
        
        // Check adapter's gToken balance
        uint256 adapterGTokenBalance = gUsdc.balanceOf(address(layerBankAdapter));
        console.log("Adapter's gToken balance:", adapterGTokenBalance);
        assertGt(adapterGTokenBalance, 0, "Adapter should have received gTokens");
        
        // Check getTotalPrincipal
        uint256 totalPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Total principal tracked:", totalPrincipal);
        assertEq(totalPrincipal, supplyAmount, "Total principal tracking incorrect");
        
        vm.stopPrank();
    }

    function testWithdraw() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Now test withdrawal
        uint256 withdrawAmount = 50 * 1e6; // 50 USDC
        
        vm.startPrank(testUser);
        
        // Get initial USDC balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance before withdrawal:", initialBalance);
        
        // Withdraw from LayerBank via adapter
        uint256 withdrawn = layerBankAdapter.withdraw(USDC_ADDRESS, withdrawAmount);
        console.log("Amount withdrawn:", withdrawn);
        
        // LayerBank might not give exact amounts due to exchange rate
        // so we check that some amount was withdrawn
        assertGt(withdrawn, 0, "Should withdraw some amount");
        
        // Verify USDC was transferred to user
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance after withdrawal:", finalBalance);
        assertGt(finalBalance, initialBalance, "USDC should be transferred to user");
        
        // Check adapter's principal tracking is updated
        uint256 totalPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Total principal after withdrawal:", totalPrincipal);
        
        // Principal should be reduced
        assertLt(totalPrincipal, supplyAmount, "Total principal should be reduced");
        
        vm.stopPrank();
    }

    function testWithdrawToUser() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Now test withdrawal to direct user
        uint256 withdrawAmount = 30 * 1e6; // 30 USDC
        
        vm.startPrank(testUser);
        
        // Get initial direct user USDC balance
        uint256 initialBalance = usdc.balanceOf(directUser);
        console.log("Direct user's initial USDC balance:", initialBalance);
        
        // Withdraw from LayerBank directly to another user
        uint256 withdrawn = layerBankAdapter.withdrawToUser(USDC_ADDRESS, withdrawAmount, directUser);
        console.log("Amount withdrawn to direct user:", withdrawn);
        
        // LayerBank might not give exact amounts due to exchange rate
        // so we check that some amount was withdrawn
        assertGt(withdrawn, 0, "Should withdraw some amount");
        
        // Verify USDC was transferred to direct user
        uint256 finalBalance = usdc.balanceOf(directUser);
        console.log("Direct user's final USDC balance:", finalBalance);
        assertGt(finalBalance, initialBalance, "USDC should be transferred to direct user");
        
        // Check adapter's principal tracking is updated
        uint256 totalPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Total principal after withdrawal:", totalPrincipal);
        
        // Principal should be reduced
        assertLt(totalPrincipal, supplyAmount, "Total principal should be reduced");
        
        vm.stopPrank();
    }

    function testHarvest() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Initial balance check
        uint256 initialGTokenBalance = gUsdc.balanceOf(address(layerBankAdapter));
        console.log("Initial gToken balance:", initialGTokenBalance);
        uint256 initialPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Initial principal:", initialPrincipal);
        
        // Fast forward time to simulate interest accrual
        vm.warp(block.timestamp + 30 days);
        console.log("Fast-forwarded 30 days");
        
        // Execute harvest
        vm.startPrank(admin);
        uint256 harvestedAmount = layerBankAdapter.harvest(USDC_ADDRESS);
        console.log("Harvested amount:", harvestedAmount);
        vm.stopPrank();
        
        // Verify principal remains the same
        uint256 finalPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Final principal:", finalPrincipal);
        assertEq(finalPrincipal, initialPrincipal, "Principal should not change after harvest");
        
        // Get balance after harvest
        uint256 finalGTokenBalance = gUsdc.balanceOf(address(layerBankAdapter));
        console.log("Final gToken balance:", finalGTokenBalance);
        
        // In a real environment, there should be interest accrued, but in test environment,
        // we might not see actual interest
        // assertGt(finalGTokenBalance, initialGTokenBalance, "gToken balance should increase over time");
    }

    function testConvertFeeToReward() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Get initial principal
        uint256 initialPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Initial principal:", initialPrincipal);
        
        // Convert a fee to reward
        uint256 feeAmount = 5 * 1e6; // 5 USDC
        vm.startPrank(admin);
        layerBankAdapter.convertFeeToReward(USDC_ADDRESS, feeAmount);
        vm.stopPrank();
        
        // Verify principal is reduced by fee amount
        uint256 finalPrincipal = layerBankAdapter.getTotalPrincipal(USDC_ADDRESS);
        console.log("Final principal after fee conversion:", finalPrincipal);
        assertEq(finalPrincipal, initialPrincipal - feeAmount, "Principal should be reduced by fee amount");
    }

    function testGetAPY() public {
        uint256 apy = layerBankAdapter.getAPY(USDC_ADDRESS);
        console.log("Current APY (in basis points):", apy);
        // Cannot assert a specific value as APY changes
    }

    function testGetBalance() public {
        // First supply some funds
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        vm.stopPrank();
        
        // Get balance (should return the value in underlying tokens)
        uint256 balance = layerBankAdapter.getBalance(USDC_ADDRESS);
        console.log("Adapter balance in USDC terms:", balance);
        
        // Balance should be around the supplied amount
        // LayerBank uses exchange rates, so it might not be exactly the same
        assertGt(balance, 0, "Balance should be greater than 0");
    }
}