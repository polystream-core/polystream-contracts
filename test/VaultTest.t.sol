// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";

// import "../src/vault/Vault.sol";
// import "../src/vault/IVault.sol";
// import "../src/rewards/RewardManager.sol";
// import "../src/rewards/IRewardManager.sol";
// import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import "../src/MockProtocolAdapter.sol";

// address constant REAL_USDC_ADDRESS = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;

// contract VaultTest is Test {
//     Vault public vault;
//     RewardManager public rewardManager;
//     ProtocolAdapter public protocolAdapter;
//     IERC20 public usdc;

//     address public user1;
//     address public user2;
//     address public yieldDepositor;

//     function setUp() public {
//         user1 = address(0xBEEF);
//         user2 = address(0xCAFE);
//         yieldDepositor = address(0xDEAD);

//         protocolAdapter = new ProtocolAdapter(REAL_USDC_ADDRESS);
//         vault = new Vault(REAL_USDC_ADDRESS, address(protocolAdapter));
//         rewardManager = new RewardManager(REAL_USDC_ADDRESS, address(vault));

//         vault.setRewardManager(address(rewardManager));

//         usdc = IERC20(REAL_USDC_ADDRESS);

//         // Mock USDC balances for testing
//         deal(address(usdc), user1, 3000e6);
//         deal(address(usdc), user2, 5000e6);
//         deal(address(usdc), yieldDepositor, 300e6);

//         console.log("=== Setup Complete ===");
//     }

//     /// ✅ **Test: Normal staking and unstaking after reward accumulation**
//     function testNormalStakingAndUnstaking() public {
//         vm.startPrank(user1);
//         usdc.approve(address(vault), 3000e6);
//         vault.deposit(user1, 3000e6);
//         vm.stopPrank();

//         console.log("User1 deposited 3000 USDC into adapter");
//         console.log("Time:", block.timestamp);
//         console.log("Protocol's USDC balance:", usdc.balanceOf(address(protocolAdapter)));

//         // Simulate passage of time (1 epoch)
//         vm.warp(1751536052);
//         console.log("Time after epoch:", block.timestamp);

//         // Simulate yield deposit
//         vm.startPrank(yieldDepositor);
//         usdc.approve(address(protocolAdapter), 300e6);
//         protocolAdapter.depositFee(300e6);  // Mock yield accrued in protocol adapter
//         console.log("Protocol's USDC balance:", usdc.balanceOf(address(protocolAdapter)));
//         vm.stopPrank();

//         console.log("300 USDC deposited as yield");
//         console.log("Time after another epoch:", block.timestamp);

//         console.log("Before withdrawal:");
//         console.log("User1's Vault shares:", vault.balanceOf(user1));
//         console.log("User1's USDC balance:", usdc.balanceOf(user1));

//         vm.warp(1761536052);
//         vm.prank(address(vault));
//         vault.checkAndHarvest();

//         // User1 withdraws full stake
//         vm.startPrank(user1);
//         console.log("User1 new balance:", usdc.balanceOf(user1));
//         vault.withdraw(user1, 3000e6);
//         vm.stopPrank();

//         console.log("User1 withdrew full stake, new balance:", usdc.balanceOf(user1));

//     }

//     function testEarlyWithdrawalPenalty() public {
//         vm.startPrank(user1);
//         usdc.approve(address(vault), 3000e6);
//         vault.deposit(user1, 3000e6);
//         vm.stopPrank();

//         console.log("User1 deposited 3000 USDC into adapter");
//         console.log("Time:", block.timestamp);
//         console.log("Protocol's USDC balance:", usdc.balanceOf(address(protocolAdapter)));

//         // Simulate yield deposit
//         vm.startPrank(yieldDepositor);
//         usdc.approve(address(protocolAdapter), 300e6);
//         protocolAdapter.depositFee(300e6);
//         console.log("Protocol's USDC balance:", usdc.balanceOf(address(protocolAdapter)));
//         vm.stopPrank();

//         console.log("300 USDC deposited as yield");
//         console.log("Time after another epoch:", block.timestamp);

//         console.log("Before withdrawal:");
//         console.log("User1's Vault shares:", vault.balanceOf(user1));
//         console.log("User1's USDC balance:", usdc.balanceOf(user1));

//         vm.warp(1741580411);
//         vm.prank(address(vault));
//         vault.checkAndHarvest();

//         vm.startPrank(user1);
//         console.log("User1 new balance:", usdc.balanceOf(user1));
//         vault.withdraw(user1, 3000e6);
//         vm.stopPrank();

//         console.log("User1 withdrew full stake, new balance:", usdc.balanceOf(user1));
//     }

//     function testOldStakeNewStakeOnly5PercentDeductedFromNew() public {
//         vm.startPrank(user2);
//         usdc.approve(address(vault), 3000e6);
//         vault.deposit(user2, 3000e6);
//         vm.stopPrank();

