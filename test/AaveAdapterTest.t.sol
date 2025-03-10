// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AaveAdapterTest is Test {
    // Contract addresses on Scroll
    address constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_ATOKEN_ADDRESS = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    
    // Test user
    address public testUser;
    
    // Core contracts
    ProtocolRegistry public registry;
    AaveAdapter public aaveAdapter;
    
    // Token
    IERC20 public usdc;
    
    function setUp() public {
        // Create a test user
        testUser = makeAddr("testUser");
        vm.deal(testUser, 10 ether);
        
        // Give the test user some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6);
        
        // Deploy registry and adapters
        registry = new ProtocolRegistry();
        console.log("Registry deployed at:", address(registry));

        aaveAdapter = new AaveAdapter(AAVE_POOL_ADDRESS);
        console.log("Aave Adapter deployed at:", address(aaveAdapter));
        
        // Register Aave protocol in the registry
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Aave V3");
        console.log("Aave protocol registered in the registry");
        
        // Add USDC as a supported asset in the Aave adapter with its known aToken address
        aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS);
        console.log("USDC added as a supported asset in the Aave adapter with aToken:", USDC_ATOKEN_ADDRESS);
        
        // Register the Aave adapter for USDC in the registry
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS, address(aaveAdapter));
        console.log("Aave adapter registered in the registry for USDC");
        
        // Initialize token instance
        usdc = IERC20(USDC_ADDRESS);
        
        // Log setup information
        console.log("Test setup complete");
        console.log("USDC balance of test user:", usdc.balanceOf(testUser));
    }
    
    function testAdapterSetup() public view {
        console.log("===== Testing Adapter Setup =====");
        
        // Check if adapter supports USDC
        bool isSupported = aaveAdapter.isAssetSupported(USDC_ADDRESS);
        console.log("Adapter supports USDC:", isSupported);
        assert(isSupported);
        
        // Check aToken mapping
        address aToken = aaveAdapter.aTokens(USDC_ADDRESS);
        console.log("aToken for USDC:", aToken);
        assert(aToken == USDC_ATOKEN_ADDRESS);
        
        // Check registry has adapter
        bool hasAdapter = registry.hasAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS);
        console.log("Registry has adapter for USDC:", hasAdapter);
        assert(hasAdapter);
    }
    
    function testAaveSupply() public {
        console.log("===== Testing Aave Supply via Adapter =====");
        
        // Get initial balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Approve and supply
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        
        // Get adapter from registry
        IProtocolAdapter adapter = registry.getAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS);
        
        // Approve adapter to spend USDC
        usdc.approve(address(adapter), supplyAmount);
        
        // Supply USDC through the adapter
        uint256 received = adapter.supply(USDC_ADDRESS, supplyAmount);
        console.log("Adapter supply successful, received:", received);
        
        vm.stopPrank();
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance:", finalBalance);
        console.log("USDC spent:", initialBalance - finalBalance);
        
        // Check balance in the Aave protocol
        uint256 protocolBalance = adapter.getBalance(USDC_ADDRESS);
        console.log("Balance in Aave protocol:", protocolBalance);
        
        // Verify balance
        assertGe(protocolBalance, supplyAmount - 1); // Allow for small rounding errors
    }
    
    function testAaveWithdraw() public {
        console.log("===== Testing Aave Withdraw via Adapter =====");
        
        // First supply some USDC
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        
        // Get adapter from registry
        IProtocolAdapter adapter = registry.getAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS);
        
        // Approve adapter to spend USDC
        usdc.approve(address(adapter), supplyAmount);
        
        // Supply USDC through the adapter
        adapter.supply(USDC_ADDRESS, supplyAmount);
        
        // Get balance before withdrawal
        uint256 balanceBefore = usdc.balanceOf(testUser);
        console.log("USDC balance before withdrawal:", balanceBefore);
        
        // Withdraw half of the supplied amount
        uint256 withdrawAmount = supplyAmount / 2;
        uint256 withdrawn = adapter.withdraw(USDC_ADDRESS, withdrawAmount);
        console.log("Withdrawn USDC:", withdrawn);
        
        vm.stopPrank();
        
        // Check final balance
        uint256 balanceAfter = usdc.balanceOf(testUser);
        console.log("USDC balance after withdrawal:", balanceAfter);
        console.log("USDC received:", balanceAfter - balanceBefore);
        
        // Verify received amount
        assertGe(balanceAfter - balanceBefore, withdrawAmount - 1); // Allow for small rounding errors
    }
}