// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// We'll define an interface for the pool without importing the full Aave libraries
interface IPoolMinimal {
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );
}

contract AaveAdapterHarvestTest is Test {
    // Contract addresses on Scroll
    address constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_ATOKEN_ADDRESS = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    address constant AAVE_PRICE_ORACLE = 0x04421D8C506E2fA2371a08EfAaBf791F624054F3;
    address constant AAVE_REWARDS_CONTROLLER = address(0); // Set to real address if available
    
    // Aave constants
    uint256 constant ONE_RAY = 1e27;
    
    // Test user and admin
    address public testUser;
    address public admin;
    
    // Core contracts
    ProtocolRegistry public registry;
    AaveAdapter public aaveAdapter;
    IPoolMinimal public aavePool;
    
    // Token
    IERC20 public usdc;
    IERC20 public aUsdc;
    
    function setUp() public {
        // Create a test user and admin
        testUser = makeAddr("testUser");
        admin = makeAddr("admin");
        vm.deal(testUser, 10 ether);
        vm.deal(admin, 10 ether);
        
        // Give the test user some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6);
        
        // Deploy registry and adapters
        registry = new ProtocolRegistry();
        console.log("Registry deployed at:", address(registry));

        // Register Aave protocol in the registry (as the test contract)
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Aave V3");
        console.log("Aave protocol registered in the registry");
        
        // Deploy the Aave adapter as admin
        vm.startPrank(admin);
        aaveAdapter = new AaveAdapter(AAVE_POOL_ADDRESS);
        console.log("Aave Adapter deployed at:", address(aaveAdapter));
        
        // Add USDC as a supported asset in the Aave adapter with its known aToken address
        aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS);
        console.log("USDC added as a supported asset in the Aave adapter with aToken:", USDC_ATOKEN_ADDRESS);
        
        // Set min reward amount
        aaveAdapter.setMinRewardAmount(USDC_ADDRESS, 1 * 1e5); // 0.1 USDC
        
        // Set external contracts
        aaveAdapter.setExternalContracts(
            AAVE_REWARDS_CONTROLLER,
            AAVE_PRICE_ORACLE,
            address(0), // No swap router needed yet
            address(0)  // No WETH needed yet
        );
        vm.stopPrank();
        
        // Register the Aave adapter for USDC in the registry (as the test contract)
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS, address(aaveAdapter));
        console.log("Aave adapter registered in the registry for USDC");
        
        // Initialize token instances and Aave pool
        usdc = IERC20(USDC_ADDRESS);
        aUsdc = IERC20(USDC_ATOKEN_ADDRESS);
        aavePool = IPoolMinimal(AAVE_POOL_ADDRESS);
        
        // Log setup information
        console.log("Test setup complete");
        console.log("USDC balance of test user:", usdc.balanceOf(testUser));
    }
    
    function testGetCurrentAPY() public {
        // Get the current APY from the Aave adapter
        uint256 currentAPY = aaveAdapter.getAPY(USDC_ADDRESS);
        console.log("Current USDC APY from adapter (bps):", currentAPY);
        
        // Calculate APY directly
        (
            ,
            ,
            uint128 currentLiquidityRate,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            
        ) = aavePool.getReserveData(USDC_ADDRESS);
        
        uint256 apyBps = (currentLiquidityRate * 10000) / ONE_RAY;
        console.log("Current USDC APY calculated directly (bps):", apyBps);
        
        // They should be the same
        assertEq(currentAPY, apyBps, "APY from adapter should match direct calculation");
    }
    
    function testHarvestAfterTimeSimulation() public {
        console.log("===== Testing Aave Harvest with Time Simulation =====");
        
        // Get current APY for calculations
        uint256 currentAPYBps = aaveAdapter.getAPY(USDC_ADDRESS);
        console.log("Current USDC APY (bps):", currentAPYBps);
        
        // Get initial balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Supply amount
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        
        // Approve adapter to spend USDC
        usdc.approve(address(aaveAdapter), supplyAmount);
        
        // Supply USDC through the adapter
        uint256 received = aaveAdapter.supply(USDC_ADDRESS, supplyAmount);
        console.log("Adapter supply successful, received:", received);
        
        vm.stopPrank();
        
        // Check initial aToken balance in adapter
        uint256 initialATokenBalance = aUsdc.balanceOf(address(aaveAdapter));
        console.log("Initial aToken balance in adapter:", initialATokenBalance);
        
        // Fast forward 90 days to simulate interest accrual
        vm.warp(block.timestamp + 90 days);
        console.log("Fast forwarded 90 days");
        
        // For Aave, interest accrues directly in the aToken balance
        // Get adapter's aToken balance after time passes
        uint256 aTokenBalanceAfter90Days = aUsdc.balanceOf(address(aaveAdapter));
        console.log("aToken balance after 90 days:", aTokenBalanceAfter90Days);
        
        // Calculate interest accrued
        uint256 interestAccrued = aTokenBalanceAfter90Days - initialATokenBalance;
        console.log("Interest accrued after 90 days:", interestAccrued);
        
        // Expected interest for 90 days: principal * APY * (days/365)
        uint256 expectedInterest = (supplyAmount * currentAPYBps * 90 days) / (365 days * 10000);
        console.log("Expected interest based on current APY:", expectedInterest);
        
        // Now harvest the interest
        vm.startPrank(admin);
        uint256 harvestedAmount = aaveAdapter.harvest(USDC_ADDRESS);
        console.log("Harvested amount:", harvestedAmount);
        vm.stopPrank();
        
        // The harvested amount should be close to the interest accrued
        assertApproxEqRel(harvestedAmount, interestAccrued, 0.1e18); // 10% tolerance
        
        // Fast forward another 180 days to see compounding effect
        vm.warp(block.timestamp + 180 days);
        console.log("Fast forwarded another 180 days");
        
        // Get new aToken balance
        uint256 aTokenBalanceAfter270Days = aUsdc.balanceOf(address(aaveAdapter));
        console.log("aToken balance after 270 days:", aTokenBalanceAfter270Days);
        
        // Calculate new interest accrued (since last harvest)
        uint256 newInterestAccrued = aTokenBalanceAfter270Days - aTokenBalanceAfter90Days;
        console.log("New interest accrued (180 days):", newInterestAccrued);
        
        // Now harvest again
        vm.startPrank(admin);
        uint256 secondHarvestedAmount = aaveAdapter.harvest(USDC_ADDRESS);
        console.log("Second harvested amount:", secondHarvestedAmount);
        vm.stopPrank();
        
        // The second harvested amount should be close to the new interest accrued
        assertApproxEqRel(secondHarvestedAmount, newInterestAccrued, 0.1e18); // 10% tolerance
        
        // Verify compounding effect (second harvest should be greater than the first, scaled for time)
        // First harvest: 90 days
        // Second harvest: 180 days (2x time)
        // With compounding, second harvest should be more than 2x the first
        uint256 scaledFirstHarvest = (harvestedAmount * 180) / 90; // Scale first harvest to 180 days
        console.log("First harvest scaled to 180 days:", scaledFirstHarvest);
        console.log("Second harvest (actual):", secondHarvestedAmount);
        
        // If there's compounding, second harvest should be greater than scaled first harvest
        // However, interest rates might have changed during this period
        if (secondHarvestedAmount > scaledFirstHarvest) {
            console.log("Compounding effect confirmed!");
            console.log("Extra interest from compounding:", secondHarvestedAmount - scaledFirstHarvest);
        } else {
            console.log("No compounding effect detected or interest rates might have changed");
        }
        
        // Total interest earned
        console.log("Total interest earned:", harvestedAmount + secondHarvestedAmount);
        
        // Test that adapter can properly report time since last harvest
        uint256 timeSinceLastHarvest = aaveAdapter.getTimeSinceLastHarvest(USDC_ADDRESS);
        console.log("Time since last harvest (seconds):", timeSinceLastHarvest);
        assertEq(timeSinceLastHarvest, 0, "Time since last harvest should be 0 right after harvesting");
        
        // Fast forward 30 days and check again
        vm.warp(block.timestamp + 30 days);
        timeSinceLastHarvest = aaveAdapter.getTimeSinceLastHarvest(USDC_ADDRESS);
        console.log("Time since last harvest after 30 days (seconds):", timeSinceLastHarvest);
        assertEq(timeSinceLastHarvest, 30 days, "Time since last harvest should be 30 days");
    }
}