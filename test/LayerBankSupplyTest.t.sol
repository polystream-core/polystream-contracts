// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Foundry
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICore {
    struct MarketInfo {
        bool isListed;
        uint256 supplyCap;
        uint256 borrowCap;
        uint256 collateralFactor;
    }

    function allMarkets() external view returns (address[] memory);
    function marketInfoOf(address gToken) external view returns (MarketInfo memory);
    function enterMarkets(address[] calldata gTokens) external;
    function supply(address gToken, uint256 underlyingAmount) external payable returns (uint256);
}


contract LayerBankSupplyTest is Test {
    // LayerBank contract address - replace with the actual contract address
    address constant CORE_ADDRESS = 0xEC53c830f4444a8A56455c6836b5D2aA794289Aa; // Example, replace with real address
    
    // Test token addresses - replace with actual USDC address on your target chain
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4; // Replace with actual USDC address
    address constant USDC_GTOKEN = 0x0D8F8e271DD3f2fC58e5716d3Ff7041dBe3F0688; // Replace with actual gToken for USDC
    
    // Test user
    address public testUser;
    
    // Contract instances
    ICore public core;
    IERC20 public usdc;
    
    function setUp() public {
        // Create a test user
        testUser = makeAddr("testUser");
        vm.deal(testUser, 10 ether);
        
        // Initialize contract instances
        core = ICore(CORE_ADDRESS);
        usdc = IERC20(USDC_ADDRESS);
        
        // Give the test user some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6); // Assuming USDC has 6 decimals
        
        // Log setup information
        console.log("Test setup complete");
        console.log("Core address:", CORE_ADDRESS);
        console.log("USDC balance of test user:", usdc.balanceOf(testUser));
    }
    
    // Test 1: Get market information
    function testMarketInfo() public view {
        console.log("===== Market Information =====");
        
        // Get list of all markets
        try core.allMarkets() returns (address[] memory markets) {
            console.log("Number of markets:", markets.length);
            
            // List all markets
            for (uint i = 0; i < markets.length; i++) {
                console.log("Market", i, ":", markets[i]);
                if (markets[i] == USDC_GTOKEN) {
                    console.log("USDC gToken found at index:", i);
                }
            }
        } catch Error(string memory reason) {
            console.log("Failed to get markets list with reason:", reason);
        } catch {
            console.log("Failed to get markets list with unknown reason");
        }
        
        // Get USDC market data
        try core.marketInfoOf(USDC_GTOKEN) returns (ICore.MarketInfo memory info) {
            console.log("===== USDC Market Data =====");
            console.log("USDC gToken:", USDC_GTOKEN);
            console.log(info.isListed ? "Listed" : "Not listed");
        } catch Error(string memory reason) {
            console.log("Failed to get market data with reason:", reason);
        } catch {
            console.log("Failed to get market data with unknown reason");
        }
    }
    
    // Test 2: Supply USDC
    function testLayerbankSupply() public {
        console.log("===== Testing USDC Supply =====");
        
        // Get initial balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Enter markets (if needed)
        address[] memory marketsToEnter = new address[](1);
        marketsToEnter[0] = USDC_GTOKEN;
        
        vm.startPrank(testUser);
        
        try core.enterMarkets(marketsToEnter) {
            console.log("Successfully entered USDC market");
        } catch Error(string memory reason) {
            console.log("Failed to enter market with reason:", reason);
        } catch {
            console.log("Failed to enter market with unknown reason");
        }
        
        // Approve and supply
        uint256 supplyAmount = 100 * 1e8; // 100 USDC
        
        usdc.approve(USDC_GTOKEN, supplyAmount);
        console.log("Approved USDC spending");
        
        // Try to supply
        try core.supply(USDC_GTOKEN, 100 * 1e6) returns (uint256 supplied) {
            console.log("Supply succeeded");
            console.log("Tokens received:", supplied);
        } catch Error(string memory reason) {
            console.log("Supply failed with reason:", reason);
        } catch {
            console.log("Supply failed with unknown reason");
        }
        
        vm.stopPrank();
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance:", finalBalance);
        console.log("USDC balance change:", initialBalance - finalBalance);
    }
}
