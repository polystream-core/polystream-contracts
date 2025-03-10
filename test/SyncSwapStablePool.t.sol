// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Foundry
import "forge-std/Test.sol";
import "forge-std/console.sol";

/**
 * @dev Minimal ERC20 interface for USDC and USDT (6 decimals)
 */
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @dev SyncSwap Router interface for adding liquidity to a stable pool.
 */
interface ISyncSwapRouter {
    struct TokenInput {
        address token;
        uint amount;
    }

    /**
     * @notice Add liquidity to a pool.
     * @param pool The stable pool contract address for USDC/USDT
     * @param inputs An array of TokenInput specifying which tokens and how much to deposit
     * @param data Extra data the pool might need (often includes (address to, uint8 withdrawMode))
     * @param minLiquidity The minimum LP tokens you want to receive (slippage protection)
     * @param callback A callback address if the pool uses a callback mechanism (usually 0)
     * @param callbackData Additional data for the callback (usually empty)
     * @return liquidity The amount of LP tokens minted
     */
    function addLiquidity(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        address callback,
        bytes calldata callbackData
    ) external payable returns (uint liquidity);
}

contract SyncSwapStablePoolTest is Test {
    // --- Replace these addresses with the actual deployed addresses on Scroll ---
    address constant ROUTER_ADDRESS      = 0x80e38291e06339d10AAB483C65695D004dBD5C69; 
    address constant STABLE_POOL_ADDRESS = 0x2076d4632853FB165Cf7c7e7faD592DaC70f4fe1; // USDC/USDT stable pool
    address constant USDC_ADDRESS        = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;    
    address constant USDT_ADDRESS        = 0xf55BEC9cafDbE8730f096Aa55dad6D22d44099Df;  

    // The user who will add liquidity
    address public testUser;

    // Contract interfaces
    ISyncSwapRouter public router;
    IERC20 public usdc;
    IERC20 public usdt;

    // We'll deposit 100 USDC and 100 USDT
    // Increase these if the pool reverts for insufficient liquidity
    uint256 constant USDC_AMOUNT = 100e6; // 100 USDC
    uint256 constant USDT_AMOUNT = 100e6; // 100 USDT

    function setUp() public {
        // 1. Create a test user and fund with ETH for gas
        testUser = makeAddr("testUser");
        vm.deal(testUser, 10 ether);

        // 2. Initialize contract interfaces
        router = ISyncSwapRouter(ROUTER_ADDRESS);
        usdc   = IERC20(USDC_ADDRESS);
        usdt   = IERC20(USDT_ADDRESS);

        // 3. Give the user some USDC and USDT (using Foundry's deal cheatcode)
        // Increase these if you need more for the pool
        deal(USDC_ADDRESS, testUser, 1_000e6); // 1,000 USDC
        deal(USDT_ADDRESS, testUser, 1_000e6); // 1,000 USDT

        console.log("=== setUp() Complete ===");
        console.log("User address:", testUser);
        console.log("User USDC balance:", usdc.balanceOf(testUser));
        console.log("User USDT balance:", usdt.balanceOf(testUser));
    }

    function testAddLiquidityStablePool() public {
        console.log("=== Testing SyncSwap Stable Pool Liquidity Provision (USDC/USDT) ===");

        // Check user's initial USDC/USDT balances
        uint256 initialUSDC = usdc.balanceOf(testUser);
        uint256 initialUSDT = usdt.balanceOf(testUser);
        console.log("Initial USDC balance:", initialUSDC);
        console.log("Initial USDT balance:", initialUSDT);

        // Impersonate the testUser
        vm.startPrank(testUser);

        // Approve the router to spend USDC and USDT
        bool approvedUSDC = usdc.approve(ROUTER_ADDRESS, type(uint256).max);
        bool approvedUSDT = usdt.approve(ROUTER_ADDRESS, type(uint256).max);
        require(approvedUSDC && approvedUSDT, "Token approval failed");
        console.log("Approved router to spend USDC and USDT");

        // Prepare the TokenInput array for USDC and USDT
        ISyncSwapRouter.TokenInput[] memory inputs = new ISyncSwapRouter.TokenInput[](2);
        inputs[0] = ISyncSwapRouter.TokenInput({ token: USDC_ADDRESS, amount: USDC_AMOUNT });
        inputs[1] = ISyncSwapRouter.TokenInput({ token: USDT_ADDRESS, amount: USDT_AMOUNT });

        // Provide the stable pool's expected data (address recipient, uint8 withdrawMode)
        // Typically (testUser, 0) => the minted LP tokens go to testUser, withdrawMode = 0
        bytes memory data = abi.encode(testUser, uint8(0));

        // No slippage protection for testing
        uint minLiquidity = 0;
        // No callback
        address callback = address(0);
        bytes memory callbackData = "";

        // Call addLiquidity on the router
        uint liquidityMinted = router.addLiquidity(
            STABLE_POOL_ADDRESS,
            inputs,
            data,
            minLiquidity,
            callback,
            callbackData
        );

        console.log("Liquidity minted (LP tokens):", liquidityMinted);

        vm.stopPrank();

        // Check final USDC and USDT balances
        uint256 finalUSDC = usdc.balanceOf(testUser);
        uint256 finalUSDT = usdt.balanceOf(testUser);
        console.log("Final USDC balance:", finalUSDC);
        console.log("Final USDT balance:", finalUSDT);
        console.log("USDC spent:", initialUSDC - finalUSDC);
        console.log("USDT spent:", initialUSDT - finalUSDT);

        // (Optional) If the pool contract is an ERC20, you can check the LP token balance:
        // IERC20 lpToken = IERC20(STABLE_POOL_ADDRESS);
        // uint256 lpBalance = lpToken.balanceOf(testUser);
        // console.log("LP token balance of testUser:", lpBalance);
    }
}