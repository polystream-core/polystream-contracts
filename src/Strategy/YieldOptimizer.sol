// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/CombinedVault.sol";
import "../core/interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";
import "forge-std/console.sol"; // ✅ Import Foundry logging

contract YieldOptimizer {
    IRegistry public registry;
    CombinedVault public vault;
    IERC20 public immutable asset;

    event OptimizedYield(uint256 oldProtocolId, uint256 newProtocolId, uint256 amount);

    constructor(address _vault, address _asset) {
        require(_vault != address(0), "Invalid vault address");
        require(_asset != address(0), "Invalid asset address");

        vault = CombinedVault(_vault);
        registry = vault.registry();
        asset = IERC20(_asset);
    }

    /**
     * @notice Optimizes yield by switching to the highest APY protocol
     * @dev Called automatically via Chainlink Automation at the end of each epoch
     */
    function optimizeYield() external {
        console.log("Optimizing yield...");

        uint256 activeProtocolId = registry.getActiveProtocolId();
        address activeAdapter = address(registry.getAdapter(activeProtocolId, address(asset)));

        require(activeAdapter != address(0), "Active adapter not found");

        uint256 currentAPY = IProtocolAdapter(activeAdapter).getAPY(address(asset));
        console.log("Current active protocol:", activeProtocolId, "APY:", currentAPY);

        uint256[] memory allProtocols = registry.getAllProtocolIds();
        uint256 highestAPY = currentAPY;
        uint256 bestProtocolId = activeProtocolId;

        for (uint256 i = 0; i < allProtocols.length; i++) {
            uint256 protocolId = allProtocols[i];
            address protocolAdapter = address(registry.getAdapter(protocolId, address(asset)));

            if (protocolAdapter != address(0)) {
                uint256 apy = IProtocolAdapter(protocolAdapter).getAPY(address(asset));
                console.log("Checking protocol:", protocolId, "APY:", apy);

                if (apy > highestAPY) {
                    highestAPY = apy;
                    bestProtocolId = protocolId;
                }
            }
        }

        if (bestProtocolId != activeProtocolId) {
            uint256 vaultBalance = vault.getTotalSupply();
            console.log("Switching protocol! Vault Balance:", vaultBalance);

            // ✅ Withdraw all assets from the current protocol
            vault._withdrawAllFromProtocol(activeProtocolId);
            console.log("Withdrawn from old protocol:", activeProtocolId);

            // ✅ Update to the new protocol
            registry.setActiveProtocol(bestProtocolId);
            console.log("Updated active protocol to:", bestProtocolId);

            // ✅ Supply the entire vault balance to the new protocol
            vault.supplyToProtocol(bestProtocolId, vaultBalance);
            console.log("Supplied to new protocol via Vault:", bestProtocolId);

            emit OptimizedYield(activeProtocolId, bestProtocolId, vaultBalance);
        } else {
            console.log("No better APY found. No changes made.");
        }
    }
}
