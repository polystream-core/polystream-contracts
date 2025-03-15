// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@account-abstraction/interfaces/IEntryPoint.sol";
import "@account-abstraction/interfaces/PackedUserOperation.sol";
import "../src/account-abstraction/YieldVaultAccount.sol";
import "../src/vault/CombinedVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CompleteAATest is Script {
    // Constants
    address constant USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    address constant ENTRY_POINT_ADDRESS = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    function run() external {
        // Load environment variables
        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        address userAddress = vm.addr(userPrivateKey);
        address accountAddress = vm.envAddress("ACCOUNT_ADDRESS");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");
        
        // Start broadcast from the user's EOA
        vm.startBroadcast(userPrivateKey);
        
        // Step 1: Update USDC balance for the user
        console.log("==== STEP 1: FUND USER WITH USDC ====");
        _updateUSDCBalance(userAddress, 10_000_000 * 1e6); // 10M USDC
        
        IERC20 usdc = IERC20(USDC_ADDRESS);
        console.log("User USDC balance:", usdc.balanceOf(userAddress));
        
        // Step 2: Transfer USDC to the smart account
        console.log("\n==== STEP 2: TRANSFER USDC TO SMART ACCOUNT ====");
        usdc.transfer(accountAddress, depositAmount);
        console.log("Transferred", depositAmount, "USDC to smart account");
        console.log("Smart account USDC balance:", usdc.balanceOf(accountAddress));
        
        // Step 3: Create and submit UserOperation for gasless deposit
        console.log("\n==== STEP 3: CREATE AND SUBMIT USER OPERATION ====");
        
        // Get account and entryPoint contracts
        YieldVaultAccount account = YieldVaultAccount(payable(accountAddress));
        IEntryPoint entryPoint = IEntryPoint(ENTRY_POINT_ADDRESS);
        
        // Create deposit calldata
        bytes memory depositCallData = abi.encodeWithSelector(
            account.depositToVault.selector,
            vaultAddress,
            USDC_ADDRESS,
            depositAmount
        );
        
        // Create UserOperation
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: accountAddress,
            nonce: entryPoint.getNonce(accountAddress, 0),
            initCode: hex"",
            callData: depositCallData,
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 50000,
            gasFees: bytes32(abi.encodePacked(uint128(3e9), uint128(3e9))),
            paymasterAndData: bytes(""), // No paymaster for testing
            signature: hex""
        });
        
        // Sign the userOperation
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Package the userOp for handleOps
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        console.log("About to submit UserOperation to EntryPoint...");
        
        // Submit the operation directly to the EntryPoint
        entryPoint.handleOps(ops, payable(msg.sender));
        
        console.log("UserOperation executed successfully!");
        
        // Step 4: Verify the deposit was successful by checking vault balance
        console.log("\n==== STEP 4: VERIFY DEPOSIT SUCCESS ====");
        
        // Check the vault balance for the user
        CombinedVault vault = CombinedVault(vaultAddress);
        uint256 vaultBalance = vault.balanceOf(userAddress);
        console.log("User vault balance after deposit:", vaultBalance);
        
        if (vaultBalance >= depositAmount) {
            console.log("SUCCESS: Account abstraction deposit completed successfully!");
        } else {
            console.log("FAILED: Deposit amount not reflected in vault balance");
        }
        
        vm.stopBroadcast();
    }
    
    function _updateUSDCBalance(address account, uint256 newBalance) internal {
        // Get initial balance
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 initialBalance = usdc.balanceOf(account);
        console.log("Initial USDC balance:", initialBalance);
        
        // Update balance at slot 9 (as discovered in previous tests)
        bytes32 balanceSlot = keccak256(abi.encode(account, uint256(9)));
        vm.store(USDC_ADDRESS, balanceSlot, bytes32(newBalance));
        
        // Verify the update
        uint256 updatedBalance = usdc.balanceOf(account);
        console.log("Updated USDC balance:", updatedBalance);
    }
}