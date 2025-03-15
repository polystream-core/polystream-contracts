// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/account-abstraction/YieldVaultAccountFactory.sol";
import "../src/account-abstraction/YieldVaultAccount.sol";

/**
 * @title CreateSmartAccount
 * @notice Script to create a smart account using the deployed factory
 */
contract CreateSmartAccount is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address userAddress = vm.envAddress("USER_ADDRESS");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Create the account using the factory
        YieldVaultAccountFactory factory = YieldVaultAccountFactory(factoryAddress);
        
        // Get the counterfactual account address
        address accountAddress = factory.getAccountAddress(userAddress);
        console.log("Counterfactual account address:", accountAddress);
        
        // Check if the account is already deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(accountAddress)
        }
        
        if (codeSize > 0) {
            console.log("Smart account already deployed");
        } else {
            // Deploy the account
            address deployedAccount = factory.createAccount(userAddress);
            console.log("Smart account deployed at:", deployedAccount);
            
            // Fund the smart account with some ETH for testing
            (bool success, ) = deployedAccount.call{value: 0.1 ether}("");
            require(success, "Failed to fund account");
            console.log("Funded smart account with 0.1 ETH");
        }
        
        vm.stopBroadcast();
    }
}