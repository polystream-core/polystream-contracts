// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/tokens/mocks/MockUSDC.sol";
import "../src/adapters/mocks/MockAaveAdapter.sol";
import "../src/adapters/mocks/MockLayerBankAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";

/**
 * @title MockAdaptersTest
 * @notice Tests for mock protocol adapters
 */
contract MockAdaptersTest is Test {
    // Test accounts
    address public admin;
    address public user1;
    address public user2;
    
    // Mock contracts
    MockUSDC public mockUSDC;
    MockAaveAdapter public mockAaveAdapter;
    MockLayerBankAdapter public mockLayerBankAdapter;
    ProtocolRegistry public registry;
    
    // Constants for test
    uint256 constant INITIAL_MINT = 1000000 * 1e6; // 1,000,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 10000 * 1e6; // 10,000 USDC
    
    function setUp() public {
        // Set up test accounts
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.deal(admin, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Deploy contracts as admin
        vm.startPrank(admin);
        
        // 1. Deploy mock USDC
        mockUSDC = new MockUSDC(admin);
        
        // 2. Deploy mock adapters
        mockAaveAdapter = new MockAaveAdapter(address(mockUSDC));
        mockLayerBankAdapter = new MockLayerBankAdapter(address(mockUSDC));

        // Add adapters as minters for MockUSDC
        mockUSDC.addMinter(address(mockAaveAdapter));
        mockUSDC.addMinter(address(mockLayerBankAdapter));
        console.log("Added adapters as minters for MockUSDC");
        
        // 3. Deploy registry
        registry = new ProtocolRegistry();
        
        // 4. Register protocols in registry
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Mock Aave V3");
        registry.registerProtocol(Constants.LAYERBANK_PROTOCOL_ID, "Mock LayerBank");
        
        // 5. Add supported assets to adapters
        mockAaveAdapter.addSupportedAsset(address(mockUSDC), address(mockUSDC)); // Using same address for simplicity
        mockLayerBankAdapter.addSupportedAsset(address(mockUSDC), address(mockUSDC));
        
        // 6. Register adapters in registry
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, address(mockUSDC), address(mockAaveAdapter));
        registry.registerAdapter(Constants.LAYERBANK_PROTOCOL_ID, address(mockUSDC), address(mockLayerBankAdapter));
        
        // 7. Mint initial USDC to users
        mockUSDC.mint(user1, INITIAL_MINT);
        mockUSDC.mint(user2, INITIAL_MINT);
        
        // 8. Set different APYs for testing yield switching
        mockAaveAdapter.setAPY(address(mockUSDC), 300); // 3%
        mockLayerBankAdapter.setAPY(address(mockUSDC), 500); // 5%
        
        vm.stopPrank();
        
        console.log("Test setup complete");
        console.log("MockUSDC deployed at:", address(mockUSDC));
        console.log("MockAaveAdapter deployed at:", address(mockAaveAdapter));
        console.log("MockLayerBankAdapter deployed at:", address(mockLayerBankAdapter));
        console.log("Registry deployed at:", address(registry));
        console.log("User1 USDC balance:", mockUSDC.balanceOf(user1));
        console.log("User2 USDC balance:", mockUSDC.balanceOf(user2));
    }
    
    function testDepositWithdraw() public {
        console.log("===== Testing Deposit/Withdraw =====");
        
        // User1 deposits to Aave adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockAaveAdapter), DEPOSIT_AMOUNT);
        mockAaveAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // User2 deposits to LayerBank adapter
        vm.startPrank(user2);
        mockUSDC.approve(address(mockLayerBankAdapter), DEPOSIT_AMOUNT);
        mockLayerBankAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check balances
        uint256 aaveBalance = mockAaveAdapter.getBalance(address(mockUSDC));
        uint256 layerBankBalance = mockLayerBankAdapter.getBalance(address(mockUSDC));
        
        console.log("Aave adapter balance:", aaveBalance);
        console.log("LayerBank adapter balance:", layerBankBalance);
        
        // Check principal
        uint256 aavePrincipal = mockAaveAdapter.getTotalPrincipal(address(mockUSDC));
        uint256 layerBankPrincipal = mockLayerBankAdapter.getTotalPrincipal(address(mockUSDC));
        
        console.log("Aave adapter principal:", aavePrincipal);
        console.log("LayerBank adapter principal:", layerBankPrincipal);
        
        // Check APYs
        uint256 aaveAPY = mockAaveAdapter.getAPY(address(mockUSDC));
        uint256 layerBankAPY = mockLayerBankAdapter.getAPY(address(mockUSDC));
        
        console.log("Aave adapter APY:", aaveAPY);
        console.log("LayerBank adapter APY:", layerBankAPY);
        
        // Withdraw half from each adapter
        vm.startPrank(user1);
        uint256 aaveWithdrawn = mockAaveAdapter.withdraw(address(mockUSDC), DEPOSIT_AMOUNT / 2);
        vm.stopPrank();
        
        vm.startPrank(user2);
        uint256 layerBankWithdrawn = mockLayerBankAdapter.withdraw(address(mockUSDC), DEPOSIT_AMOUNT / 2);
        vm.stopPrank();
        
        console.log("Aave withdrawn:", aaveWithdrawn);
        console.log("LayerBank withdrawn:", layerBankWithdrawn);
        
        // Check updated balances
        console.log("User1 USDC balance after withdrawal:", mockUSDC.balanceOf(user1));
        console.log("User2 USDC balance after withdrawal:", mockUSDC.balanceOf(user2));
    }
    
    function testHarvestYield() public {
        console.log("===== Testing Harvest Yield =====");
        
        // Both users deposit to Aave adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockAaveAdapter), DEPOSIT_AMOUNT);
        mockAaveAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        mockUSDC.approve(address(mockAaveAdapter), DEPOSIT_AMOUNT);
        mockAaveAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Fast forward 30 days to accrue interest
        skip(30 days);
        
        // Get pre-harvest balance
        uint256 preHarvestBalance = mockAaveAdapter.getBalance(address(mockUSDC));
        console.log("Aave adapter balance before harvest:", preHarvestBalance);
        
        // Get estimated interest
        uint256 estimatedInterest = mockAaveAdapter.getEstimatedInterest(address(mockUSDC));
        console.log("Estimated interest:", estimatedInterest);
        
        // Harvest as admin
        vm.prank(admin);
        uint256 harvestedAmount = mockAaveAdapter.harvest(address(mockUSDC));
        console.log("Harvested amount:", harvestedAmount);
        
        // Get post-harvest balance
        uint256 postHarvestBalance = mockAaveAdapter.getBalance(address(mockUSDC));
        console.log("Aave adapter balance after harvest:", postHarvestBalance);
        
        // Verify that harvested amount is close to our estimate
        assertApproxEqRel(harvestedAmount, estimatedInterest, 0.01e18, "Harvested amount should match estimate");
    }
    
    function testLayerBankExchangeRate() public {
        console.log("===== Testing LayerBank Exchange Rate =====");
        
        // Get initial exchange rate
        uint256 initialRate = mockLayerBankAdapter.getExchangeRate(address(mockUSDC));
        console.log("Initial exchange rate:", initialRate);
        
        // User1 deposits to LayerBank adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockLayerBankAdapter), DEPOSIT_AMOUNT);
        mockLayerBankAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Get gToken balance
        uint256 gTokenBalance = mockLayerBankAdapter.getGTokenBalance(address(mockUSDC));
        console.log("gToken balance:", gTokenBalance);
        
        // Fast forward 60 days to accrue interest
        skip(60 days);
        
        // Harvest to update exchange rate
        vm.prank(admin);
        uint256 harvestedAmount = mockLayerBankAdapter.harvest(address(mockUSDC));
        console.log("Harvested amount:", harvestedAmount);
        
        // Get new exchange rate
        uint256 newRate = mockLayerBankAdapter.getExchangeRate(address(mockUSDC));
        console.log("New exchange rate:", newRate);
        
        // Verify exchange rate increased
        assertGt(newRate, initialRate, "Exchange rate should increase after harvest");
        
        // Calculate expected balance
        uint256 expectedBalance = (gTokenBalance * newRate) / 1e18;
        uint256 actualBalance = mockLayerBankAdapter.getBalance(address(mockUSDC));
        console.log("Expected balance:", expectedBalance);
        console.log("Actual balance:", actualBalance);
        
        // Verify balance matches calculation
        assertEq(actualBalance, expectedBalance, "Balance should match calculation from exchange rate");
    }
    
    function testFeeConversion() public {
        console.log("===== Testing Fee Conversion =====");
        
        // User1 deposits to Aave adapter
        vm.startPrank(user1);
        mockUSDC.approve(address(mockAaveAdapter), DEPOSIT_AMOUNT);
        mockAaveAdapter.supply(address(mockUSDC), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Get initial principal
        uint256 initialPrincipal = mockAaveAdapter.getTotalPrincipal(address(mockUSDC));
        console.log("Initial principal:", initialPrincipal);
        
        // Convert fee to reward (5% of deposit)
        uint256 feeAmount = DEPOSIT_AMOUNT * 5 / 100;
        console.log("Fee amount to convert:", feeAmount);
        
        vm.prank(admin);
        mockAaveAdapter.convertFeeToReward(address(mockUSDC), feeAmount);
        
        // Get final principal
        uint256 finalPrincipal = mockAaveAdapter.getTotalPrincipal(address(mockUSDC));
        console.log("Final principal:", finalPrincipal);
        
        // Verify principal reduced by fee amount
        assertEq(finalPrincipal, initialPrincipal - feeAmount, "Principal should be reduced by fee amount");
    }
}