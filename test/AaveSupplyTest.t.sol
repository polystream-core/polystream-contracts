// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Simplified interfaces to avoid stack too deep errors
interface IAavePool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
    
    function getReservesList() external view returns (address[] memory);
    
    // Simplified to reduce stack usage
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 variableBorrowIndex,
        uint16 id,
        address aTokenAddress
    );
}

interface IAaveL2Pool {
    function supply(bytes32 args) external;
}

interface IL2Encoder {
    function encodeSupplyParams(
        address asset,
        uint256 amount,
        uint16 referralCode
    ) external view returns (bytes32);
}

contract AaveScrollUpdatedTest is Test {
    // Updated Aave contract addresses for Scroll mainnet
    address constant POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe; // Active pool from Scroll
    address constant L2_ENCODER_ADDRESS = 0x8714E5ED2d8edD4E88eFf66637C3FE8eCf2B8C40;
    
    // Test token addresses
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    
    // Test user
    address public testUser;
    
    // Contract instances
    IAavePool public pool;
    IAaveL2Pool public l2Pool;
    IL2Encoder public l2Encoder;
    IERC20 public usdc;
    
    function setUp() public {
        // Create a test user
        testUser = makeAddr("testUser");
        vm.deal(testUser, 10 ether);
        
        // Initialize contract instances
        pool = IAavePool(POOL_ADDRESS);
        l2Pool = IAaveL2Pool(POOL_ADDRESS);
        l2Encoder = IL2Encoder(L2_ENCODER_ADDRESS);
        usdc = IERC20(USDC_ADDRESS);
        
        // Give the test user some USDC
        deal(USDC_ADDRESS, testUser, 1000 * 1e6);
        
        // Log setup information
        console.log("Test setup complete");
        console.log("Pool address:", POOL_ADDRESS);
        console.log("USDC balance of test user:", usdc.balanceOf(testUser));
    }
    
    
    // Test 1: Try standard supply
    function testStandardSupply() public {
        console.log("===== Testing Standard Supply =====");
        
        // Get initial balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Approve and supply
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(testUser);
        usdc.approve(POOL_ADDRESS, supplyAmount);
        console.log("Approved USDC spending");
        
        // Try to supply using standard method
        try pool.supply(USDC_ADDRESS, supplyAmount, testUser, 0) {
            console.log("Standard supply succeeded");
        } catch Error(string memory reason) {
            console.log("Standard supply failed with reason:", reason);
        } catch {
            console.log("Standard supply failed with unknown reason");
        }
        
        vm.stopPrank();
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance:", finalBalance);
        console.log("USDC balance change:", initialBalance - finalBalance);
    }
    
    // Test 2: Try L2 optimized supply
    function testL2Supply() public {
        console.log("===== Testing L2 Optimized Supply =====");
        
        // Get initial balance
        uint256 initialBalance = usdc.balanceOf(testUser);
        console.log("Initial USDC balance:", initialBalance);
        
        // Encode supply params - attempt with different asset IDs
        uint256 supplyAmount = 100 * 1e6; // 100 USDC
        
        try l2Encoder.encodeSupplyParams(
            USDC_ADDRESS,
            supplyAmount,
            0 // referral code
        ) returns (bytes32 supplyArgs) {
            console.log("Encoded supply args (uint):", uint256(supplyArgs));
            
            // Decode the args for inspection
            uint16 assetId = uint16(uint256(supplyArgs));
            uint128 amount = uint128(uint256(supplyArgs) >> 16);
            uint16 refCode = uint16(uint256(supplyArgs) >> 144);
            
            console.log("Decoded from args - Asset ID:", assetId);
            console.log("Decoded from args - Amount:", amount);
            console.log("Decoded from args - Referral Code:", refCode);
            
            // Approve and try to supply
            vm.startPrank(testUser);
            usdc.approve(POOL_ADDRESS, supplyAmount);
            console.log("Approved USDC spending for L2 Pool");
            
            // Try to supply using L2 optimized method
            try l2Pool.supply(supplyArgs) {
                console.log("L2 supply succeeded");
            } catch Error(string memory reason) {
                console.log("L2 supply failed with reason:", reason);
            } catch {
                console.log("L2 supply failed with unknown reason");
            }
            
            vm.stopPrank();
        } catch Error(string memory reason) {
            console.log("Failed to encode supply params with reason:", reason);
        } catch {
            console.log("Failed to encode supply params with unknown reason");
            
            // Try direct encoding of supply args for manual testing of different asset IDs
            // Based on the documentation: bit 0-15: assetId, bit 16-143: amount, bit 144-159: referralCode
            
            // Try with asset ID 1
            bytes32 manualArgs = bytes32((uint256(0) << 144) | (uint256(supplyAmount) << 16) | uint256(1));
            console.log("Manual encoded args (ID 1):", uint256(manualArgs));
            
            vm.startPrank(testUser);
            usdc.approve(POOL_ADDRESS, supplyAmount);
            
            try l2Pool.supply(manualArgs) {
                console.log("Manual L2 supply succeeded with asset ID 1");
            } catch {
                console.log("Manual L2 supply failed with asset ID 1");
                
                // Try with asset ID 2
                bytes32 manualArgs2 = bytes32((uint256(0) << 144) | (uint256(supplyAmount) << 16) | uint256(2));
                
                try l2Pool.supply(manualArgs2) {
                    console.log("Manual L2 supply succeeded with asset ID 2");
                } catch {
                    console.log("Manual L2 supply failed with asset ID 2");
                }
            }
            
            vm.stopPrank();
        }
        
        // Check final balance
        uint256 finalBalance = usdc.balanceOf(testUser);
        console.log("Final USDC balance:", finalBalance);
        console.log("USDC balance change:", initialBalance - finalBalance);
    }

}