// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";

contract APYCalculatorTest is Test {
    uint256 constant ONE_RAY = 1e27;

    IPool public pool;
    
    // USDC on Scroll
    address public asset = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    
    function setUp() public {
        // Aave pool on Scroll.
        pool = IPool(0x11fCfe756c05AD438e312a7fd934381537D3cFfe);
    }
    
    function testCalculateAPY() public {
        // Fetch reserve data for the asset from Aave.
        DataTypes.ReserveDataLegacy memory reserveData = pool.getReserveData(asset);
        uint256 liquidityRateRay = reserveData.currentLiquidityRate;
        
        // Convert liquidity rate in ray to basis points.
        uint256 apyBps = (liquidityRateRay * 10000) / ONE_RAY;
        
        // Log the raw basis points value.
        emit log_uint(apyBps);
        
        // When reading the log, interpret 5 as 0.05% and 252 as 2.52%.
    }
}
