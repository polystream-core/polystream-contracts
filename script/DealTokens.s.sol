// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DealTokens is Script {
    // USDC address on Scroll
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address userAddress = vm.envAddress("USER_ADDRESS");
        uint256 amount = 10_000_000 * 1e6; // 10 million USDC
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get initial balance
        uint256 initialBalance = IERC20(USDC_ADDRESS).balanceOf(userAddress);
        console.log("Initial USDC balance of user:", initialBalance);
        console.log("User address", userAddress);
        
        // The USDC contract on Scroll appears to be an implementation behind a proxy
        // We need to find the correct storage slot for balances
        
        // Looking at storage slot 0
        bytes32 slot0Value = vm.load(USDC_ADDRESS, bytes32(uint256(0)));
        console.log("Slot 0 value:", vm.toString(slot0Value));
        
        // For ERC20 tokens, the balances mapping is typically stored in a specific slot
        // Let's try various slot positions for the balance mapping
        
        // Trying with a more comprehensive approach
        // ERC20 implementation from OpenZeppelin typically uses mapping at slot 0
        bytes32 balanceSlot;
        uint256 newBalance = amount;
        
        // Try slots 0 through 10 to find the balances mapping
        for (uint256 slot = 0; slot <= 10; slot++) {
            // The key in the mapping is derived from keccak256(abi.encode(address, uint256))
            balanceSlot = keccak256(abi.encode(userAddress, uint256(slot)));
            
            // Store new balance
            vm.store(USDC_ADDRESS, balanceSlot, bytes32(newBalance));
            
            // Check if balance was updated
            uint256 updatedBalance = IERC20(USDC_ADDRESS).balanceOf(userAddress);
            if (updatedBalance != initialBalance) {
                console.log("Found balance at slot:", slot);
                console.log("Updated balance:", updatedBalance);
                break;
            }
        }
        
        // If we couldn't find the slot using the standard approach, try alternative approaches
        uint256 finalBalance = IERC20(USDC_ADDRESS).balanceOf(userAddress);
        if (finalBalance == initialBalance) {
            // This pattern is used if balances are stored differently
            // Sometimes, USDC implementations use a storage pattern where the slot is pre-hashed
            bytes32 mappingSlot = keccak256(abi.encode("balances"));
            balanceSlot = keccak256(abi.encode(userAddress, mappingSlot));
            vm.store(USDC_ADDRESS, balanceSlot, bytes32(newBalance));
            
            finalBalance = IERC20(USDC_ADDRESS).balanceOf(userAddress);
            if (finalBalance != initialBalance) {
                console.log("Found balance using pre-hashed slot name");
                console.log("Updated balance:", finalBalance);
            }
        }
        
        // Try one more pattern for USDC implementations
        if (finalBalance == initialBalance) {
            // Some implementations use a different pattern for balance storage
            // where the user address is directly used as the key
            for (uint256 slot = 0; slot <= 10; slot++) {
                bytes32 directSlot = keccak256(abi.encode(userAddress, slot));
                vm.store(USDC_ADDRESS, directSlot, bytes32(newBalance));
                
                finalBalance = IERC20(USDC_ADDRESS).balanceOf(userAddress);
                if (finalBalance != initialBalance) {
                    console.log("Found balance using direct user address at slot:", slot);
                    console.log("Updated balance:", finalBalance);
                    break;
                }
            }
        }
        
        finalBalance = IERC20(USDC_ADDRESS).balanceOf(userAddress);
        
        // Check final result
        if (finalBalance > initialBalance) {
            console.log("Successfully updated USDC balance to:", finalBalance / 1e6, "USDC");
        } else {
            console.log("Failed to update USDC balance using common storage patterns.");
            
            // Since we need to get past this for testing, let's try a direct low-level approach
            // by pretending to be a USDC holder and sending tokens
            vm.stopBroadcast();
            
            // Find a holder with enough USDC
            address usdcHolder = 0xECB6a3E0E99700b32bb03BA14727d99FE8E538cf;
            uint256 holderBalance = IERC20(USDC_ADDRESS).balanceOf(usdcHolder);
            console.log("Found USDC holder with balance:", holderBalance / 1e6, "USDC");
            
            // Directly modify the allowance slot to allow our user to transfer tokens
            // This is a more advanced approach that requires understanding the specific
            // storage layout of the USDC contract
            console.log("Direct manipulation approach would require more specific analysis of the contract's storage layout.");
        }
        
        vm.stopBroadcast();
    }
}