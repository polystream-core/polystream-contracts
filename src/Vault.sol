// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//IMPORTS
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

//INTERFACES



contract YieldVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    //STATE VARIABLES
    

    //CONSTRUCTORS

    //CORE FUNCTIONS

    //VIEW FUNCTIONS

}