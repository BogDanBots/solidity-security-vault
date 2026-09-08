// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SecureVault} from "../src/SecureVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract SecureVaultFuzzTest is Test {
    MockERC20 internal token;
    SecureVault internal vault;
    address internal actor = address(0xCAFE);

    function setUp() public {
        token = new MockERC20();
        vault = new SecureVault(address(token), type(uint128).max, address(this));
        token.mint(actor, type(uint128).max);
        vm.prank(actor);
        token.approve(address(vault), type(uint256).max);
    }

    function testFuzzDepositThenRedeem(uint128 amount) public {
        vm.assume(amount > 0);
        vm.startPrank(actor);
        uint256 shares = vault.deposit(amount, actor);
        uint256 assets = vault.redeem(shares, actor);
        vm.stopPrank();

        assertEq(assets, amount);
        assertEq(vault.totalShares(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function testFuzzPreviewWithdrawIsSufficient(uint128 depositAmount, uint128 withdrawAmount)
        public
    {
        vm.assume(depositAmount > 1);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        vm.startPrank(actor);
        vault.deposit(depositAmount, actor);
        uint256 shares = vault.previewWithdraw(withdrawAmount);
        uint256 burned = vault.withdraw(withdrawAmount, actor);
        vm.stopPrank();

        assertEq(burned, shares);
        assertGe(vault.totalAssets(), depositAmount - withdrawAmount);
    }
}
