// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@account-abstraction/core/BaseAccount.sol";
// import "@account-abstraction/core/Helpers.sol";
// import "@account-abstraction/interfaces/IEntryPoint.sol";
// import "@account-abstraction/interfaces/PackedUserOperation.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "forge-std/console.sol";

// /**
//  * @title YieldVaultAccount
//  * @notice Smart contract account for interacting with the YieldVault
//  * @dev Implements ERC-4337 BaseAccount for gasless transactions with the vault
//  */
// contract YieldVaultAccount is BaseAccount {
//     using ECDSA for bytes32;

//     // The EntryPoint contract that processes UserOperations
//     IEntryPoint private immutable _entryPoint;
    
//     // The owner of this account
//     address public owner;
    
//     // Events
//     event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
//     event VaultInteraction(address indexed vault, bytes4 selector, uint256 amount);
    
//     /**
//      * @dev Constructor
//      * @param _owner The owner of this account
//      * @param entryPointAddress The EntryPoint contract address
//      */
//     constructor(address _owner, IEntryPoint entryPointAddress) {
//         owner = _owner;
//         _entryPoint = entryPointAddress;
//     }
    
//     /**
//      * @dev Require the function call is from the owner or the EntryPoint
//      */
//     modifier onlyOwnerOrEntryPoint() {
//         require(
//             msg.sender == owner || msg.sender == address(entryPoint()),
//             "Only owner or EntryPoint"
//         );
//         _;
//     }
    
//     /**
//      * @dev Return the EntryPoint for this account
//      * @return The EntryPoint contract
//      */
//     function entryPoint() public view override returns (IEntryPoint) {
//         return _entryPoint;
//     }
    
//     /**
//      * @dev Return the current nonce
//      * @return Current nonce value
//      */
//     function getNonce() public view virtual override returns (uint256) {
//         return entryPoint().getNonce(address(this), 0);
//     }
    
//     /**
//      * @dev Change the owner of this account
//      * @param newOwner The new owner address
//      */
//     function transferOwnership(address newOwner) external onlyOwnerOrEntryPoint {
//         require(newOwner != address(0), "New owner is the zero address");
        
//         address oldOwner = owner;
//         owner = newOwner;
        
//         emit OwnerUpdated(oldOwner, newOwner);
//     }
    
//     /**
//      * @dev Execute a transaction only if it's from the owner or EntryPoint
//      * @param target The target contract address
//      * @param value The ETH value to send
//      * @param data The calldata to send
//      */
//     function execute(
//         address target,
//         uint256 value,
//         bytes calldata data
//     ) external onlyOwnerOrEntryPoint {
//         (bool success, bytes memory result) = target.call{value: value}(data);
        
//         if (!success) {
//             assembly {
//                 revert(add(result, 32), mload(result))
//             }
//         }
        
//         // Emit event with info about the vault interaction
//         if (data.length >= 4) {
//             bytes4 selector = bytes4(data[:4]);
//             uint256 amount = 0;
//             if (data.length >= 68) {
//                 // This assumes that amount is the second parameter in the function call
//                 // (after the address parameter which is 32 bytes)
//                 amount = abi.decode(data[36:68], (uint256));
//             }
            
//             emit VaultInteraction(target, selector, amount);
//         }
//     }
    
//     /**
//      * @dev Execute a sequence of transactions only if it's from the owner or EntryPoint
//      * @param targets Array of target addresses
//      * @param values Array of ETH values
//      * @param datas Array of calldata
//      */
//     function executeBatch(
//         address[] calldata targets,
//         uint256[] calldata values,
//         bytes[] calldata datas
//     ) external onlyOwnerOrEntryPoint {
//         require(
//             targets.length == values.length && 
//             targets.length == datas.length,
//             "Arrays length mismatch"
//         );
        
//         for (uint256 i = 0; i < targets.length; i++) {
//             (bool success, bytes memory result) = targets[i].call{value: values[i]}(datas[i]);
            
//             if (!success) {
//                 assembly {
//                     revert(add(result, 32), mload(result))
//                 }
//             }
            
//             // Emit event for each vault interaction
//             if (datas[i].length >= 4) {
//                 bytes4 selector = bytes4(datas[i][:4]);
//                 uint256 amount = 0;
//                 if (datas[i].length >= 68) {
//                     // Assuming amount is the second parameter
//                     amount = abi.decode(datas[i][36:68], (uint256));
//                 }
                
//                 emit VaultInteraction(targets[i], selector, amount);
//             }
//         }
//     }
    
//     /**
//      * @dev Deposit an ERC20 token to a vault contract
//      * @param vault The vault contract address
//      * @param token The ERC20 token contract
//      * @param amount The amount to deposit
//      */
//     function depositToVault(
//         address vault,
//         address token,
//         uint256 amount
//     ) external onlyOwnerOrEntryPoint {
//         // Approve vault to spend tokens
//         IERC20(token).approve(vault, amount);
        
//         // Create deposit calldata
//         bytes memory depositCallData = abi.encodeWithSelector(
//             bytes4(keccak256("deposit(address,uint256)")),
//             owner, // User is the account owner
//             amount
//         );
        
//         // Execute deposit
//         (bool success, bytes memory result) = vault.call(depositCallData);
        
//         if (!success) {
//             assembly {
//                 revert(add(result, 32), mload(result))
//             }
//         }
        
//         emit VaultInteraction(vault, bytes4(keccak256("deposit(address,uint256)")), amount);
//     }
    
//     /**
//      * @dev Withdraw from a vault contract
//      * @param vault The vault contract address
//      * @param amount The amount to withdraw
//      */
//     function withdrawFromVault(
//         address vault,
//         uint256 amount
//     ) external onlyOwnerOrEntryPoint {
//         // Create withdraw calldata
//         bytes memory withdrawCallData = abi.encodeWithSelector(
//             bytes4(keccak256("withdraw(address,uint256)")),
//             owner, // User is the account owner
//             amount
//         );
        
//         // Execute withdraw
//         (bool success, bytes memory result) = vault.call(withdrawCallData);
        
//         if (!success) {
//             assembly {
//                 revert(add(result, 32), mload(result))
//             }
//         }
        
//         emit VaultInteraction(vault, bytes4(keccak256("withdraw(address,uint256)")), amount);
//     }
    
//     /**
//      * @dev Validate user operation
//      * @param userOp The UserOperation to validate
//      * @param userOpHash The hash of the UserOperation
//      * @return validationData The validation data
//      */
//     function _validateSignature(
//         PackedUserOperation calldata userOp,
//         bytes32 userOpHash
//     ) internal override returns (uint256) {
//         // Use ECDSA to recover signer from signature
//         bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        
//         // Verify the signature is from the owner
//         bytes calldata signature = userOp.signature;
//         address recovered = ECDSA.recover(signedHash, signature);
        
//         if (recovered != owner) {
//             return SIG_VALIDATION_FAILED;
//         }
        
//         return 0; // Signature is valid
//     }
    
//     /**
//      * @dev Handle deposits to the account
//      */
//     receive() external payable {}
// }