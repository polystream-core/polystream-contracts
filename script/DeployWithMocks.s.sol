// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/tokens/mocks/MockUSDC.sol";
import "../src/adapters/mocks/MockAaveAdapter.sol";
import "../src/adapters/mocks/MockLayerBankAdapter.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/core/CombinedVault.sol";
import "../src/libraries/Constants.sol";

/**
 * @title DeployWithMocks
 * @notice Script to deploy the yield optimizer with mock components
 */
contract DeployWithMocks is Script {
    function run() external {
        // Get the private key from env or use a default testing key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with address:", deployer);
        
        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy mock USDC
        MockUSDC mockUSDC = new MockUSDC(deployer);
        console.log("MockUSDC deployed at:", address(mockUSDC));
        
        // Step 2: Deploy protocol registry
        ProtocolRegistry registry = new ProtocolRegistry();
        console.log("ProtocolRegistry deployed at:", address(registry));
        
        // Step 3: Deploy mock protocol adapters
        MockAaveAdapter mockAaveAdapter = new MockAaveAdapter(address(mockUSDC));
        MockLayerBankAdapter mockLayerBankAdapter = new MockLayerBankAdapter(address(mockUSDC));
        console.log("MockAaveAdapter deployed at:", address(mockAaveAdapter));
        console.log("MockLayerBankAdapter deployed at:", address(mockLayerBankAdapter));
        
        // Add adapters as minters for MockUSDC
        mockUSDC.addMinter(address(mockAaveAdapter));
        mockUSDC.addMinter(address(mockLayerBankAdapter));
        console.log("Added adapters as minters for MockUSDC");
        
        // Step 4: Configure adapters
        mockAaveAdapter.addSupportedAsset(address(mockUSDC), address(mockUSDC));
        mockLayerBankAdapter.addSupportedAsset(address(mockUSDC), address(mockUSDC));
        console.log("Supported assets added to adapters");
        
        // Set APYs (configure based on your testing needs)
        mockAaveAdapter.setAPY(address(mockUSDC), 300); // 3%
        mockLayerBankAdapter.setAPY(address(mockUSDC), 500); // 5%
        console.log("APYs set for adapters");
        
        // Step 5: Register protocols in registry
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Mock Aave V3");
        registry.registerProtocol(Constants.LAYERBANK_PROTOCOL_ID, "Mock LayerBank");
        console.log("Protocols registered in registry");
        
        // Step 6: Register adapters in registry
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, address(mockUSDC), address(mockAaveAdapter));
        registry.registerAdapter(Constants.LAYERBANK_PROTOCOL_ID, address(mockUSDC), address(mockLayerBankAdapter));
        console.log("Adapters registered in registry");
        
        // Set the active protocol (Aave as default)
        registry.setActiveProtocol(Constants.AAVE_PROTOCOL_ID);
        console.log("Set Aave as active protocol");
        
        // Step 7: Deploy Combined Vault
        CombinedVault vault = new CombinedVault(address(registry), address(mockUSDC));
        console.log("CombinedVault deployed at:", address(vault));
        
        // Step 8: Add protocols to vault
        vault.addProtocol(Constants.AAVE_PROTOCOL_ID);
        console.log("Added Aave protocol to vault");
        
        // Step 9: Transfer ownership of registry to deployer wallet
        // This allows for later protocol switching
        registry.transferOwnership(deployer);
        console.log("Registry ownership remains with deployer");
        
        // Step 10: Mint some test tokens to deployer
        mockUSDC.mint(deployer, 1000000 * 1e6); // 1,000,000 USDC
        console.log("1,000,000 USDC minted to deployer");
        
        // Log important addresses for reference
        console.log("\n=== Deployment Summary ===");
        console.log("MockUSDC:", address(mockUSDC));
        console.log("ProtocolRegistry:", address(registry));
        console.log("MockAaveAdapter:", address(mockAaveAdapter));
        console.log("MockLayerBankAdapter:", address(mockLayerBankAdapter));
        console.log("CombinedVault:", address(vault));
        
        vm.stopBroadcast();
    }
}