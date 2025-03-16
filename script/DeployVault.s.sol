// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/CombinedVault.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/libraries/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployVault
 * @notice Script to deploy CombinedVault and its dependencies on Scroll
 */
contract DeployVault is Script {
    // Contract addresses on Scroll
    address constant AAVE_POOL_ADDRESS = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe;
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant USDC_ATOKEN_ADDRESS = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    
    // Deployed contract addresses
    ProtocolRegistry public registry;
    AaveAdapter public aaveAdapter;
    CombinedVault public vault;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy registry
        registry = new ProtocolRegistry();
        console.log("ProtocolRegistry deployed at:", address(registry));
        
        // Deploy Aave adapter
        aaveAdapter = new AaveAdapter(AAVE_POOL_ADDRESS);
        console.log("AaveAdapter deployed at:", address(aaveAdapter));
        
        // Register protocol in registry
        registry.registerProtocol(Constants.AAVE_PROTOCOL_ID, "Aave V3");
        console.log("Registered Aave protocol with ID:", Constants.AAVE_PROTOCOL_ID);
        
        // Add USDC as supported asset in Aave adapter
        aaveAdapter.addSupportedAsset(USDC_ADDRESS, USDC_ATOKEN_ADDRESS);
        console.log("Added USDC as supported asset in AaveAdapter");
        
        // Register adapter in registry
        registry.registerAdapter(Constants.AAVE_PROTOCOL_ID, USDC_ADDRESS, address(aaveAdapter));
        console.log("Registered AaveAdapter for USDC in registry");
        
        // Deploy vault
        vault = new CombinedVault(
            address(registry),
            USDC_ADDRESS
        );
        console.log("CombinedVault deployed at:", address(vault));
        
        // Add Aave protocol to vault
        vault.addProtocol(Constants.AAVE_PROTOCOL_ID);
        console.log("Added Aave protocol to vault");
        
        // Output all deployed addresses for .env file
        console.log("\n--- Copy these values to your .env file ---");
        console.log("VAULT_ADDRESS=", address(vault));
        console.log("TOKEN_ADDRESS=", USDC_ADDRESS);
        console.log("REGISTRY_ADDRESS=", address(registry));
        console.log("AAVE_ADAPTER_ADDRESS=", address(aaveAdapter));
        
        vm.stopBroadcast();
    }
}