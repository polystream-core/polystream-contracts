// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import "@account-abstraction/interfaces/IEntryPoint.sol";
// import "@account-abstraction/interfaces/PackedUserOperation.sol";
// import "../src/account-abstraction/YieldVaultPaymaster.sol";
// import "../src/account-abstraction/YieldVaultAccount.sol";
// import "../src/account-abstraction/YieldVaultAccountFactory.sol";
// import "../src/vault/CombinedVault.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// /**
//  * @title AnvilAAInfrastructure
//  * @notice Script to set up Account Abstraction infrastructure on Anvil
//  */
// contract AnvilAAInfrastructure is Script {
//     IEntryPoint public entryPoint;
//     YieldVaultAccountFactory public factory;
//     YieldVaultPaymaster public paymaster;
    
//     // These would be your actual vault and token addresses
//     address public vaultAddress;
//     address public tokenAddress;
    
//     function run() external {
//         uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);
        
//         // Check if the EntryPoint contract exists at the standard address
//         address entryPointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
//         uint256 codeSize;
//         assembly {
//             codeSize := extcodesize(entryPointAddress)
//         }
        
//         if (codeSize == 0) {
//             console.log("EntryPoint not found at standard address. Deploy your own EntryPoint.");
//             vm.stopBroadcast();
//             return;
//         }
        
//         entryPoint = IEntryPoint(entryPointAddress);
//         console.log("Using EntryPoint at:", entryPointAddress);
        
//         // Set the vault and token addresses (replace with your actual addresses)
//         vaultAddress = vm.envAddress("VAULT_ADDRESS");
//         tokenAddress = vm.envAddress("TOKEN_ADDRESS");
//         console.log("Vault address:", vaultAddress);
//         console.log("Token address:", tokenAddress);
        
//         // Deploy YieldVaultAccountFactory
//         factory = new YieldVaultAccountFactory(entryPoint);
//         console.log("YieldVaultAccountFactory deployed at:", address(factory));
        
//         // Deploy YieldVaultPaymaster
//         paymaster = new YieldVaultPaymaster(entryPoint, vaultAddress);
//         console.log("YieldVaultPaymaster deployed at:", address(paymaster));
        
//         // Fund the paymaster
//         paymaster.deposit{value: 1 ether}();
//         console.log("Funded paymaster with 1 ETH");
        
//         vm.stopBroadcast();
//     }
// }

// /**
//  * @title AnvilCreateSmartAccount
//  * @notice Script to create a smart account for testing on Anvil
//  */
// contract AnvilCreateSmartAccount is Script {
//     function run() external {
//         // Load environment variables
//         uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//         address userAddress = vm.envAddress("USER_ADDRESS");
//         address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        
//         vm.startBroadcast(deployerPrivateKey);
        
//         // Create the account
//         YieldVaultAccountFactory factory = YieldVaultAccountFactory(factoryAddress);
//         address accountAddress = factory.getAccountAddress(userAddress);
//         console.log("Counterfactual account address:", accountAddress);
        
//         // Check if already deployed
//         uint256 codeSize;
//         assembly {
//             codeSize := extcodesize(accountAddress)
//         }
        
//         if (codeSize > 0) {
//             console.log("Smart account already deployed");
//         } else {
//             // Deploy the account
//             address deployedAccount = factory.createAccount(userAddress);
//             console.log("Smart account deployed at:", deployedAccount);
            
//             // Fund the smart account with some ETH for testing
//             (bool success, ) = deployedAccount.call{value: 0.1 ether}("");
//             require(success, "Failed to fund account");
//             console.log("Funded smart account with 0.1 ETH");
//         }
        
//         vm.stopBroadcast();
//     }
// }

// /**
//  * @title AnvilSimulateGaslessDeposit
//  * @notice Script to simulate a gasless deposit transaction on Anvil
//  */
// contract AnvilSimulateGaslessDeposit is Script {
//     function run() external {
//         // Load environment variables
//         uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
//         address userAddress = vm.addr(userPrivateKey);
//         address accountAddress = vm.envAddress("ACCOUNT_ADDRESS");
//         address paymasterAddress = vm.envAddress("PAYMASTER_ADDRESS");
//         address vaultAddress = vm.envAddress("VAULT_ADDRESS");
//         address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
//         address entryPointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
//         uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");
        
//         // Start with EOA to fund and prepare
//         vm.startBroadcast(userPrivateKey);
        
