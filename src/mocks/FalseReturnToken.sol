// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "./MockERC20.sol";

/// @dev Test-only token that can return false from outgoing transfers.
contract FalseReturnToken is MockERC20 {
    bool public failTransfers;

    function setFailTransfers(bool fail) external {
        failTransfers = fail;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (failTransfers) return false;
        _move(msg.sender, to, amount);
        return true;
    }
}
