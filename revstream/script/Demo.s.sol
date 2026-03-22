// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {RevToken} from "../src/RevToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RevStream Demo Script
/// @notice Run on an Anvil fork of Ethereum mainnet or Base to demonstrate the full lifecycle.
/// @dev    Uses real USDC on the fork. Run with:
///
///         # Terminal 1: Start Anvil fork
///         anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY --fork-block-number 21000000
///
///         # Terminal 2: Run demo
///         forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
///
contract Demo is Script {
    // ── Mainnet USDC address ──
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // ── Demo actors (Anvil default accounts) ──
    uint256 constant SELLER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant INVESTOR_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant CUSTOMER_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    address seller;
    address investor;
    address customer;

    function run() external {
        seller = vm.addr(SELLER_KEY);
        investor = vm.addr(INVESTOR_KEY);
        customer = vm.addr(CUSTOMER_KEY);

        console2.log("=======================================================");
        console2.log("  RevStream - Future Revenue Marketplace Demo");
        console2.log("=======================================================");
        console2.log("");

        // ── Step 0: Seed USDC to demo accounts ──
        // On a fork we impersonate a USDC whale to distribute tokens
        _seedAccounts();

        // ── Step 1: Deploy AuctionFactory ──
        console2.log("[1] Deploying AuctionFactory...");
        vm.startBroadcast(SELLER_KEY);
        AuctionFactory factory = new AuctionFactory();
        vm.stopBroadcast();
        console2.log("    Factory deployed at:", address(factory));
        console2.log("");

        // ── Step 2: Create auction for "myshop.eth" ──
        console2.log("[2] Creating auction for myshop.eth...");
        console2.log("    Seller:      ", seller);
        console2.log("    Description:  Q2 2026 stablecoin revenue");
        console2.log("    Total tokens: 1,000,000 REV");
        console2.log("    Duration:     1 day");

        vm.startBroadcast(SELLER_KEY);
        uint256 auctionId = factory.createAuction(
            "myshop.eth",
            "Q2 2026 stablecoin revenue from myshop.eth payment processing",
            USDC,
            1_000_000e18, // 1M RevTokens
            1 days
        );
        vm.stopBroadcast();

        AuctionFactory.Auction memory a = factory.getAuction(auctionId);
        console2.log("    Auction ID:  ", auctionId);
        console2.log("    RevToken at: ", a.revToken);
        console2.log("");

        // ── Step 3: Investor places a bid ──
        uint256 bidAmount = 50_000e6; // 50k USDC
        console2.log("[3] Investor placing bid of 50,000 USDC...");
        console2.log("    Investor:    ", investor);

        vm.startBroadcast(INVESTOR_KEY);
        IERC20(USDC).approve(address(factory), bidAmount);
        factory.bid(auctionId, bidAmount);
        vm.stopBroadcast();

        a = factory.getAuction(auctionId);
        console2.log("    Highest bid: ", a.highestBid / 1e6, "USDC");
        console2.log("    Bidder:      ", a.highestBidder);
        console2.log("");

        // ── Step 4: Fast-forward & finalize auction ──
        console2.log("[4] Fast-forwarding past auction deadline...");
        vm.warp(block.timestamp + 1 days + 1);

        vm.startBroadcast(SELLER_KEY);
        factory.finalize(auctionId);
        vm.stopBroadcast();

        RevToken rev = RevToken(a.revToken);
        console2.log("    Auction finalized!");
        console2.log("    Seller received:     ", IERC20(USDC).balanceOf(seller) / 1e6, "USDC");
        console2.log("    Investor RevTokens:  ", rev.balanceOf(investor) / 1e18, "REV");
        console2.log("");

        // ── Step 5: Simulate revenue deposit ──
        uint256 revenue = 10_000e6; // 10k USDC
        console2.log("[5] Simulating revenue: customer pays 10,000 USDC...");
        console2.log("    Customer:    ", customer);

        vm.startBroadcast(CUSTOMER_KEY);
        IERC20(USDC).approve(address(rev), revenue);
        rev.depositRevenue(revenue);
        vm.stopBroadcast();

        console2.log("    Revenue deposited for epoch 0");
        console2.log("    Epoch revenue: ", rev.epochRevenue(0) / 1e6, "USDC");
        console2.log("");

        // ── Step 6: Investor claims their share ──
        uint256 claimableAmt = rev.claimable(0, investor);
        console2.log("[6] Investor claiming revenue share...");
        console2.log("    Claimable:   ", claimableAmt / 1e6, "USDC");

        uint256 balBefore = IERC20(USDC).balanceOf(investor);
        vm.startBroadcast(INVESTOR_KEY);
        rev.claim(0);
        vm.stopBroadcast();

        uint256 balAfter = IERC20(USDC).balanceOf(investor);
        console2.log("    Claimed!     ", (balAfter - balBefore) / 1e6, "USDC received");
        console2.log("");

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

    /// @dev Impersonate a USDC whale to seed demo accounts
    function _seedAccounts() internal {
        // Mainnet USDC whale (Circle/Coinbase hot wallet)
        address whale = 0x55FE002aefF02F77364de339a1292923A15844B8;

        console2.log("[0] Seeding demo accounts with USDC from whale...");

        vm.startPrank(whale);
        IERC20(USDC).transfer(investor, 500_000e6);
        IERC20(USDC).transfer(customer, 500_000e6);
        vm.stopPrank();

        console2.log("    Investor USDC:", IERC20(USDC).balanceOf(investor) / 1e6);
        console2.log("    Customer USDC:", IERC20(USDC).balanceOf(customer) / 1e6);
        console2.log("");
    }
}
