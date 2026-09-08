// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { SecureVault } from "../src/SecureVault.sol";
import { FalseReturnToken } from "../src/mocks/FalseReturnToken.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { ReentrantToken } from "../src/mocks/ReentrantToken.sol";
import { FeeOnTransferToken } from "../src/mocks/FeeOnTransferToken.sol";

/// @dev Test-only state seeding lets the rounding test exercise a non-unit share price.
contract SecureVaultMathHarness is SecureVault {
    constructor(address asset_, uint256 depositCap_, address owner_)
        SecureVault(asset_, depositCap_, owner_)
    { }

    function seedAccounting(address account, uint256 assets, uint256 shares) external {
        managedAssets = assets;
        totalShares = shares;
        sharesOf[account] = shares;
    }
}

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
        uint256 shares = vault.deposit(100 ether, alice, 100 ether);
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
        vault.deposit(100 ether, alice, 100 ether);

        vm.prank(bob);
        vault.deposit(1 ether, bob, 1 ether);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(1 ether, alice);

        assertGe(sharesBurned, 1 ether);
        assertEq(vault.sharesOf(alice) + sharesBurned, 100 ether);
    }

    function testWithdrawRoundsUpAtNonUnitSharePrice() public {
        SecureVaultMathHarness rateVault =
            new SecureVaultMathHarness(address(token), 100 ether, address(this));
        token.mint(address(rateVault), 2);
        rateVault.seedAccounting(alice, 2, 3);

        vm.prank(alice);
        uint256 sharesBurned = rateVault.withdraw(1, alice);

        assertEq(sharesBurned, 2);
        assertEq(rateVault.sharesOf(alice), 1);
        assertEq(rateVault.totalShares(), 1);
        assertEq(rateVault.totalAssets(), 1);
    }

    function testCapAndPause() public {
        vm.prank(alice);
        vault.deposit(1_000 ether, alice, 1_000 ether);

        vm.prank(bob);
        vm.expectRevert(SecureVault.DepositCapExceeded.selector);
        vault.deposit(1, bob, 1);

        vault.pause();
        vm.prank(alice);
        vm.expectRevert(SecureVault.PausedError.selector);
        vault.redeem(1, alice);
    }

    function testDonationDoesNotDistortSubsequentDeposit() public {
        // Without donation-resistant accounting this is the 2 / 999 / 1,000
        // sequence that can mint only 1 victim share and extract value later.
        token.mint(alice, 1);

        vm.prank(alice);
        uint256 attackerShares = vault.deposit(2, alice, 2);

        vm.prank(alice);
        bool donationSucceeded = token.transfer(address(vault), 999);
        assertTrue(donationSucceeded);

        vm.prank(bob);
        uint256 victimShares = vault.deposit(1_000, bob, 1_000);

        assertEq(victimShares, 1_000);
        assertEq(vault.unaccountedAssets(), 999);

        vm.prank(alice);
        uint256 attackerAssets = vault.redeem(attackerShares, alice);
        assertEq(attackerAssets, 2);
        assertEq(vault.sharesOf(bob), 1_000);
    }

    function testTwoStepOwnershipTransfer() public {
        address newOwner = address(0xBEEF);
        vault.transferOwnership(newOwner);
        assertEq(vault.pendingOwner(), newOwner);

        vm.prank(newOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), newOwner);
        assertEq(vault.pendingOwner(), address(0));
        vm.expectRevert(SecureVault.NotOwner.selector);
        vault.pause();
    }

    function testCannotRecoverUnderlyingAsset() public {
        vm.expectRevert(SecureVault.AssetRecoveryForbidden.selector);
        vault.recoverNonAssetToken(address(token), address(this), 1);
    }

    function testCannotRedeemAnotherUsersShares() public {
        vm.prank(alice);
        vault.deposit(100 ether, alice, 100 ether);

        vm.prank(bob);
        vm.expectRevert(SecureVault.InsufficientShares.selector);
        vault.redeem(1 ether, bob);
    }

    function testDepositAccountsForFeeOnTransferToken() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken(500);
        SecureVault feeVault = new SecureVault(address(feeToken), 100 ether, address(this));
        feeToken.mint(alice, 100 ether);

        vm.startPrank(alice);
        feeToken.approve(address(feeVault), type(uint256).max);
        vm.expectRevert(SecureVault.SlippageExceeded.selector);
        feeVault.deposit(100 ether, alice, 100 ether);
        uint256 shares = feeVault.deposit(100 ether, alice, 95 ether);
        vm.stopPrank();

        assertEq(feeVault.totalAssets(), 95 ether);
        assertEq(shares, 95 ether);
        assertEq(feeVault.sharesOf(alice), 95 ether);

        vm.prank(alice);
        vm.expectRevert(SecureVault.TransferFailed.selector);
        feeVault.withdraw(1 ether, alice);
        assertEq(feeVault.totalAssets(), 95 ether);
        assertEq(feeVault.sharesOf(alice), 95 ether);
    }

    function testRejectsFalseOutgoingTransferWithoutBurningShares() public {
        FalseReturnToken falseToken = new FalseReturnToken();
        SecureVault falseVault = new SecureVault(address(falseToken), 100 ether, address(this));
        falseToken.mint(alice, 100 ether);

        vm.startPrank(alice);
        falseToken.approve(address(falseVault), type(uint256).max);
        falseVault.deposit(100 ether, alice, 100 ether);
        vm.stopPrank();

        falseToken.setFailTransfers(true);
        vm.prank(alice);
        vm.expectRevert(SecureVault.TransferFailed.selector);
        falseVault.withdraw(1 ether, alice);

        assertEq(falseVault.totalAssets(), 100 ether);
        assertEq(falseVault.sharesOf(alice), 100 ether);
    }

    function testReentrancyGuardRejectsTokenCallback() public {
        ReentrantToken attackToken = new ReentrantToken();
        SecureVault attackVault = new SecureVault(address(attackToken), 1_000 ether, address(this));
        attackToken.mint(address(this), 100 ether);
        attackToken.mint(address(attackToken), 1 ether);
        attackToken.approve(address(attackVault), type(uint256).max);
        attackToken.approveFromToken(address(attackVault), type(uint256).max);
        attackToken.configureHook(
            address(attackVault),
            abi.encodeCall(SecureVault.deposit, (1 ether, address(attackToken), 1 ether))
        );

        uint256 shares = attackVault.deposit(10 ether, address(this), 10 ether);

        assertEq(shares, 10 ether);
        assertFalse(attackToken.hookSuccess());
        assertEq(
            attackToken.hookReturnData(), abi.encodeWithSelector(SecureVault.Reentrancy.selector)
        );
        assertEq(attackVault.totalShares(), 10 ether);
    }
}
