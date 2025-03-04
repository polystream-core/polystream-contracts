// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/YieldVault.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldVaultTest is Test {
    // Contract addresses on Scroll
    address constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_ATOKEN_ADDRESS = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    
    // Test users
    address public admin;
    address public testUser;
    
    // Core contracts
    ProtocolRegistry public registry;
    AaveAdapter public aaveAdapter;
    YieldVault public vault;
    
    // Token
    IERC20 public usdc;
    
    function setUp() public {
        console.log("Starting YieldVault test setup...");
        
        // Create admin and test user
        admin = makeAddr("admin");
        testUser = makeAddr("testUser");
        vm.deal(admin, 10 ether);
        vm.deal(testUser, 10 ether);
        
        // Give test user some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6);
        
        vm.startPrank(admin);
        
        // Step 1: Deploy Registry
        registry = new ProtocolRegistry();
        console.log("Registry deployed at:", address(registry));
        
        // Step 2: Deploy Aave adapter
        aaveAdapter = new AaveAdapter(AAVE_POOL_ADDRESS);
        console.log("Aave Adapter deployed at:", address(aaveAdapter));
        
        // Step 3: Register Aave protocol in registry
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Aave V3");
        console.log("Aave protocol registered in registry");
        
        // Step 4: Add USDC as supported asset in Aave adapter
        aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS);
        console.log("USDC added as supported asset in Aave adapter");
        
        // Step 5: Register Aave adapter for USDC in registry
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS, address(aaveAdapter));
        console.log("Aave adapter registered in registry for USDC");
        
        // Step 6: Deploy YieldVault
        vault = new YieldVault(
            address(registry),
            USDC_ADDRESS,
            "Yield Vault USDC",
            "yvUSDC"
        );
        console.log("YieldVault deployed at:", address(vault));
        
        // Step 7: Configure vault to use Aave with 100% allocation
        vault.addProtocol(Constants.AAVE_PROTOCOL_ID, 10000); // 100% allocation
        console.log("Vault configured with 100% allocation to Aave");
        
        // Initialize token instance
        usdc = IERC20(USDC_ADDRESS);
        
        vm.stopPrank();
        
        console.log("Test setup complete");
        console.log("USDC balance of test user:", usdc.balanceOf(testUser));
    }
    
    function testVaultDepositAndWithdraw() public {
        console.log("===== Testing Vault Deposit and Withdraw =====");
        
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        
        // Get initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance of test user:", initialUsdcBalance);
        
        // Approve vault to spend USDC
        usdc.approve(address(vault), depositAmount);
        console.log("Approved vault to spend USDC");
        
        // Deposit into vault
        uint256 shares = vault.deposit(depositAmount);
        console.log("Deposited USDC into vault:", depositAmount);
        console.log("Received shares:", shares);
        
        // Check share balance
        uint256 shareBalance = vault.balanceOf(testUser);
        console.log("Share balance of test user:", shareBalance);
        
        // Check total assets in vault
        uint256 totalAssets = vault.totalAssets();
        console.log("Total assets in vault:", totalAssets);
        
        // Check price per share
        uint256 pricePerShare = vault.getPricePerShare();
        console.log("Price per share:", pricePerShare);
        
        // Check Aave adapter balance through registry
        IProtocolAdapter adapter = registry.getAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS);
        uint256 aaveBalance = adapter.getBalance(USDC_ADDRESS);
        console.log("USDC balance in Aave adapter:", aaveBalance);
        
        // Now withdraw 50% of shares
        uint256 sharesToWithdraw = shareBalance / 2;
        
        // Withdraw from vault
        uint256 withdrawnAmount = vault.withdraw(sharesToWithdraw);
        console.log("Withdrew USDC from vault:", withdrawnAmount);
        console.log("Burnt shares:", sharesToWithdraw);
        
        // Check final balances
        uint256 finalUsdcBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance of test user:", finalUsdcBalance);
        console.log("USDC received from withdrawal:", finalUsdcBalance - (initialUsdcBalance - depositAmount));
        
        // Check final share balance
        uint256 finalShareBalance = vault.balanceOf(testUser);
        console.log("Final share balance of test user:", finalShareBalance);
        
        // Check final total assets in vault
        uint256 finalTotalAssets = vault.totalAssets();
        console.log("Final total assets in vault:", finalTotalAssets);
        
        // Verify shares were burnt correctly
        assertEq(finalShareBalance, shareBalance - sharesToWithdraw);
        
        // Verify we received assets back
        assert(withdrawnAmount > 0);
        assert(finalUsdcBalance > initialUsdcBalance - depositAmount);
        
        // Verify total assets decreased
        assert(finalTotalAssets < totalAssets);
        
        vm.stopPrank();
    }
    
    function testGetAverageAPY() public view {
        console.log("===== Testing Get Average APY =====");
        
        uint256 apy = vault.getAverageAPY();
        console.log("Average APY:", apy, "basis points");
        
        // Verify APY is returned
        assert(apy > 0);
    }
    
    function testRebalance() public {
        console.log("===== Testing Rebalance =====");
        
        // First deposit some funds
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Get initial adapter balance
        IProtocolAdapter adapter = registry.getAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS);
        uint256 initialAdapterBalance = adapter.getBalance(USDC_ADDRESS);
        console.log("Initial USDC balance in Aave adapter:", initialAdapterBalance);
        
        // Switch to admin to rebalance
        vm.startPrank(admin);
        
        // Rebalance (should be a no-op since we already have 100% in Aave)
        vault.rebalance();
        console.log("Rebalance executed");
        
        // Get final adapter balance
        uint256 finalAdapterBalance = adapter.getBalance(USDC_ADDRESS);
        console.log("Final USDC balance in Aave adapter:", finalAdapterBalance);
        
        // Since we're still at 100% Aave, balances should be very close
        uint256 diff = finalAdapterBalance > initialAdapterBalance ? 
            finalAdapterBalance - initialAdapterBalance : 
            initialAdapterBalance - finalAdapterBalance;
            
        console.log("Difference after rebalance:", diff);
        
        // The difference should be very small (just gas costs and rounding)
        assert(diff < 1000); // Less than 0.001 USDC difference
        
        vm.stopPrank();
    }
}