// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import "../core/CombinedVault.sol";
// import "../core/interfaces/IRegistry.sol";
// import "../adapters/interfaces/IProtocolAdapter.sol";

// contract YieldOptimizer {
//     IRegistry public registry;
//     CombinedVault public vault;
//     IERC20 public immutable asset;

//     event OptimizedYield(uint256 oldProtocolId, uint256 newProtocolId, uint256 amount);

//     constructor(address _registry, address _vault, address _asset) {
//         require(_registry != address(0), "Invalid registry address");
//         require(_vault != address(0), "Invalid vault address");
//         require(_asset != address(0), "Invalid asset address");

//         vault = CombinedVault(_vault);
//         registry = vault.registry();
//         asset = IERC20(_asset);
//     }

//     /**
//      * @notice Optimizes yield by switching to the highest APY protocol
//      * @dev Called automatically via Chainlink Automation at the end of each epoch
//      */
//     function optimizeYield() external {
//         uint256 activeProtocolId = registry.getActiveProtocolId();
//         uint256 currentAPY = registry.getAPY(activeProtocolId);

//         uint256[] memory allProtocols = registry.getAllProtocolIds();
//         uint256 highestAPY = currentAPY;
//         uint256 bestProtocolId = activeProtocolId;

//         // 🔍 Find the highest APY protocol
//         for (uint256 i = 0; i < allProtocols.length; i++) {
//             uint256 protocolId = allProtocols[i];
//             uint256 apy = registry.getAPY(protocolId);

//             if (apy > highestAPY) {
//                 highestAPY = apy;
//                 bestProtocolId = protocolId;
//             }
//         }

//         // 🚀 Migrate funds if a higher APY protocol is found
//         if (bestProtocolId != activeProtocolId) {
//             uint256 vaultBalance = vault.getTotalSupply();

//             // 🏦 Withdraw from the current protocol
//             address currentAdapter = registry.getAdapter(activeProtocolId, address(asset));
//             vault._withdrawFromProtocols(vaultBalance, address(vault)); // Bring funds back to Vault

//             // 🔄 Update to the new protocol
//             registry.setActiveProtocol(bestProtocolId);

//             // 💰 Deposit into the new protocol
//             address newAdapter = registry.getAdapter(bestProtocolId, address(asset));
//             IProtocolAdapter(newAdapter).supply(address(asset), vaultBalance);

//             emit OptimizedYield(activeProtocolId, bestProtocolId, vaultBalance);
//         }
//     }
// }
