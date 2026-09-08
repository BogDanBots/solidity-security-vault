// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "./MockERC20.sol";

contract ReentrantToken is MockERC20 {
    error ZeroAddress();

    address public hookTarget;
    bytes public hookData;
    bool public hookEnabled;
    bool public hookSuccess;
    bytes public hookReturnData;

    function configureHook(address target, bytes calldata data) external {
        if (target == address(0)) revert ZeroAddress();
        hookTarget = target;
        hookData = data;
        hookEnabled = true;
    }

    function disableHook() external {
        hookEnabled = false;
    }

    /// @dev Gives the token contract an allowance for a callback deposit.
    function approveFromToken(address spender, uint256 amount) external returns (bool) {
        allowance[address(this)][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _move(msg.sender, to, amount);
        _hook();
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
        _move(from, to, amount);
        _hook();
        return true;
    }

    function _hook() internal {
        if (hookEnabled) {
            bool wasEnabled = hookEnabled;
            hookEnabled = false;
            (hookSuccess, hookReturnData) = hookTarget.call(hookData);
            hookEnabled = wasEnabled;
        }
    }
}