//         // Fund the smart account with tokens for testing
//         IERC20 token = IERC20(tokenAddress);
//         uint256 tokenBalance = token.balanceOf(userAddress);
//         require(tokenBalance >= depositAmount, "Insufficient token balance");
        
//         // Transfer tokens to the smart account
//         token.transfer(accountAddress, depositAmount);
//         console.log("Transferred", depositAmount, "tokens to smart account");
        
//         // Now create the UserOperation for gasless deposit
//         YieldVaultAccount account = YieldVaultAccount(payable(accountAddress));
//         IEntryPoint entryPoint = IEntryPoint(entryPointAddress);
        
//         // Create calldata for depositToVault function
//         bytes memory depositCallData = abi.encodeWithSelector(
//             account.depositToVault.selector,
//             vaultAddress,
//             tokenAddress,
//             depositAmount
//         );
        
//         // Create and sign the UserOperation
//         bytes memory paymasterAndData = abi.encodePacked(paymasterAddress);
        
//         // In a real scenario, we would use the bundler. For local testing,
//         // we'll call the entryPoint directly
        
//         // Create minimal UserOperation - fixed to include all 9 required fields
//         PackedUserOperation memory userOp = PackedUserOperation({
//             sender: accountAddress,
//             nonce: entryPoint.getNonce(accountAddress, 0),
//             initCode: hex"",
//             callData: depositCallData,
//             accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
//             preVerificationGas: 50000,  // Added missing field
//             gasFees: bytes32(abi.encodePacked(uint128(3e9), uint128(3e9))), // Added missing field (maxPriorityFeePerGas, maxFeePerGas)
//             paymasterAndData: paymasterAndData,
//             signature: hex""
//         });
        
//         // Sign the userOp
//         bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userOpHash);
//         userOp.signature = abi.encodePacked(r, s, v);
        
//         // For local testing, call the entryPoint directly
//         PackedUserOperation[] memory ops = new PackedUserOperation[](1);
//         ops[0] = userOp;
        
//         // Simulate the bundler's role by calling the entryPoint
//         entryPoint.handleOps(ops, payable(msg.sender));
        
//         console.log("Gasless deposit completed successfully");
//         vm.stopBroadcast();
//     }
// }

// /**
//  * @title AnvilSimulateGaslessWithdraw
//  * @notice Script to simulate a gasless withdraw transaction on Anvil
//  */
// contract AnvilSimulateGaslessWithdraw is Script {
//     function run() external {
//         // Load environment variables
//         uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
//         address userAddress = vm.addr(userPrivateKey);
//         address accountAddress = vm.envAddress("ACCOUNT_ADDRESS");
//         address paymasterAddress = vm.envAddress("PAYMASTER_ADDRESS");
//         address vaultAddress = vm.envAddress("VAULT_ADDRESS");
//         address entryPointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
//         uint256 withdrawAmount = vm.envUint("WITHDRAW_AMOUNT");
        
//         vm.startBroadcast(userPrivateKey);
        
//         // Create the UserOperation for gasless withdrawal
//         YieldVaultAccount account = YieldVaultAccount(payable(accountAddress));
//         IEntryPoint entryPoint = IEntryPoint(entryPointAddress);
        
//         // Create calldata for withdrawFromVault function
//         bytes memory withdrawCallData = abi.encodeWithSelector(
//             account.withdrawFromVault.selector,
//             vaultAddress,
//             withdrawAmount
//         );
        
//         // Create minimal UserOperation with paymaster - fixed to include all 9 required fields
//         bytes memory paymasterAndData = abi.encodePacked(paymasterAddress);
        
//         PackedUserOperation memory userOp = PackedUserOperation({
//             sender: accountAddress,
//             nonce: entryPoint.getNonce(accountAddress, 0),
//             initCode: hex"",
//             callData: withdrawCallData,
//             accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
//             preVerificationGas: 50000,  // Added missing field
//             gasFees: bytes32(abi.encodePacked(uint128(3e9), uint128(3e9))), // Added missing field (maxPriorityFeePerGas, maxFeePerGas)
//             paymasterAndData: paymasterAndData,
//             signature: hex""
//         });
        
//         // Sign the userOp
//         bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userOpHash);
//         userOp.signature = abi.encodePacked(r, s, v);
        
//         // For local testing, call the entryPoint directly
//         PackedUserOperation[] memory ops = new PackedUserOperation[](1);
//         ops[0] = userOp;
        
//         // Simulate the bundler's role
//         entryPoint.handleOps(ops, payable(msg.sender));
        
//         console.log("Gasless withdrawal completed successfully");
//         vm.stopBroadcast();
//     }
// }