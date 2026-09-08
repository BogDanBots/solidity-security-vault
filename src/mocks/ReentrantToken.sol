// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

contract ReentrantToken is MockERC20 {
    address public hookTarget;
    bytes public hookData;
    bool public hookEnabled;

    function configureHook(address target, bytes calldata data) external {
        hookTarget = target;
        hookData = data;
        hookEnabled = true;
    }

    function disableHook() external {
        hookEnabled = false;
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
            (bool success, bytes memory data) = hookTarget.call(hookData);
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
    }
}
