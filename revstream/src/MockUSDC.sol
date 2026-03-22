// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC – Test stablecoin for XRPL EVM demos
/// @notice Mintable ERC-20 with 6 decimals simulating USDC on XRPL EVM Sidechain.
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin (XRPL)", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
