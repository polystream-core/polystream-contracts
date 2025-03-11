// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@aave/contracts/interfaces/IPool.sol";
import "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import "@layerbank-contracts/interfaces/ILToken.sol";
import "@layerbank-contracts/interfaces/IRateModel.sol";
import "forge-std/console.sol";

contract YieldOptimizer {
    // Addresses for Lending Pools
    address public constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address public constant AAVE_ASSET = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address public constant LAYERBANK_ILTOKEN = 0x0D8F8e271DD3f2fC58e5716d3Ff7041dBe3F0688;
    address public constant LAYERBANK_RATEMODEL = 0x09aD162E117eFCC5cBD5Fd4865818f2ABA8e80D7;

    // Lending Pool Interfaces
    IPool public aavePool;
    ILToken public layerBankToken;
    IRateModel public layerBankRateModel;

    uint256 public constant ONE_RAY = 1e27;
    uint256 public constant SECONDS_PER_YEAR = 31536000;

    // Current Pool State
    address public currentLendingPool;
    uint256 public lastCheckedAPY;

    // APY values for testing
    uint256 public aaveAPY;
    uint256 public layerBankAPY;

    event PoolSwitched(address indexed newPool, uint256 newAPY);

    constructor() {
        aavePool = IPool(AAVE_POOL_ADDRESS);
        layerBankToken = ILToken(LAYERBANK_ILTOKEN);
        layerBankRateModel = IRateModel(LAYERBANK_RATEMODEL);

        // Set the initial pool based on the highest APY
        setFirstPool();
    }

    /// @notice Fetches APY from Aave lending pool
    function getAaveAPY() public view returns (uint256) {
        return aaveAPY;
    }

    /// @notice Fetches APY from LayerBank lending pool
    function getLayerBankAPY() public view returns (uint256) {
        return layerBankAPY;
    }

    /// @notice Sets the initial pool based on the highest APY
    function setFirstPool() internal {
        uint256 aaveAPYValue = getAaveAPY();
        uint256 layerBankAPYValue = getLayerBankAPY();

        if (layerBankAPYValue > aaveAPYValue) {
            currentLendingPool = LAYERBANK_ILTOKEN;
            lastCheckedAPY = layerBankAPYValue;
        } else {
            currentLendingPool = AAVE_POOL_ADDRESS;
            lastCheckedAPY = aaveAPYValue;
        }

        emit PoolSwitched(currentLendingPool, lastCheckedAPY);
    }

    /// @notice Combined function for Chainlink Automation
    /// This function checks APYs and switches pools if necessary
    function optimizeYield() external {
        uint256 aaveAPYValue = getAaveAPY();
        uint256 layerBankAPYValue = getLayerBankAPY();
        
        console.log("Current Pool:", currentLendingPool);
        console.log("Aave APY:", aaveAPYValue);
        console.log("LayerBank APY:", layerBankAPYValue);

        if (currentLendingPool == AAVE_POOL_ADDRESS && layerBankAPYValue > aaveAPYValue) {
            switchLendingPool(LAYERBANK_ILTOKEN, layerBankAPYValue);
        } else if (currentLendingPool == LAYERBANK_ILTOKEN && aaveAPYValue > layerBankAPYValue) {
            switchLendingPool(AAVE_POOL_ADDRESS, aaveAPYValue);
        } else {
            console.log("No switch needed, staying in current pool.");
        }
    }

    /// @notice Mock function to simulate pool switching (Replace with actual implementation)
    function switchLendingPool(address newPool, uint256 newAPY) internal {
        require(newPool != currentLendingPool, "Already in best pool");
        console.log("Switching from", currentLendingPool, "to", newPool);

        currentLendingPool = newPool;
        lastCheckedAPY = newAPY;
        
        emit PoolSwitched(newPool, newAPY);
    }

    /// @notice Sets the Aave APY for testing purposes
    function setAaveAPY(uint256 _aaveAPY) external {
        aaveAPY = _aaveAPY;
    }

    /// @notice Sets the LayerBank APY for testing purposes
    function setLayerBankAPY(uint256 _layerBankAPY) external {
        layerBankAPY = _layerBankAPY;
    }
}