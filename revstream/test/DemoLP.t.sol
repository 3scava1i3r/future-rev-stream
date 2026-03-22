// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AuctionFactoryLP} from "../src/AuctionFactoryLP.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @dev Minimal interface for Uniswap V3 NonfungiblePositionManager
interface INonfungiblePositionManager is IERC721 {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title RevStream LP Auction Fork Demo
/// @notice Demonstrates the full LP auction lifecycle on a mainnet fork:
///         mint a real Uniswap V3 position, auction the NFT for USDC, transfer to winner.
/// @dev    Run with:
///         forge test --match-test test_lp_demo --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY -vvv
contract DemoLPTest is Test {
    // ── Mainnet addresses ──
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNI_V3_NPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;

    // USDC/WETH 0.3% pool — USDC is token0 (lower address)
    uint24 constant POOL_FEE = 3000;
    // Wide tick range for demo (≈ $500 – $10,000 range)
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    address seller = makeAddr("lpSeller");
    address investor = makeAddr("investor");

    function test_lp_demo() public {
        INonfungiblePositionManager npm = INonfungiblePositionManager(UNI_V3_NPM);

        console2.log("=======================================================");
        console2.log("  RevStream LP Auction - Mainnet Fork Demo");
        console2.log("=======================================================");
        console2.log("");

        // ── Step 0: Seed seller with WETH + USDC to create LP position ──
        console2.log("[0] Seeding seller with ETH & USDC...");
        vm.deal(seller, 10 ether);
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(seller, 20_000e6);

        vm.startPrank(seller);
        IWETH(WETH).deposit{value: 5 ether}();
        vm.stopPrank();

        console2.log("    Seller WETH: ", IERC20(WETH).balanceOf(seller) / 1e18, "ETH");
        console2.log("    Seller USDC: ", IERC20(USDC).balanceOf(seller) / 1e6, "USDC");
        console2.log("");

        // ── Step 1: Seller mints a Uniswap V3 LP position ──
        console2.log("[1] Minting Uniswap V3 USDC/WETH LP position...");
        vm.startPrank(seller);
        IERC20(USDC).approve(UNI_V3_NPM, 20_000e6);
        IERC20(WETH).approve(UNI_V3_NPM, 5 ether);

        (uint256 nftId, uint128 liquidity,,) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: WETH,
                fee: POOL_FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: 10_000e6,
                amount1Desired: 2 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: seller,
                deadline: block.timestamp + 300
            })
        );
        vm.stopPrank();

        console2.log("    LP NFT ID:   ", nftId);
        console2.log("    Liquidity:   ", uint256(liquidity));
        console2.log("    Owner:       ", npm.ownerOf(nftId));
        console2.log("");

        // ── Step 2: Seed investor with USDC for bidding ──
        console2.log("[2] Seeding investor with USDC...");
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(investor, 500_000e6);
        console2.log("    Investor USDC:", IERC20(USDC).balanceOf(investor) / 1e6);
        console2.log("");

        // ── Step 3: Deploy AuctionFactoryLP & create auction ──
        console2.log("[3] Deploying AuctionFactoryLP & creating auction...");
        AuctionFactoryLP factory = new AuctionFactoryLP();
        console2.log("    Factory at:  ", address(factory));

        vm.startPrank(seller);
        npm.approve(address(factory), nftId);
        uint256 auctionId = factory.createLPAuction(
            "lptrader.eth",
            UNI_V3_NPM,
            nftId,
            USDC,
            5_000e6, // min bid: 5k USDC
            1 days
        );
        vm.stopPrank();

        AuctionFactoryLP.LPAuction memory a = factory.getAuction(auctionId);
        console2.log("    Auction ID:  ", auctionId);
        console2.log("    ENS name:     lptrader.eth");
        console2.log("    LP NFT:      ", a.nftId);
        console2.log("    Min bid:     ", a.minBid / 1e6, "USDC");
        console2.log("    NFT escrowed: ", npm.ownerOf(nftId) == address(factory) ? "YES" : "NO");
        console2.log("");

        // ── Step 4: Investor places a bid ──
        uint256 bidAmount = 8_000e6;
        console2.log("[4] Investor bidding 8,000 USDC...");

        vm.startPrank(investor);
        IERC20(USDC).approve(address(factory), bidAmount);
        factory.bid(auctionId, bidAmount);
        vm.stopPrank();

        a = factory.getAuction(auctionId);
        console2.log("    Highest bid: ", a.highestBid / 1e6, "USDC");
        console2.log("    Bidder:      ", a.highestBidder);
        console2.log("");

        // ── Step 5: Fast-forward & finalize ──
        console2.log("[5] Fast-forwarding past deadline & finalizing...");
        vm.warp(block.timestamp + 1 days + 1);
        factory.finalize(auctionId);

        console2.log("    Auction finalized!");
        console2.log("    Seller received: ", IERC20(USDC).balanceOf(seller) / 1e6, "USDC");
        console2.log("    NFT new owner:   ", npm.ownerOf(nftId));
        console2.log("");

        // ── Assertions ──
        assertEq(npm.ownerOf(nftId), investor, "Investor should own the LP NFT");
        assertGt(IERC20(USDC).balanceOf(seller), 0, "Seller should have received USDC");

        // Verify the position still has liquidity
        (,,,,,,,uint128 posLiquidity,,,,) = npm.positions(nftId);
        assertGt(uint256(posLiquidity), 0, "LP position should still have liquidity");
        console2.log("    Position liquidity:", uint256(posLiquidity));
        console2.log("");

        console2.log("=======================================================");
        console2.log("  LP Auction Demo Complete!");
        console2.log("=======================================================");
        console2.log("");
        console2.log("  Summary:");
        console2.log("  - lptrader.eth minted a real Uniswap V3 USDC/WETH position");
        console2.log("  - Escrowed LP NFT into AuctionFactoryLP");
        console2.log("  - Investor won auction for 8,000 USDC");
        console2.log("  - Seller got immediate stablecoin liquidity");
        console2.log("  - Investor now owns the LP NFT + all future fees");
        console2.log("  - ENS name 'lptrader.eth' tied to auction on-chain");
        console2.log("=======================================================");
    }
}