//         console.log("User2 deposited 3000 USDC in Epoch 1");
//         console.log("Time:", block.timestamp);
//         console.log("Protocol's USDC balance:", usdc.balanceOf(address(protocolAdapter)));

//         vm.warp(1751850411);
//         console.log("Time:", block.timestamp);

//         vm.startPrank(user2);
//         usdc.approve(address(vault), 2000e6);
//         vault.deposit(user2, 2000e6);
//         vm.stopPrank();

//         console.log("User2 deposited 1000 USDC in Epoch 2");

//         vm.warp(1751850418);
//         console.log("Time:", block.timestamp);

//         console.log("Before withdrawal:");
//         console.log("User2's Vault shares:", vault.balanceOf(user2));

//         vm.startPrank(user2);
//         vault.withdraw(user2, 5000e6);
//         vm.stopPrank();

//         uint256 expectedPenalty = (2000e6 * 5) / 100;
//         uint256 expectedBalance = 5000e6 - expectedPenalty;

//         console.log("User2 withdrew old + new stake, expected penalty:", expectedPenalty);
//         console.log("User2 new balance:", usdc.balanceOf(user2));
//         console.log("Protocol's USDC balance:", usdc.balanceOf(address(protocolAdapter)));

//         vm.prank(address(vault));
//         vault.checkAndHarvest();

//         assertEq(
//             usdc.balanceOf(user2), 
//             expectedBalance, 
//             "User should be penalized only on new deposit"
//         );
//     }

//     function testTwoUserDifferentEpochDeposits() public {
//         // **User1 deposits 3000 USDC in Epoch 1**
//         vm.startPrank(user1);
//         usdc.approve(address(vault), 3000e6);
//         vault.deposit(user1, 3000e6);
//         vm.stopPrank();
        
//         console.log("User1 deposited 3000 USDC in Epoch 1");
//         console.log("Timestamp 0:", block.timestamp);
//         vm.warp(block.timestamp + 1 days);
//         console.log("Timestamp 1:", block.timestamp);

//         vm.prank(address(vault));
//         vault.checkAndHarvest();

//         // Simulate half an epoch
//         vm.warp(block.timestamp + (1 days / 2));
//         console.log("Timestamp 2:", block.timestamp);
//         console.log("Midway through Epoch 2:", block.timestamp);

//         // **User2 deposits 2000 USDC mid-epoch**
//         vm.startPrank(user2);
//         usdc.approve(address(vault), 2000e6);
//         vault.deposit(user2, 2000e6);
//         vm.stopPrank();

//         console.log("User2 deposited 2000 USDC mid-Epoch 1");

//         // Simulate yield deposit
//         vm.startPrank(yieldDepositor);
//         usdc.approve(address(protocolAdapter), 300e6);
//         protocolAdapter.depositFee(300e6);
//         vm.stopPrank();

//         console.log("Yield of 300 USDC deposited");

//         // Simulate another epoch
//         vm.warp(1742624700);
//         vm.prank(address(vault));
//         vault.checkAndHarvest();

//         uint256 user1Reward = rewardManager.getUserRewardDebt(user1);
//         uint256 user2Reward = rewardManager.getUserRewardDebt(user2);

//         console.log("User1 Reward Debt:", user1Reward);
//         console.log("User2 Reward Debt:", user2Reward);

//         assertGt(user1Reward, user2Reward, "User1 should receive a higher reward since User2 deposited mid-epoch.");
//     }

//         function testTwoUserRewardDistribution() public {
//         // **User1 deposits 3000 USDC in Epoch 1**
//         vm.startPrank(user1);
//         usdc.approve(address(vault), 3000e6);
//         vault.deposit(user1, 3000e6);
//         vm.stopPrank();
        
//         console.log("User1 deposited 3000 USDC in Epoch 1");

//         vm.startPrank(user2);
//         usdc.approve(address(vault), 2000e6);
//         vault.deposit(user2, 2000e6);
//         vm.stopPrank();

//         console.log("User2 deposited 2000 USDC in Epoch 2");

//         // Simulate yield deposit
//         vm.startPrank(yieldDepositor);
//         usdc.approve(address(protocolAdapter), 300e6);
//         protocolAdapter.depositFee(300e6);
//         vm.stopPrank();

//         console.log("Yield of 300 USDC deposited");

//         vm.warp(1761536052);
//         vm.prank(address(vault));
//         vault.checkAndHarvest();

//         uint256 user1Reward = rewardManager.getUserRewardDebt(user1);
//         uint256 user2Reward = rewardManager.getUserRewardDebt(user2);

//         console.log("User1 Reward Debt:", user1Reward);
//         console.log("User2 Reward Debt:", user2Reward);

//         assertGt(user1Reward, user2Reward, "User1 should receive a higher reward than User2 since they were in the vault longer.");
//     }
// }
