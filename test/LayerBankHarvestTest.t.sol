// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/adapters/LayerBankAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Simplified interfaces for testing - renamed to avoid conflicts
interface ILTokenTest {
    function getCash() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function totalReserve() external view returns (uint256);
    function reserveFactor() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function exchangeRate() external view returns (uint256);
    function accruedExchangeRate() external returns (uint256);
}

interface ILayerBankCoreTest {
    function supply(address gToken, uint256 underlyingAmount) external payable returns (uint256);
    function redeem(address gToken, uint256 amount) external returns (uint256);
}

contract LayerBankHarvestTest is Test {
    // Contract addresses on Scroll
    address constant LAYERBANK_CORE_ADDRESS = 0xEC53c830f4444a8A56455c6836b5D2aA794289Aa;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_GTOKEN_ADDRESS = 0x0D8F8e271DD3f2fC58e5716d3Ff7041dBe3F0688;
    
    // Number of seconds in one year
    uint256 constant SECONDS_PER_YEAR = 31536000;
    
    // Test users
    address public admin;
    address public testUser;
    
    // Core contracts
    ProtocolRegistry public registry;
    LayerBankAdapter public layerBankAdapter;
    
    // Token
    IERC20 public usdc;
    ILTokenTest public gUsdc;
    
    function setUp() public {
        console.log("Starting LayerBank harvest test setup...");
        
        // Create users
        admin = makeAddr("admin");
        testUser = makeAddr("testUser");
        vm.deal(admin, 10 ether);
        vm.deal(testUser, 10 ether);
        
        // Give users some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6);
        
        // Deploy registry as test contract
        registry = new ProtocolRegistry();
        console.log("Registry deployed at:", address(registry));
        
        // Register LayerBank protocol in registry
        registry.registerProtocol(Constants.LAYERBANK_PROTOCOL_ID, "LayerBank");
        console.log("LayerBank protocol registered in registry");
        
        // Deploy the LayerBank adapter as admin
        vm.startPrank(admin);
        layerBankAdapter = new LayerBankAdapter(LAYERBANK_CORE_ADDRESS);
        console.log("LayerBank Adapter deployed at:", address(layerBankAdapter));
        
        // Add USDC as supported asset in LayerBank adapter
        layerBankAdapter.addSupportedAsset(USDC_ADDRESS, USDC_GTOKEN_ADDRESS);
        console.log("USDC added as supported asset in LayerBank adapter");
        vm.stopPrank();
        
        // Register LayerBank adapter for USDC in registry
        registry.registerAdapter(Constants.LAYERBANK_PROTOCOL_ID, USDC_ADDRESS, address(layerBankAdapter));
        console.log("LayerBank adapter registered in registry for USDC");
        
        // Initialize token instances
        usdc = IERC20(USDC_ADDRESS);
        gUsdc = ILTokenTest(USDC_GTOKEN_ADDRESS);
        
        console.log("Test setup complete");
        console.log("USDC balance of test user:", usdc.balanceOf(testUser));
    }
    
    function testGetCurrentAPY() public {
        // Get the current APY from the adapter
        uint256 adapterAPY = layerBankAdapter.getAPY(USDC_ADDRESS);
        console.log("Current USDC APY from adapter (bps):", adapterAPY);
    }
    
    function testHarvestWithInterest() public {
        console.log("===== Testing Harvest With Interest =====");
        
        // 1. Supply tokens
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        uint256 received = layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        console.log("Supplied tokens, received gTokens:", received);
        vm.stopPrank();
        
        // 2. Get initial exchange rate and token balance
        uint256 initialExchangeRate = gUsdc.exchangeRate();
        uint256 initialGTokenBalance = gUsdc.balanceOf(address(layerBankAdapter));
        console.log("Initial exchange rate:", initialExchangeRate);
        console.log("Initial gToken balance:", initialGTokenBalance);
        
        // 3. Fast forward time
        vm.warp(block.timestamp + 90 days);
        console.log("Fast forwarded 90 days");
        
        // 4. Trigger interest accrual by calling accruedExchangeRate
        try gUsdc.accruedExchangeRate() returns (uint256 newRate) {
            console.log("New exchange rate after accrual:", newRate);
            console.log("Exchange rate difference:", newRate > initialExchangeRate ? newRate - initialExchangeRate : 0);
        } catch {
            console.log("Failed to accrue interest");
        }
        
        // 5. Try to harvest
        vm.startPrank(admin);
        try layerBankAdapter.harvest(USDC_ADDRESS) returns (uint256 amount) {
            console.log("Harvested amount:", amount);
        } catch Error(string memory reason) {
            console.log("Harvest failed:", reason);
        } catch {
            console.log("Harvest failed with unknown error");
        }
        vm.stopPrank();
        
        // 6. Check if timestamp was updated
        uint256 timeSinceLastHarvest = layerBankAdapter.getTimeSinceLastHarvest(USDC_ADDRESS);
        console.log("Time since harvest:", timeSinceLastHarvest);
        
        // 7. Fast forward more time
        vm.warp(block.timestamp + 30 days);
        timeSinceLastHarvest = layerBankAdapter.getTimeSinceLastHarvest(USDC_ADDRESS);
        console.log("Time after 30 more days:", timeSinceLastHarvest);
        assertEq(timeSinceLastHarvest, 30 days, "Should be 30 days");
    }
    
    function testHarvestWithLargerAmount() public {
        console.log("===== Testing Harvest With Larger Amount =====");
        
        // 1. Supply more tokens (1000 USDC)
        uint256 supplyAmount = 1000 * 1e6; // 1000 USDC
        vm.startPrank(testUser);
        usdc.approve(address(layerBankAdapter), supplyAmount);
        uint256 received = layerBankAdapter.supply(USDC_ADDRESS, supplyAmount);
        console.log("Supplied tokens, received gTokens:", received);
        vm.stopPrank();
        
        // 2. Fast forward more time (365 days)
        vm.warp(block.timestamp + 365 days);
        console.log("Fast forwarded 365 days");
        
        // 3. Trigger interest accrual by calling accruedExchangeRate
        try gUsdc.accruedExchangeRate() returns (uint256 newRate) {
            console.log("Exchange rate after 365 days:", newRate);
        } catch {
            console.log("Failed to accrue interest");
        }
        
        // 4. Try to harvest
        vm.startPrank(admin);
        try layerBankAdapter.harvest(USDC_ADDRESS) returns (uint256 amount) {
            console.log("Harvested amount after 365 days:", amount);
        } catch Error(string memory reason) {
            console.log("Harvest failed:", reason);
        } catch {
            console.log("Harvest failed with unknown error");
        }
        vm.stopPrank();
        
        // 5. Check if timestamp was updated
        uint256 timeSinceLastHarvest = layerBankAdapter.getTimeSinceLastHarvest(USDC_ADDRESS);
        console.log("Time since harvest:", timeSinceLastHarvest);
        
        // 6. Fast forward more time
        vm.warp(block.timestamp + 30 days);
        timeSinceLastHarvest = layerBankAdapter.getTimeSinceLastHarvest(USDC_ADDRESS);
        console.log("Time after 30 more days:", timeSinceLastHarvest);
        assertEq(timeSinceLastHarvest, 30 days, "Should be 30 days");
    }
}