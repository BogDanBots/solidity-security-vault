// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SecureVault} from "../src/SecureVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {ReentrantToken} from "../src/mocks/ReentrantToken.sol";

contract SecureVaultTest is Test {
    MockERC20 internal token;
    SecureVault internal vault;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20();
        vault = new SecureVault(address(token), 1_000 ether, address(this));
        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    function testDepositAndRedeem() public {
        vm.startPrank(alice);
        uint256 shares = vault.deposit(100 ether, alice);
        uint256 before = token.balanceOf(alice);
        uint256 assets = vault.redeem(shares, alice);
        vm.stopPrank();

        assertEq(shares, 100 ether);
        assertEq(assets, 100 ether);
        assertEq(token.balanceOf(alice), before + assets);
        assertEq(vault.totalShares(), 0);
    }

    function testWithdrawUsesCeilingAndDoesNotOverburn() public {
        vm.prank(alice);
        vault.deposit(100 ether, alice);

        vm.prank(bob);
        vault.deposit(1 ether, bob);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(1 ether, alice);

        assertGe(sharesBurned, 1 ether);
        assertEq(vault.sharesOf(alice) + sharesBurned, 100 ether);
    }

    function testCapAndPause() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice);

        vm.prank(bob);
        vm.expectRevert(SecureVault.DepositCapExceeded.selector);
        vault.deposit(1, bob);

        vault.pause();
        vm.prank(alice);
        vm.expectRevert(SecureVault.PausedError.selector);
        vault.redeem(1, alice);
    }

    function testCannotRecoverUnderlyingAsset() public {
        vm.expectRevert(SecureVault.AssetRecoveryForbidden.selector);
        vault.recoverNonAssetToken(address(token), address(this), 1);
    }

    function testReentrancyGuardRejectsTokenCallback() public {
        ReentrantToken attackToken = new ReentrantToken();
        SecureVault attackVault = new SecureVault(address(attackToken), 1_000 ether, address(this));
        attackToken.mint(address(this), 100 ether);
        attackToken.approve(address(attackVault), type(uint256).max);
        attackToken.configureHook(
            address(attackVault), abi.encodeCall(SecureVault.deposit, (1 ether, address(this)))
        );

        vm.expectRevert();
        attackVault.deposit(10 ether, address(this));
    }
}
