// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RevToken – Future Revenue Share Token
/// @notice ERC-20 token representing a pro-rata claim on future stablecoin revenue.
///         Holders can claim their share of deposited revenue proportional to their balance.
contract RevToken is ERC20 {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RevenueDeposited(uint256 indexed epoch, uint256 amount, address depositor);
    event RevenueClaimed(uint256 indexed epoch, address indexed holder, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The stablecoin used for revenue settlement (e.g. USDC).
    IERC20 public immutable stablecoin;

    /// @notice Address of the seller (ENS-identified protocol/merchant).
    address public immutable seller;

    /// @notice The AuctionFactory that created this token.
    address public immutable factory;

    /// @notice Current revenue epoch (incremented each time new revenue is deposited).
    uint256 public currentEpoch;

    /// @notice Revenue amount deposited per epoch.
    mapping(uint256 epoch => uint256 amount) public epochRevenue;

    /// @notice Snapshot of total supply at each epoch (for pro-rata calculation).
    mapping(uint256 epoch => uint256 supply) public epochTotalSupply;

    /// @notice Tracks whether a holder has claimed for a given epoch.
    mapping(uint256 epoch => mapping(address holder => bool claimed)) public hasClaimed;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _name      Token name (e.g. "RevStream: myshop.eth Q2-2026")
    /// @param _symbol    Token symbol (e.g. "REV-MYSHOP-Q2")
    /// @param _stablecoin Address of the settlement stablecoin (USDC/USDT)
    /// @param _seller    Address of the revenue seller
    /// @param _factory   Address of the AuctionFactory
    constructor(
        string memory _name,
        string memory _symbol,
        address _stablecoin,
        address _seller,
        address _factory
    ) ERC20(_name, _symbol) {
        stablecoin = IERC20(_stablecoin);
        seller = _seller;
        factory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                            MINTING (FACTORY ONLY)
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint RevTokens to an investor. Only callable by the factory.
    /// @param to     Recipient address
    /// @param amount Number of tokens to mint
    function mint(address to, uint256 amount) external {
        require(msg.sender == factory, "RevToken: only factory");
        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          REVENUE DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit revenue (stablecoin) for the current epoch.
    ///         Typically called by the seller or an automated revenue router.
    /// @param amount Amount of stablecoin to deposit as revenue
    function depositRevenue(uint256 amount) external {
        require(amount > 0, "RevToken: zero amount");
        require(totalSupply() > 0, "RevToken: no holders");

        uint256 epoch = currentEpoch++;

        epochRevenue[epoch] = amount;
        epochTotalSupply[epoch] = totalSupply();

        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        emit RevenueDeposited(epoch, amount, msg.sender);
    }

    /// @notice Claim your pro-rata share of revenue for a given epoch.
    /// @param epoch The epoch to claim from
    function claim(uint256 epoch) external {
        require(epoch < currentEpoch, "RevToken: epoch not finalized");
        require(!hasClaimed[epoch][msg.sender], "RevToken: already claimed");
        require(balanceOf(msg.sender) > 0, "RevToken: no balance");

        hasClaimed[epoch][msg.sender] = true;

        uint256 holderShare = (epochRevenue[epoch] * balanceOf(msg.sender)) / epochTotalSupply[epoch];
        require(holderShare > 0, "RevToken: nothing to claim");

        stablecoin.safeTransfer(msg.sender, holderShare);

        emit RevenueClaimed(epoch, msg.sender, holderShare);
    }

    /// @notice View how much a holder can claim for a given epoch.
    /// @param epoch  The epoch to query
    /// @param holder The address to check
    /// @return The claimable stablecoin amount
    function claimable(uint256 epoch, address holder) external view returns (uint256) {
        if (epoch >= currentEpoch) return 0;
        if (hasClaimed[epoch][holder]) return 0;
        if (epochTotalSupply[epoch] == 0) return 0;

        return (epochRevenue[epoch] * balanceOf(holder)) / epochTotalSupply[epoch];
    }
}
