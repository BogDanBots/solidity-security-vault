// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "./MockERC20.sol";

/// @dev Test-only token that credits a configurable fee to a sink address.
contract FeeOnTransferToken is MockERC20 {
    error FeeTooHigh();

    uint256 public immutable feeBps;
    address public constant FEE_SINK = address(0xFEE);

    constructor(uint256 feeBps_) {
        if (feeBps_ > 10_000) revert FeeTooHigh();
        feeBps = feeBps_;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _moveWithFee(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 approved = allowance[from][msg.sender];
        require(approved >= amount, "allowance");
        allowance[from][msg.sender] = approved - amount;
        _moveWithFee(from, to, amount);
        return true;
    }

    function _moveWithFee(address from, address to, uint256 amount) internal {
        uint256 fee = (amount * feeBps) / 10_000;
        _move(from, to, amount - fee);
        if (fee != 0) _move(from, FEE_SINK, fee);
    }
}
