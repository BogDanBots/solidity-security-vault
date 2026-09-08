// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";

contract MockERC20 is IERC20Minimal {
    string public constant name = "Portfolio Test Token";
    string public constant symbol = "PTT";
    uint8 public constant decimals = 18;

    mapping(address account => uint256 balance) public override balanceOf;
    mapping(address account => mapping(address spender => uint256 amount)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        virtual
        override
        returns (bool)
    {
        uint256 approved = allowance[from][msg.sender];
        require(approved >= amount, "allowance");
        allowance[from][msg.sender] = approved - amount;
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(to != address(0), "zero recipient");
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
