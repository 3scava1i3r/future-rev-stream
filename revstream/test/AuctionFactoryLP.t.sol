// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AuctionFactoryLP} from "../src/AuctionFactoryLP.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

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

/// @dev Mock LP Position NFT for unit tests
contract MockLPNFT is ERC721 {
    uint256 private _nextId;

    constructor() ERC721("Uniswap V3 Positions", "UNI-V3-POS") {}

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _nextId++;
        _mint(to, tokenId);
    }
}

contract AuctionFactoryLPTest is Test {
    AuctionFactoryLP factory;
    MockUSDC usdc;
    MockLPNFT lpNft;

    address seller = makeAddr("seller");
    address investor1 = makeAddr("investor1");
    address investor2 = makeAddr("investor2");

    uint256 constant MIN_BID = 10_000e6; // 10k USDC
    uint256 constant AUCTION_DURATION = 1 days;

    uint256 nftId;

    function setUp() public {
        factory = new AuctionFactoryLP();
        usdc = new MockUSDC();
        lpNft = new MockLPNFT();

        // Mint LP NFT to seller
        nftId = lpNft.mint(seller);

        // Give investors USDC
        usdc.mint(investor1, 100_000e6);
        usdc.mint(investor2, 200_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                          AUCTION CREATION
    //////////////////////////////////////////////////////////////*/

    function test_createLPAuction() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        AuctionFactoryLP.LPAuction memory a = factory.getAuction(id);
        assertEq(a.seller, seller);
        assertEq(a.nftContract, address(lpNft));
        assertEq(a.nftId, nftId);
        assertEq(a.minBid, MIN_BID);
        assertFalse(a.settled);

        // NFT should be escrowed in the factory
        assertEq(lpNft.ownerOf(nftId), address(factory));
    }

    function test_createLPAuction_emptyEns_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        vm.expectRevert("AuctionFactoryLP: empty ENS name");
        factory.createLPAuction("", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();
    }

    function test_getAuctionsByEns() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        uint256 nftId2 = lpNft.mint(seller);
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId2);
        factory.createLPAuction("myshop.eth", address(lpNft), nftId2, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        uint256[] memory ids = factory.getAuctionsByEns("myshop.eth");
        assertEq(ids.length, 2);
    }

    /*//////////////////////////////////////////////////////////////
                               BIDDING
    //////////////////////////////////////////////////////////////*/

    function test_bid() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        factory.bid(id, 50_000e6);
        vm.stopPrank();

        AuctionFactoryLP.LPAuction memory a = factory.getAuction(id);
        assertEq(a.highestBidder, investor1);
        assertEq(a.highestBid, 50_000e6);
    }

    function test_bid_belowMinBid_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.startPrank(investor1);
        usdc.approve(address(factory), 5_000e6);
        vm.expectRevert("AuctionFactoryLP: below min bid");
        factory.bid(id, 5_000e6);
        vm.stopPrank();
    }

    function test_bid_outbid_refunds() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        // Investor1 bids 50k
        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        factory.bid(id, 50_000e6);
        vm.stopPrank();

        // Investor2 outbids with 80k
        vm.startPrank(investor2);
        usdc.approve(address(factory), 80_000e6);
        factory.bid(id, 80_000e6);
        vm.stopPrank();

        // Investor1 should be refunded
        assertEq(usdc.balanceOf(investor1), 100_000e6);
        assertEq(usdc.balanceOf(investor2), 120_000e6);
    }

    function test_bid_tooLow_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        factory.bid(id, 50_000e6);
        vm.stopPrank();

        vm.startPrank(investor2);
        usdc.approve(address(factory), 30_000e6);
        vm.expectRevert("AuctionFactoryLP: bid too low");
        factory.bid(id, 30_000e6);
        vm.stopPrank();
    }

    function test_bid_afterDeadline_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        vm.expectRevert("AuctionFactoryLP: auction ended");
        factory.bid(id, 50_000e6);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FINALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_finalize() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        factory.bid(id, 50_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        factory.finalize(id);

        AuctionFactoryLP.LPAuction memory a = factory.getAuction(id);
        assertTrue(a.settled);

        // Seller received the USDC
        assertEq(usdc.balanceOf(seller), 50_000e6);

        // Winner owns the LP NFT
        assertEq(lpNft.ownerOf(nftId), investor1);
    }

    function test_finalize_tooEarly_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        factory.bid(id, 50_000e6);
        vm.stopPrank();

        vm.expectRevert("AuctionFactoryLP: not ended yet");
        factory.finalize(id);
    }

    function test_finalize_noBids_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        vm.expectRevert("AuctionFactoryLP: no bids");
        factory.finalize(id);
    }

    /*//////////////////////////////////////////////////////////////
                            CANCELLATION
    //////////////////////////////////////////////////////////////*/

    function test_cancel() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        // NFT is escrowed
        assertEq(lpNft.ownerOf(nftId), address(factory));

        vm.prank(seller);
        factory.cancel(id);

        // NFT returned to seller
        assertEq(lpNft.ownerOf(nftId), seller);

        AuctionFactoryLP.LPAuction memory a = factory.getAuction(id);
        assertTrue(a.settled);
    }

    function test_cancel_notSeller_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.expectRevert("AuctionFactoryLP: not seller");
        vm.prank(investor1);
        factory.cancel(id);
    }

    function test_cancel_hasBids_reverts() public {
        vm.startPrank(seller);
        lpNft.approve(address(factory), nftId);
        uint256 id = factory.createLPAuction("myshop.eth", address(lpNft), nftId, address(usdc), MIN_BID, AUCTION_DURATION);
        vm.stopPrank();

        vm.startPrank(investor1);
        usdc.approve(address(factory), 50_000e6);
        factory.bid(id, 50_000e6);
        vm.stopPrank();

        vm.expectRevert("AuctionFactoryLP: has bids");
        vm.prank(seller);
        factory.cancel(id);
    }
}
