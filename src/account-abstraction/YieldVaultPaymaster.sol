// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@account-abstraction/core/BasePaymaster.sol";
import "@account-abstraction/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title YieldVaultPaymasterSimple
 * @notice Simplified Paymaster for testing on Anvil
 */
contract YieldVaultPaymaster is BasePaymaster {
    // Vault contract that this paymaster sponsors
    address public vaultContract;
    
    // Supported vault function selectors
    bytes4 public constant DEPOSIT_SELECTOR = bytes4(keccak256("deposit(address,uint256)"));
    bytes4 public constant WITHDRAW_SELECTOR = bytes4(keccak256("withdraw(address,uint256)"));
    
    // Config values
    uint256 public constant MAX_GAS_LIMIT = 500000;
    uint256 public maxCostAllowed = 0.01 ether; // 0.01 ETH per transaction

    // Events
    event GasSponsored(address indexed user, bytes4 selector, uint256 gasCost);
    event VaultContractUpdated(address indexed newVaultContract);
    event MaxCostAllowedUpdated(uint256 newMaxCost);
    
    /**
     * @dev Constructor
     * @param _entryPoint The EntryPoint contract address
     * @param _vaultContract The vault contract address to sponsor gas for
     */
    constructor(IEntryPoint _entryPoint, address _vaultContract) BasePaymaster(_entryPoint) {
        require(_vaultContract != address(0), "Invalid vault contract address");
        vaultContract = _vaultContract;
    }
    
    /**
     * @dev Override to skip the interface check for testing
     */
    function _validateEntryPointInterface(IEntryPoint _entryPoint) internal override {
        // Skip validation for testing
    }
    
    /**
     * @dev Set the vault contract address
     * @param _vaultContract The new vault contract address
     */
    function setVaultContract(address _vaultContract) external onlyOwner {
        require(_vaultContract != address(0), "Invalid vault contract address");
        vaultContract = _vaultContract;
        
        emit VaultContractUpdated(_vaultContract);
    }
    
    /**
     * @dev Set the maximum cost allowed per transaction
     * @param _maxCostAllowed The new maximum cost allowed in ETH
     */
    function setMaxCostAllowed(uint256 _maxCostAllowed) external onlyOwner {
        maxCostAllowed = _maxCostAllowed;
        
        emit MaxCostAllowedUpdated(_maxCostAllowed);
    }
    
    /**
     * @dev Check if a UserOperation is valid and should be paid for
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal override returns (bytes memory context, uint256 validationData) {
        // Verify this is a call to the vault contract
        require(userOp.callData.length >= 4, "Invalid calldata");
        
        // Extract the target contract and function selector
        (address targetContract, bytes4 selector) = _parseCallData(userOp.callData);
        
        // Check that the target is our vault contract
        require(targetContract == vaultContract, "Only vault contract allowed");
        
        // Check that the function is either deposit or withdraw
        require(
            selector == DEPOSIT_SELECTOR || 
            selector == WITHDRAW_SELECTOR,
            "Only deposit/withdraw allowed"
        );
        
        // Check total cost is within our limits
        require(maxCost <= maxCostAllowed, "Transaction cost too high");
        
        // Context contains the function selector and user that called it
        context = abi.encode(selector, userOp.sender);
        
        // Return validationData = 0 which means the request is valid with no time range restrictions
        return (context, 0);
    }
    
    /**
     * @dev Execute after a UserOperation is executed
     */
    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        // If the transaction was successful, emit an event
        if (mode == PostOpMode.opSucceeded) {
            (bytes4 selector, address user) = abi.decode(context, (bytes4, address));
            emit GasSponsored(user, selector, actualGasCost);
        }
    }
    
    /**
     * @dev Extracts the target contract address and function selector from calldata
     */
    function _parseCallData(bytes calldata data) internal pure returns (address target, bytes4 selector) {
        // First 20 bytes are the target address
        bytes20 targetBytes;
        assembly {
            targetBytes := calldataload(data.offset)
        }
        target = address(targetBytes);
        
        // The next 4 bytes are the function selector
        bytes4 selectorBytes;
        assembly {
            selectorBytes := calldataload(add(data.offset, 20))
        }
        selector = selectorBytes;
        
        return (target, selector);
    }
}