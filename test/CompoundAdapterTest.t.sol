// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/adapters/mocks/MockCompoundAdapter.sol";

import "../src/tokens/mocks/MockUSDC.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";

contract CompoundAdapterTest is Test {
    // Test accounts
    address public admin;
    address public user1;
    address public user2;
    
    // Core contracts
    ProtocolRegistry public registry;
    MockCompoundAdapter public mockCompoundAdapter;
    
    // Token
    MockUSDC public mockUSDC;
    
    // Constants for testing
    uint256 constant INITIAL_MINT = 10000 * 1e6; // 10,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 1000 * 1e6; // 1,000 USDC
    
    // Let's add a constant for Compound v3 Protocol ID
    uint256 constant COMPOUND_PROTOCOL_ID = 4; // Assuming 1-3 are already used
    
    function setUp() public {
        // Create test accounts
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Deploy as admin
        vm.startPrank(admin);
        
        // Deploy mock USDC
        mockUSDC = new MockUSDC(admin);
        console.log("MockUSDC deployed at:", address(mockUSDC));
        
        // Deploy registry
        registry = new ProtocolRegistry();
        console.log("Registry deployed at:", address(registry));
        
        // Deploy mock Compound adapter
        mockCompoundAdapter = new MockCompoundAdapter(address(mockUSDC));
        console.log("MockCompoundAdapter deployed at:", address(mockCompoundAdapter));
        
        // Add adapter as minter for MockUSDC
        mockUSDC.addMinter(address(mockCompoundAdapter));
        console.log("Added adapter as minter for MockUSDC");
        
        // Set APY for testing
        mockCompoundAdapter.setAPY(address(mockUSDC), 450); // 4.5%
        
        // Register protocol
        registry.registerProtocol(COMPOUND_PROTOCOL_ID, "Mock Compound v3");
        
        // Register adapter
        registry.registerAdapter(COMPOUND_PROTOCOL_ID, address(mockUSDC), address(mockCompoundAdapter));
        
        // Mint USDC to test users
        mockUSDC.mint(user1, INITIAL_MINT);
        mockUSDC.mint(user2, INITIAL_MINT);
        
        vm.stopPrank();
        
        console.log("Test setup complete");
        console.log("User1 USDC balance:", mockUSDC.balanceOf(user1));
        console.log("User2 USDC balance:", mockUSDC.balanceOf(user2));
    }
    
    function testSupplyAndWithdraw() public {
        console.log("===== Testing Supply and Withdraw =====");
        
        // User1 deposits to Compound adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockCompoundAdapter), DEPOSIT_AMOUNT);
        uint256 supplied = mockCompoundAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        console.log("User1 supplied:", supplied);
        
        // Check balance in adapter
        uint256 adapterBalance = mockCompoundAdapter.getBalance(address(mockUSDC));
        console.log("Adapter balance:", adapterBalance);
        
        // Check total principal
        uint256 totalPrincipal = mockCompoundAdapter.getTotalPrincipal(address(mockUSDC));
        console.log("Total principal:", totalPrincipal);
        
        // Verify supplied amount
        assertEq(supplied, DEPOSIT_AMOUNT, "Supplied amount should match deposit");
        assertEq(totalPrincipal, DEPOSIT_AMOUNT, "Total principal should match deposit");
        
        // Withdraw half
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        vm.startPrank(user1);
        uint256 withdrawn = mockCompoundAdapter.withdraw(address(mockUSDC), withdrawAmount);
        vm.stopPrank();
        
        console.log("Withdrawn amount:", withdrawn);
        
        // Check updated total principal
        totalPrincipal = mockCompoundAdapter.getTotalPrincipal(address(mockUSDC));
        console.log("Total principal after withdrawal:", totalPrincipal);
        
        // Verify withdrawal
        assertEq(withdrawn, withdrawAmount, "Withdrawn amount should match request");
        assertEq(totalPrincipal, DEPOSIT_AMOUNT - withdrawAmount, "Total principal should be reduced by withdrawn amount");
    }
    
    function testHarvestYield() public {
        console.log("===== Testing Harvest Yield =====");
        
        // User1 deposits to Compound adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockCompoundAdapter), DEPOSIT_AMOUNT);
        mockCompoundAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        console.log("User1 deposited:", DEPOSIT_AMOUNT);
        
        // Fast forward 30 days to accrue interest
        skip(30 days);
        
        // Get estimated interest
        uint256 estimatedInterest = mockCompoundAdapter.getEstimatedInterest(address(mockUSDC));
        console.log("Estimated interest after 30 days:", estimatedInterest);
        
        // Harvest as admin
        vm.prank(admin);
        uint256 harvestedAmount = mockCompoundAdapter.harvest(address(mockUSDC));
        console.log("Harvested amount:", harvestedAmount);
        
        // Verify harvested amount is close to estimated
        assertApproxEqRel(harvestedAmount, estimatedInterest, 0.01e18, "Harvested amount should be close to estimated");
        
        // Check time since last harvest
        uint256 timeSinceHarvest = block.timestamp - mockCompoundAdapter.lastHarvestTimestamp(address(mockUSDC));
        console.log("Time since harvest:", timeSinceHarvest);
        assertEq(timeSinceHarvest, 0, "Time since harvest should be zero right after harvest");
        
        // Fast forward another 15 days
        skip(15 days);
        
        // Check time since last harvest again
        timeSinceHarvest = block.timestamp - mockCompoundAdapter.lastHarvestTimestamp(address(mockUSDC));
        console.log("Time since harvest after 15 days:", timeSinceHarvest);
        assertEq(timeSinceHarvest, 15 days, "Time since harvest should be 15 days");
    }
    
    function testConvertFeeToReward() public {
        console.log("===== Testing Convert Fee to Reward =====");
        
        // User1 deposits to Compound adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockCompoundAdapter), DEPOSIT_AMOUNT);
        mockCompoundAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Get initial principal
        uint256 initialPrincipal = mockCompoundAdapter.getTotalPrincipal(address(mockUSDC));
        console.log("Initial principal:", initialPrincipal);
        
        // Convert fee to reward (5% of deposit)
        uint256 feeAmount = DEPOSIT_AMOUNT * 5 / 100;
        console.log("Fee amount to convert:", feeAmount);
        
        vm.prank(admin);
        mockCompoundAdapter.convertFeeToReward(address(mockUSDC), feeAmount);
        
        // Get final principal
        uint256 finalPrincipal = mockCompoundAdapter.getTotalPrincipal(address(mockUSDC));
        console.log("Final principal:", finalPrincipal);
        
        // Verify principal reduced by fee amount
        assertEq(finalPrincipal, initialPrincipal - feeAmount, "Principal should be reduced by fee amount");
    }
    
    function testWithdrawToUser() public {
        console.log("===== Testing Withdraw To User =====");
        
        // User1 deposits to Compound adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockCompoundAdapter), DEPOSIT_AMOUNT);
        mockCompoundAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Get initial balances
        uint256 user2InitialBalance = mockUSDC.balanceOf(user2);
        console.log("User2 initial balance:", user2InitialBalance);
        
        // User1 withdraws to User2
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        vm.startPrank(user1);
        uint256 withdrawn = mockCompoundAdapter.withdrawToUser(address(mockUSDC), withdrawAmount, user2);
        vm.stopPrank();
        
        console.log("Withdrawn to User2:", withdrawn);
        
        // Get User2's final balance
        uint256 user2FinalBalance = mockUSDC.balanceOf(user2);
        console.log("User2 final balance:", user2FinalBalance);
        
        // Verify User2 received the funds
        assertEq(user2FinalBalance - user2InitialBalance, withdrawAmount, "User2 should receive the withdrawn amount");
    }
    
    function testGetAPY() public {
        console.log("===== Testing Get APY =====");
        
        // Get APY
        uint256 apy = mockCompoundAdapter.getAPY(address(mockUSDC));
        console.log("Current APY (bps):", apy);
        
        // Should match what we set in setUp
        assertEq(apy, 450, "APY should be 450 bps (4.5%)");
        
        // Change APY
        vm.prank(admin);
        mockCompoundAdapter.setAPY(address(mockUSDC), 550);
        
        // Check updated APY
        apy = mockCompoundAdapter.getAPY(address(mockUSDC));
        console.log("Updated APY (bps):", apy);
        assertEq(apy, 550, "APY should be updated to 550 bps (5.5%)");
    }
}