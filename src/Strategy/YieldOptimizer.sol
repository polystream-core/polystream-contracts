// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/CombinedVault.sol";
import "../core/interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";

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
        uint256 activeProtocolId = registry.getActiveProtocolId();
        address activeAdapter = address(registry.getAdapter(activeProtocolId, address(asset)));

        require(activeAdapter != address(0), "Active adapter not found");

        uint256 currentAPY = IProtocolAdapter(activeAdapter).getAPY(address(asset));

        uint256[] memory allProtocols = registry.getAllProtocolIds();
        uint256 highestAPY = currentAPY;
        uint256 bestProtocolId = activeProtocolId;

        for (uint256 i = 0; i < allProtocols.length; i++) {
            uint256 protocolId = allProtocols[i];
            address protocolAdapter = address(registry.getAdapter(protocolId, address(asset)));

            if (protocolAdapter != address(0)) {
                uint256 apy = IProtocolAdapter(protocolAdapter).getAPY(address(asset));

                if (apy > highestAPY) {
                    highestAPY = apy;
                    bestProtocolId = protocolId;
                }
            }
        }

        if (bestProtocolId != activeProtocolId) {
            uint256 vaultBalance = vault.getTotalSupply();

            // ✅ Withdraw all assets from the current protocol
            vault._withdrawAllFromProtocol(activeProtocolId);

            // ✅ Update to the new protocol
            registry.setActiveProtocol(bestProtocolId);

            // ✅ Supply the entire vault balance to the new protocol
            vault.supplyToProtocol(bestProtocolId, vaultBalance);

            emit OptimizedYield(activeProtocolId, bestProtocolId, vaultBalance);
        }
    }
}
