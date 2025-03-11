// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Strategy/YieldOptimizer.sol";

contract YieldOptimizerTest is Test {
    YieldOptimizer optimizer;

    function setUp() public {
        optimizer = new YieldOptimizer();
        // Set up initial state, mock data, and any necessary contracts
    }

    function testInitialPoolSetup() public {
        optimizer = new YieldOptimizer();
        address initialPool = optimizer.currentLendingPool();
    }

    function testOptimizeYieldSwitchesPool() public {
        // Arrange: Set the APY values directly
        optimizer.setAaveAPY(5 * 1e27); // Example low yield rate in Ray
        optimizer.setLayerBankAPY(10 * 1e27); // Example high yield rate in Ray

        // Act: Call the optimizeYield function
        optimizer.optimizeYield();

        // Assert: Check if the pool was switched
        address newPool = optimizer.currentLendingPool();
        assert(newPool == optimizer.LAYERBANK_ILTOKEN());

        // Now set the APY values to switch back to Aave
        optimizer.setAaveAPY(10 * 1e27); // Example high yield rate in Ray
        optimizer.setLayerBankAPY(5 * 1e27); // Example low yield rate in Ray

        // Act: Call the optimizeYield function again
        optimizer.optimizeYield();

        // Assert: Check if the pool was switched back to Aave
        newPool = optimizer.currentLendingPool();
        assert(newPool == optimizer.AAVE_POOL_ADDRESS());
    }
}