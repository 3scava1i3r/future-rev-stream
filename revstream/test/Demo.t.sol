// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {RevToken} from "../src/RevToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RevStream Fork Demo
/// @notice Demonstrates the full RevStream lifecycle on a mainnet fork using real USDC.
/// @dev    Run with:
///         forge test --match-test test_demo --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY -vvv
contract DemoTest is Test {
    // ── Mainnet USDC ──
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // ── Mainnet USDC whale ──
    address constant WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;

    address seller = makeAddr("seller");
    address investor = makeAddr("investor");
    address customer = makeAddr("customer");

    function test_demo() public {
        console2.log("=======================================================");
        console2.log("  RevStream - Future Revenue Marketplace Demo");
        console2.log("=======================================================");
        console2.log("");

        // ── Step 0: Seed USDC from mainnet whale ──
        console2.log("[0] Seeding demo accounts with USDC from whale...");
        vm.startPrank(WHALE);
        IERC20(USDC).transfer(investor, 500_000e6);
        IERC20(USDC).transfer(customer, 500_000e6);
        vm.stopPrank();
        console2.log("    Investor USDC:", IERC20(USDC).balanceOf(investor) / 1e6);
        console2.log("    Customer USDC:", IERC20(USDC).balanceOf(customer) / 1e6);
        console2.log("");

        // ── Step 1: Deploy AuctionFactory ──
        console2.log("[1] Deploying AuctionFactory...");
        AuctionFactory factory = new AuctionFactory();
        console2.log("    Factory deployed at:", address(factory));
        console2.log("");

        // ── Step 2: Create auction for "myshop.eth" ──
        console2.log("[2] Creating auction for myshop.eth...");
        console2.log("    Seller:       ", seller);
        console2.log("    Description:   Q2 2026 stablecoin revenue");
        console2.log("    Total tokens:  1,000,000 REV");
        console2.log("    Duration:      1 day");

        vm.prank(seller);
        uint256 auctionId = factory.createAuction(
            "myshop.eth",
            "Q2 2026 stablecoin revenue from myshop.eth payment processing",
            USDC,
            1_000_000e18,
            1 days
        );

        AuctionFactory.Auction memory a = factory.getAuction(auctionId);
        console2.log("    Auction ID:   ", auctionId);
        console2.log("    RevToken at:  ", a.revToken);
        console2.log("");

        // ── Step 3: Investor places a bid ──
        uint256 bidAmount = 50_000e6;
        console2.log("[3] Investor placing bid of 50,000 USDC...");
        console2.log("    Investor:     ", investor);

        vm.startPrank(investor);
        IERC20(USDC).approve(address(factory), bidAmount);
        factory.bid(auctionId, bidAmount);
        vm.stopPrank();

        a = factory.getAuction(auctionId);
        console2.log("    Highest bid:  ", a.highestBid / 1e6, "USDC");
        console2.log("    Bidder:       ", a.highestBidder);
        console2.log("");

        // ── Step 4: Fast-forward & finalize auction ──
        console2.log("[4] Fast-forwarding past auction deadline...");
        vm.warp(block.timestamp + 1 days + 1);
        factory.finalize(auctionId);

        RevToken rev = RevToken(a.revToken);
        console2.log("    Auction finalized!");
        console2.log("    Seller received:     ", IERC20(USDC).balanceOf(seller) / 1e6, "USDC");
        console2.log("    Investor RevTokens:  ", rev.balanceOf(investor) / 1e18, "REV");
        console2.log("");

        // ── Step 5: Simulate revenue deposit ──
        uint256 revenue = 10_000e6;
        console2.log("[5] Simulating revenue: customer pays 10,000 USDC...");
        console2.log("    Customer:     ", customer);

        vm.startPrank(customer);
        IERC20(USDC).approve(address(rev), revenue);
        rev.depositRevenue(revenue);
        vm.stopPrank();

        console2.log("    Revenue deposited for epoch 0");
        console2.log("    Epoch revenue: ", rev.epochRevenue(0) / 1e6, "USDC");
        console2.log("");

        // ── Step 6: Investor claims their share ──
        uint256 claimableAmt = rev.claimable(0, investor);
        console2.log("[6] Investor claiming revenue share...");
        console2.log("    Claimable:    ", claimableAmt / 1e6, "USDC");

        uint256 balBefore = IERC20(USDC).balanceOf(investor);
        vm.prank(investor);
        rev.claim(0);
        uint256 balAfter = IERC20(USDC).balanceOf(investor);

        console2.log("    Claimed!      ", (balAfter - balBefore) / 1e6, "USDC received");
        console2.log("");

        // ── Assertions ──
        assertEq(IERC20(USDC).balanceOf(seller), 50_000e6, "Seller should have bid amount");
        assertEq(rev.balanceOf(investor), 1_000_000e18, "Investor should have RevTokens");
        assertEq(balAfter - balBefore, 10_000e6, "Investor should have claimed all revenue");

        console2.log("=======================================================");
        console2.log("  Demo complete! RevStream lifecycle demonstrated.");
        console2.log("=======================================================");
        console2.log("");
        console2.log("  Summary:");
        console2.log("  - myshop.eth auctioned Q2 2026 revenue");
        console2.log("  - Investor won auction for 50,000 USDC");
        console2.log("  - 10,000 USDC revenue deposited");
        console2.log("  - Investor claimed 10,000 USDC (100% share)");
        console2.log("  - ENS name tied to auction metadata on-chain");
        console2.log("=======================================================");
    }
}
