// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title AuctionFactoryLP – Auction LP Position NFTs for immediate stablecoin liquidity
/// @notice LP holders escrow their position NFT (e.g. Uniswap V3) and auction it for USDC.
///         Highest bidder wins the NFT + all future fee accrual. Seller gets stablecoins now.
/// @dev    Simple highest-bid-wins model for hackathon MVP.
contract AuctionFactoryLP is IERC721Receiver {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event LPAuctionCreated(uint256 indexed auctionId, string ensName, address seller, address nftContract, uint256 nftId);
    event LPBidPlaced(uint256 indexed auctionId, address bidder, uint256 amount);
    event LPAuctionFinalized(uint256 indexed auctionId, address winner, uint256 winningBid);
    event LPAuctionCancelled(uint256 indexed auctionId);

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct LPAuction {
        /// @notice ENS name of the seller (e.g. "myshop.eth")
        string ensName;
        /// @notice Address of the seller
        address seller;
        /// @notice LP NFT contract address (e.g. Uniswap V3 NonfungiblePositionManager)
        address nftContract;
        /// @notice Token ID of the LP position NFT
        uint256 nftId;
        /// @notice Stablecoin used for bidding (e.g. USDC)
        address stablecoin;
        /// @notice Minimum bid amount
        uint256 minBid;
        /// @notice Auction end timestamp
        uint256 deadline;
        /// @notice Current highest bid amount (in stablecoin)
        uint256 highestBid;
        /// @notice Current highest bidder
        address highestBidder;
        /// @notice Whether the auction has been finalized or cancelled
        bool settled;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice All LP auctions by ID
    mapping(uint256 => LPAuction) public auctions;

    /// @notice Auto-incrementing auction counter
    uint256 public nextAuctionId;

    /// @notice Mapping from ENS name hash to list of auction IDs
    mapping(bytes32 => uint256[]) public auctionsByEns;

    /*//////////////////////////////////////////////////////////////
                             AUCTION LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new LP position auction. Caller must approve this contract for the NFT first.
    /// @param ensName     The seller's ENS name (e.g. "myshop.eth")
    /// @param nftContract Address of the LP NFT contract (e.g. Uniswap V3 PositionManager)
    /// @param nftId       Token ID of the LP position NFT to auction
    /// @param stablecoin  Address of the stablecoin for bidding (e.g. USDC)
    /// @param minBid      Minimum bid amount in stablecoin
    /// @param duration    Auction duration in seconds
    /// @return auctionId  The ID of the newly created auction
    function createLPAuction(
        string calldata ensName,
        address nftContract,
        uint256 nftId,
        address stablecoin,
        uint256 minBid,
        uint256 duration
    ) external returns (uint256 auctionId) {
        require(bytes(ensName).length > 0, "AuctionFactoryLP: empty ENS name");
        require(nftContract != address(0), "AuctionFactoryLP: zero nft address");
        require(duration > 0, "AuctionFactoryLP: zero duration");

        // Escrow the LP NFT from the seller
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), nftId);

        auctionId = nextAuctionId++;

        auctions[auctionId] = LPAuction({
            ensName: ensName,
            seller: msg.sender,
            nftContract: nftContract,
            nftId: nftId,
            stablecoin: stablecoin,
            minBid: minBid,
            deadline: block.timestamp + duration,
            highestBid: 0,
            highestBidder: address(0),
            settled: false
        });

        auctionsByEns[keccak256(bytes(ensName))].push(auctionId);

        emit LPAuctionCreated(auctionId, ensName, msg.sender, nftContract, nftId);
    }

    /// @notice Place a bid on an active LP auction. Requires stablecoin approval.
    ///         If outbid, the previous highest bidder is refunded automatically.
    /// @param auctionId The auction to bid on
    /// @param amount    The bid amount in stablecoin
    function bid(uint256 auctionId, uint256 amount) external {
        LPAuction storage a = auctions[auctionId];
        require(a.seller != address(0), "AuctionFactoryLP: invalid auction");
        require(block.timestamp < a.deadline, "AuctionFactoryLP: auction ended");
        require(!a.settled, "AuctionFactoryLP: already settled");
        require(amount >= a.minBid, "AuctionFactoryLP: below min bid");
        require(amount > a.highestBid, "AuctionFactoryLP: bid too low");

        IERC20 coin = IERC20(a.stablecoin);

        // Refund previous highest bidder
        if (a.highestBidder != address(0)) {
            coin.safeTransfer(a.highestBidder, a.highestBid);
        }

        // Pull new bid from bidder
        coin.safeTransferFrom(msg.sender, address(this), amount);

        a.highestBid = amount;
        a.highestBidder = msg.sender;

        emit LPBidPlaced(auctionId, msg.sender, amount);
    }

    /// @notice Finalize an auction after the deadline. Transfers LP NFT to winner
    ///         and sends the winning bid to the seller.
    /// @param auctionId The auction to finalize
    function finalize(uint256 auctionId) external {
        LPAuction storage a = auctions[auctionId];
        require(a.seller != address(0), "AuctionFactoryLP: invalid auction");
        require(block.timestamp >= a.deadline, "AuctionFactoryLP: not ended yet");
        require(!a.settled, "AuctionFactoryLP: already settled");
        require(a.highestBidder != address(0), "AuctionFactoryLP: no bids");

        a.settled = true;

        // Send winning bid to the seller
        IERC20(a.stablecoin).safeTransfer(a.seller, a.highestBid);

        // Transfer LP NFT to the winner
        IERC721(a.nftContract).safeTransferFrom(address(this), a.highestBidder, a.nftId);

        emit LPAuctionFinalized(auctionId, a.highestBidder, a.highestBid);
    }

    /// @notice Cancel an auction that received no bids. Returns NFT to seller.
    /// @param auctionId The auction to cancel
    function cancel(uint256 auctionId) external {
        LPAuction storage a = auctions[auctionId];
        require(a.seller != address(0), "AuctionFactoryLP: invalid auction");
        require(msg.sender == a.seller, "AuctionFactoryLP: not seller");
        require(!a.settled, "AuctionFactoryLP: already settled");
        require(a.highestBidder == address(0), "AuctionFactoryLP: has bids");

        a.settled = true;

        // Return LP NFT to seller
        IERC721(a.nftContract).safeTransferFrom(address(this), a.seller, a.nftId);

        emit LPAuctionCancelled(auctionId);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get all auction IDs for a given ENS name.
    function getAuctionsByEns(string calldata ensName) external view returns (uint256[] memory) {
        return auctionsByEns[keccak256(bytes(ensName))];
    }

    /// @notice Get full auction details.
    function getAuction(uint256 auctionId) external view returns (LPAuction memory) {
        return auctions[auctionId];
    }

    /*//////////////////////////////////////////////////////////////
                            ERC721 RECEIVER
    //////////////////////////////////////////////////////////////*/

    /// @dev Required to receive ERC-721 tokens via safeTransferFrom.
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
