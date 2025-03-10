// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@layerbank-contracts/interfaces/ILToken.sol";
import "@layerbank-contracts/interfaces/IRateModel.sol";

contract LayerBankAPYTest is Test {
    // USDC ILToken address
    address constant TOKEN_ILTOKEN_ADDRESS = 0x0D8F8e271DD3f2fC58e5716d3Ff7041dBe3F0688;

    ILToken public token;
    IRateModel public rateModel;

    // Number of seconds in one year.
    uint256 constant SECONDS_PER_YEAR = 31536000;

    function setUp() public {
        token = ILToken(TOKEN_ILTOKEN_ADDRESS);
        // cast call <ILToken Address> "getRateModel()(address)" \ --rpc-url https://scroll-mainnet.g.alchemy.com/v2/<YOUR_API_KEY>
        rateModel = IRateModel(0x09aD162E117eFCC5cBD5Fd4865818f2ABA8e80D7); // ratemodel address.
    }

    function testCalculateSupplyAPY() public {
        // Fetch market state for the token.
        uint256 cash = token.getCash();         // available underlying asset in the market
        uint256 borrows = token.totalBorrow();    // total borrowed amount
        uint256 reserves = token.totalReserve();  // reserved amount
        uint256 reserveFactor = token.reserveFactor(); // fraction of interest kept as reserves

        // Get the per-second supply rate from the rate model.
        uint256 perSecondSupplyRate = rateModel.getSupplyRate(cash, borrows, reserves, reserveFactor);

        // Annualize the per-second rate:
        // Annual Rate (as a fraction, in 1e18 format) = perSecondSupplyRate * seconds in a year.
        uint256 annualSupplyRateFraction = perSecondSupplyRate * SECONDS_PER_YEAR;

        // Convert to a percentage. If 1e18 equals 100%, then:
        uint256 supplyAPYPercent = (annualSupplyRateFraction * 10000) / 1e18;

        console.log("Supply APY (%):", supplyAPYPercent);
        // For example, if supplyAPYPercent is 508, then the APY is 5.08%.
    }

    // function testCalculateBorrowAPY() public {
    //     // Fetch market state for the token.
    //     uint256 cash = token.getCash();
    //     uint256 borrows = token.totalBorrow();
    //     uint256 reserves = token.totalReserve();

    //     // Get the per-second borrow rate from the rate model.
    //     uint256 perSecondBorrowRate = rateModel.getBorrowRate(cash, borrows, reserves);

    //     // Annualize the rate:
    //     uint256 annualBorrowRateFraction = perSecondBorrowRate * SECONDS_PER_YEAR;

    //     // Convert to percentage:
    //     uint256 borrowAPYPercent = (annualBorrowRateFraction * 10000) / 1e18;

    //     console.log("Borrow APY (%):", borrowAPYPercent);
    //     // For instance, if borrowAPYPercent is 7, then the borrow APY is 7%.
    // }
}
