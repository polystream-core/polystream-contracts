// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "forge-std/console.sol";

// contract ProtocolAdapter {
//     IERC20 public immutable stakingToken;
//     uint256 public totalStaked;
//     uint256 public lastHarvestAmount;

//     constructor(address _stakingToken) {
//         stakingToken = IERC20(_stakingToken);
//     }

//     function deposit(uint256 amount) external {
//         require(amount > 0, "Amount must be > 0");
//         require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
//         totalStaked += amount;
//     }

//     function depositFee(uint256 amount) external {
//         require(amount > 0, "Amount must be > 0");
//         require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
//     }

//     function convertFeeToReward(uint256 fee) external {
//         totalStaked -= fee;        
//     }

//     function withdraw(uint256 shareAmount, address user) external returns (uint256) {
//         require(totalStaked >= shareAmount, "Insufficient liquidity");


//         uint256 withdrawAmount = shareAmount;
//         console.log("shareAmount:", shareAmount);
//         console.log("totalStaked:", totalStaked);

//         totalStaked -= shareAmount;

//         console.log("Calculated Withdraw Amount:", withdrawAmount);

//         require(stakingToken.transfer(user, withdrawAmount), "Withdraw failed");
//         return withdrawAmount;
//     }

//     function harvest() external returns (uint256) {
//         uint256 balance = stakingToken.balanceOf(address(this));
//         console.log("Balance", balance);
//         console.log("totalStaked", totalStaked);
//         uint256 newRewards = balance - totalStaked;  
//         console.log("newRewards", newRewards);

//         stakingToken.approve(msg.sender, newRewards);
//         return newRewards;
//     }

// }
