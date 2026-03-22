// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RevToken} from "./RevToken.sol";

/// @title AuctionFactory – Create & settle future-revenue auctions tied to ENS names
/// @notice Protocols/merchants identified by ENS name auction off claims to future stablecoin revenue.
///         Investors bid, the highest bidder wins, and RevTokens are minted as proof of their claim.
/// @dev    Simple highest-bid-wins model for hackathon MVP. Inspired by Cherry 🍒.
contract AuctionFactory {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionCreated(uint256 indexed auctionId, string ensName, address seller, address revToken);
    event BidPlaced(uint256 indexed auctionId, address bidder, uint256 amount);
    event AuctionFinalized(uint256 indexed auctionId, address winner, uint256 winningBid, uint256 tokensMinted);

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Auction {
        /// @notice ENS name of the seller (e.g. "myshop.eth")
        string ensName;
        /// @notice Description of the revenue stream being auctioned
        string description;
        /// @notice Address of the seller
        address seller;
        /// @notice The RevToken contract for this auction
        address revToken;
        /// @notice Stablecoin used for bidding and revenue settlement
        address stablecoin;
        /// @notice Total RevTokens to mint to the winning bidder
        uint256 totalTokens;
        /// @notice Auction end timestamp
        uint256 deadline;
        /// @notice Current highest bid amount (in stablecoin)
        uint256 highestBid;
        /// @notice Current highest bidder
        address highestBidder;
        /// @notice Whether the auction has been finalized
        bool finalized;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice All auctions by ID
    mapping(uint256 => Auction) public auctions;

    /// @notice Auto-incrementing auction counter
    uint256 public nextAuctionId;

    /// @notice Mapping from ENS name hash to list of auction IDs (for lookups)
    mapping(bytes32 => uint256[]) public auctionsByEns;

    /*//////////////////////////////////////////////////////////////
                             AUCTION LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new revenue auction tied to an ENS identity.
    /// @param ensName     The seller's ENS name (e.g. "myshop.eth")
    /// @param description Human-readable description of the revenue stream
    /// @param stablecoin  Address of the stablecoin for bidding/settlement (e.g. USDC)
    /// @param totalTokens Number of RevTokens to mint (represents 100% of auctioned share)
    /// @param duration    Auction duration in seconds
    /// @return auctionId  The ID of the newly created auction
    function createAuction(
        string calldata ensName,
        string calldata description,
        address stablecoin,
        uint256 totalTokens,
        uint256 duration
    ) external returns (uint256 auctionId) {
        require(bytes(ensName).length > 0, "AuctionFactory: empty ENS name");
        require(totalTokens > 0, "AuctionFactory: zero tokens");
        require(duration > 0, "AuctionFactory: zero duration");

        auctionId = nextAuctionId++;

        // Build token name & symbol from ENS name
        string memory tokenName = string.concat("RevStream: ", ensName);
        string memory tokenSymbol = string.concat("REV-", _truncate(ensName, 8));

        // Deploy a dedicated RevToken for this auction
        RevToken revToken = new RevToken(tokenName, tokenSymbol, stablecoin, msg.sender, address(this));

        auctions[auctionId] = Auction({
            ensName: ensName,
            description: description,
            seller: msg.sender,
            revToken: address(revToken),
            stablecoin: stablecoin,
            totalTokens: totalTokens,
            deadline: block.timestamp + duration,
            highestBid: 0,
            highestBidder: address(0),
            finalized: false
        });

        // Index by ENS name hash for on-chain lookups
        auctionsByEns[keccak256(bytes(ensName))].push(auctionId);

        emit AuctionCreated(auctionId, ensName, msg.sender, address(revToken));
    }

    /// @notice Place a bid on an active auction. Requires stablecoin approval.
    ///         If outbid, the previous highest bidder is refunded automatically.
    /// @param auctionId The auction to bid on
    /// @param amount    The bid amount in stablecoin
    function bid(uint256 auctionId, uint256 amount) external {
        Auction storage a = auctions[auctionId];
        require(a.seller != address(0), "AuctionFactory: invalid auction");
        require(block.timestamp < a.deadline, "AuctionFactory: auction ended");
        require(!a.finalized, "AuctionFactory: already finalized");
        require(amount > a.highestBid, "AuctionFactory: bid too low");

        IERC20 coin = IERC20(a.stablecoin);

        // Refund previous highest bidder
        if (a.highestBidder != address(0)) {
            coin.safeTransfer(a.highestBidder, a.highestBid);
        }

        // Pull new bid from bidder
        coin.safeTransferFrom(msg.sender, address(this), amount);

        a.highestBid = amount;
        a.highestBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, amount);
    }

    /// @notice Finalize an auction after the deadline. Mints RevTokens to the winner
    ///         and sends the winning bid to the seller.
    /// @param auctionId The auction to finalize
    function finalize(uint256 auctionId) external {
        Auction storage a = auctions[auctionId];
        require(a.seller != address(0), "AuctionFactory: invalid auction");
        require(block.timestamp >= a.deadline, "AuctionFactory: not ended yet");
        require(!a.finalized, "AuctionFactory: already finalized");
        require(a.highestBidder != address(0), "AuctionFactory: no bids");

        a.finalized = true;

        // Send winning bid to the seller (this is the upfront capital they receive)
        IERC20(a.stablecoin).safeTransfer(a.seller, a.highestBid);

        // Mint RevTokens to the winner
        RevToken(a.revToken).mint(a.highestBidder, a.totalTokens);

        emit AuctionFinalized(auctionId, a.highestBidder, a.highestBid, a.totalTokens);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get all auction IDs for a given ENS name.
    function getAuctionsByEns(string calldata ensName) external view returns (uint256[] memory) {
        return auctionsByEns[keccak256(bytes(ensName))];
    }

    /// @notice Get full auction details.
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Truncate a string to maxLen bytes (for symbol generation).
    function _truncate(string memory s, uint256 maxLen) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length <= maxLen) return s;
        bytes memory result = new bytes(maxLen);
        for (uint256 i = 0; i < maxLen; i++) {
            result[i] = b[i];
        }
        return string(result);
    }
}
