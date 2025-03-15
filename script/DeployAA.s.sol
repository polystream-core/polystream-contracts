// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@account-abstraction/core/EntryPoint.sol";
import "../src/account-abstraction/YieldVaultAccountFactory.sol";
import "../src/account-abstraction/YieldVaultPaymaster.sol";
import "../src/vault/CombinedVault.sol";

/**
 * @title DeployAAInfrastructure
 * @notice Script to deploy Account Abstraction infrastructure on Scroll fork
 */
contract DeployAAInfrastructure is Script {
    IEntryPoint public entryPoint;
    YieldVaultAccountFactory public factory;
    YieldVaultPaymaster public paymaster;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy EntryPoint (instead of using standard address)
        entryPoint = new EntryPoint();
        console.log("EntryPoint deployed at:", address(entryPoint));
        
        // Get the vault address from environment
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        console.log("Using vault address:", vaultAddress);
        
        // Deploy YieldVaultAccountFactory
        factory = new YieldVaultAccountFactory(entryPoint);
        console.log("YieldVaultAccountFactory deployed at:", address(factory));
        
        // Deploy YieldVaultPaymaster
        paymaster = new YieldVaultPaymaster(entryPoint, vaultAddress);
        console.log("YieldVaultPaymaster deployed at:", address(paymaster));
        
        // Fund the EntryPoint with some ETH
        (bool success1,) = address(entryPoint).call{value: 1 ether}("");
        require(success1, "Failed to fund EntryPoint");
        console.log("Funded EntryPoint with 1 ETH");
        
        // Fund the paymaster with some ETH
        paymaster.deposit{value: 1 ether}();
        console.log("Funded paymaster with 1 ETH");
        
        vm.stopBroadcast();
    }
}