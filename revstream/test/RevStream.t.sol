// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AuctionFactory} from "../src/AuctionFactory.sol";
import {RevToken} from "../src/RevToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mock stablecoin for unit tests
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract RevStreamTest is Test {
    AuctionFactory factory;
    MockUSDC usdc;

    address seller = makeAddr("seller");
    address investor1 = makeAddr("investor1");
    address investor2 = makeAddr("investor2");
    address customer = makeAddr("customer");

    uint256 constant TOTAL_TOKENS = 1_000_000e18; // 1M RevTokens
    uint256 constant AUCTION_DURATION = 1 days;

    function setUp() public {
        factory = new AuctionFactory();
        usdc = new MockUSDC();

        // Give investors & customer some USDC
        usdc.mint(investor1, 100_000e6);
        usdc.mint(investor2, 200_000e6);
        usdc.mint(customer, 500_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                          AUCTION CREATION
    //////////////////////////////////////////////////////////////*/

    function test_createAuction() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2 2026 revenue", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        AuctionFactory.Auction memory a = factory.getAuction(id);
        assertEq(a.seller, seller);
        assertEq(keccak256(bytes(a.ensName)), keccak256("myshop.eth"));
        assertEq(a.totalTokens, TOTAL_TOKENS);
        assertFalse(a.finalized);
    }

    function test_createAuction_emptyEns_reverts() public {
        vm.expectRevert("AuctionFactory: empty ENS name");
        factory.createAuction("", "desc", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);
    }

    function test_getAuctionsByEns() public {
        vm.prank(seller);
        factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);
        vm.prank(seller);
        factory.createAuction("myshop.eth", "Q3", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        uint256[] memory ids = factory.getAuctionsByEns("myshop.eth");
        assertEq(ids.length, 2);
    }

    /*//////////////////////////////////////////////////////////////
                              BIDDING
    //////////////////////////////////////////////////////////////*/

    function test_bid() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        AuctionFactory.Auction memory a = factory.getAuction(id);
        assertEq(a.highestBidder, investor1);
        assertEq(a.highestBid, 50_000e6);
    }

    function test_bid_outbid_refunds() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        // Investor1 bids 50k
        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        // Investor2 outbids with 80k
        vm.prank(investor2);
        usdc.approve(address(factory), 80_000e6);
        vm.prank(investor2);
        factory.bid(id, 80_000e6);

        // Investor1 should be refunded
        assertEq(usdc.balanceOf(investor1), 100_000e6);
        // Investor2's balance reduced
        assertEq(usdc.balanceOf(investor2), 120_000e6);
    }

    function test_bid_tooLow_reverts() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        vm.prank(investor2);
        usdc.approve(address(factory), 30_000e6);
        vm.expectRevert("AuctionFactory: bid too low");
        vm.prank(investor2);
        factory.bid(id, 30_000e6);
    }

    function test_bid_afterDeadline_reverts() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.expectRevert("AuctionFactory: auction ended");
        vm.prank(investor1);
        factory.bid(id, 50_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_finalize() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        factory.finalize(id);

        AuctionFactory.Auction memory a = factory.getAuction(id);
        assertTrue(a.finalized);

        // Seller received the bid
        assertEq(usdc.balanceOf(seller), 50_000e6);

        // Winner got RevTokens
        RevToken rev = RevToken(a.revToken);
        assertEq(rev.balanceOf(investor1), TOTAL_TOKENS);
    }

    function test_finalize_tooEarly_reverts() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        vm.expectRevert("AuctionFactory: not ended yet");
        factory.finalize(id);
    }

    /*//////////////////////////////////////////////////////////////
                        REVENUE DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    function test_depositAndClaim() public {
        // Setup: create auction, bid, finalize
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        factory.finalize(id);

        AuctionFactory.Auction memory a = factory.getAuction(id);
        RevToken rev = RevToken(a.revToken);

        // Simulate revenue: customer pays 10k USDC as revenue
        uint256 revenue = 10_000e6;
        vm.prank(customer);
        usdc.approve(address(rev), revenue);
        vm.prank(customer);
        rev.depositRevenue(revenue);

        // Investor1 holds 100% of tokens => can claim 100% of revenue
        uint256 claimableAmount = rev.claimable(0, investor1);
        assertEq(claimableAmount, revenue);

        uint256 balBefore = usdc.balanceOf(investor1);
        vm.prank(investor1);
        rev.claim(0);
        assertEq(usdc.balanceOf(investor1) - balBefore, revenue);
    }

    function test_doubleClaim_reverts() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        factory.finalize(id);

        AuctionFactory.Auction memory a = factory.getAuction(id);
        RevToken rev = RevToken(a.revToken);

        vm.prank(customer);
        usdc.approve(address(rev), 10_000e6);
        vm.prank(customer);
        rev.depositRevenue(10_000e6);

        vm.prank(investor1);
        rev.claim(0);

        vm.expectRevert("RevToken: already claimed");
        vm.prank(investor1);
        rev.claim(0);
    }

    function test_multipleHolders_proRata() public {
        vm.prank(seller);
        uint256 id = factory.createAuction("myshop.eth", "Q2", address(usdc), TOTAL_TOKENS, AUCTION_DURATION);

        vm.prank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.prank(investor1);
        factory.bid(id, 50_000e6);

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        factory.finalize(id);

        AuctionFactory.Auction memory a = factory.getAuction(id);
        RevToken rev = RevToken(a.revToken);

        // Investor1 transfers 40% of tokens to investor2
        vm.prank(investor1);
        rev.transfer(investor2, (TOTAL_TOKENS * 40) / 100);

        // Deposit 100k revenue
        uint256 revenue = 100_000e6;
        vm.prank(customer);
        usdc.approve(address(rev), revenue);
        vm.prank(customer);
        rev.depositRevenue(revenue);

        // Investor1 should get 60%, investor2 should get 40%
        assertEq(rev.claimable(0, investor1), 60_000e6);
        assertEq(rev.claimable(0, investor2), 40_000e6);

        vm.prank(investor1);
        rev.claim(0);
        vm.prank(investor2);
        rev.claim(0);

        // Verify balances (investor1 started with 100k, paid 50k bid, got 60k revenue)
        assertEq(usdc.balanceOf(investor1), 50_000e6 + 60_000e6);
        assertEq(usdc.balanceOf(investor2), 200_000e6 + 40_000e6);
    }
}
