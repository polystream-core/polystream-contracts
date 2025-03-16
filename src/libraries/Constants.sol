// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Constants
 * @notice Library for shared constants across the protocol
 */
library Constants {
    // Protocol IDs
    uint256 public constant AAVE_PROTOCOL_ID = 1;
    uint256 public constant LAYERBANK_PROTOCOL_ID = 2;
    uint256 public constant SYNCSWAP_PROTOCOL_ID = 3;
    
    // Basis points for percentages (100% = 10000)
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;
    
    // Default harvest fee (10%)
    uint256 public constant DEFAULT_HARVEST_FEE = 1000;
    
    // Default minimum deposit amount (1 USDC)
    uint256 public constant DEFAULT_MIN_DEPOSIT = 1e6;
    
    // Default token name and symbol
    string public constant DEFAULT_TOKEN_NAME = "Polystream USDC";
    string public constant DEFAULT_TOKEN_SYMBOL = "pyUSDC";
}