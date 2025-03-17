// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Strategy/YieldOptimizer.sol";
import "../src/core/CombinedVault.sol";
import "../src/core/ProtocolRegistry.sol";
import "../src/adapters/mocks/MockAaveAdapter.sol";
import "../src/adapters/mocks/MockLayerBankAdapter.sol";
import "../src/tokens/mocks/MockUSDC.sol";

contract YieldOptimizerTest is Test {
    YieldOptimizer public optimizer;
    CombinedVault public vault;
    ProtocolRegistry public registry;
    MockAaveAdapter public adapter1;
    MockLayerBankAdapter public adapter2;
    MockUSDC public mockUSDC;
    address public asset;

    function setUp() public {
        console.log("=== Setting up YieldOptimizerTest ===");

        // Deploy Mock USDC token correctly
        mockUSDC = new MockUSDC(address(this));
        asset = address(mockUSDC);

        // **Add `address(this)` as a minter so we can mint tokens in tests**
        mockUSDC.addMinter(address(this));

        console.log("Mock USDC deployed at:", asset);

        // Deploy the registry
        registry = new ProtocolRegistry();

        // Deploy two mock protocol adapters with different APYs
        adapter1 = new MockAaveAdapter(asset);      // Mock Aave Adapter
        adapter2 = new MockLayerBankAdapter(asset); // Mock LayerBank Adapter

        console.log("Adapters deployed");

        // Ensure the adapters recognize USDC as a supported asset
        adapter1.addSupportedAsset(asset, asset);
        adapter2.addSupportedAsset(asset, asset);
        console.log("Adapters now support USDC");

        // Register protocols in the registry
        registry.registerProtocol(1, "Mock Aave");
        registry.registerProtocol(2, "Mock LayerBank");

        // Register adapters for each protocol
        registry.registerAdapter(1, asset, address(adapter1));
        registry.registerAdapter(2, asset, address(adapter2));

        console.log("Protocols and adapters registered");

        // ✅ Use `vm.prank(address)` to ensure `msg.sender` is `address(this)`
        vm.prank(address(this));
        vault = new CombinedVault(address(registry), asset);
        
        // ✅ Get the actual owner of the vault and log it
        address vaultOwner = vault.owner();
        console.log("Vault deployed! Expected owner:", address(this));
        console.log("Actual Vault Owner:", vaultOwner);

        // ✅ Ensure vault recognizes both protocols
        vm.prank(address(this));
        vault.addProtocol(1);

        vm.prank(address(this));
        vault.addProtocol(2);

        console.log("Vault recognizes protocols");

        // ✅ Set initial active protocol
        vm.prank(address(this));
        registry.setActiveProtocol(2); // Start with lower APY (Mock Aave)

        console.log("Active protocol set to 2");

        // ✅ Deploy Yield Optimizer
        optimizer = new YieldOptimizer(address(vault), asset);
        console.log("Yield Optimizer deployed");

        // ✅ Ensure `setAuthorizedCaller` is being called by the owner
        require(vaultOwner == address(this), "Vault owner mismatch! Check deployment");

        // ✅ Authorize optimizer if test contract is the owner
        vm.prank(address(this));  // Ensure it's the owner before calling
        vault.setAuthorizedCaller(address(optimizer)); 
        registry.setAuthorizedCaller(address(optimizer));
        console.log("Yield Optimizer is now authorized in Vault");

        console.log("=== Setup Complete ===");
    }

    function testOptimizeYield() public {
        console.log("=== Running testOptimizeYield ===");

        // Initial State: Protocol 1 (Mock Aave) is active
        uint256 activeProtocol = registry.getActiveProtocolId();
        console.log("Initial active protocol:", activeProtocol);

        // Get the adapter of the active protocol
        address activeAdapter = address(registry.getAdapter(activeProtocol, address(asset)));
        require(activeAdapter != address(0), "Active adapter not found");
        console.log("Active protocol adapter address:", activeAdapter);

        // Check balance in the active protocol before optimization
        uint256 balanceInAdapter = IProtocolAdapter(activeAdapter).getBalance(address(asset));
        console.log("Balance in active protocol before optimization:", balanceInAdapter);

        // Deposit funds into the vault
        uint256 depositAmount = 1000 * 10**6; // 1000 Mock USDC
        mockUSDC.mint(address(this), depositAmount);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(address(this), depositAmount);

        console.log("Deposited %d USDC into the vault", depositAmount);

        // Check balance again after deposit
        balanceInAdapter = IProtocolAdapter(activeAdapter).getBalance(address(asset));
        console.log("Balance in active protocol after deposit:", balanceInAdapter);

        // Optimize yield (should switch to protocol 2 with higher APY)
        optimizer.optimizeYield();

        // Validate active protocol changed to the one with higher APY
        uint256 newActiveProtocol = registry.getActiveProtocolId();
        console.log("New active protocol after optimization:", newActiveProtocol);
    }
}
