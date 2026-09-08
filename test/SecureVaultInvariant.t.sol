// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { SecureVault } from "../src/SecureVault.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract VaultActor {
    MockERC20 internal immutable token;
    SecureVault internal immutable vault;

    constructor(MockERC20 token_, SecureVault vault_) {
        token = token_;
        vault = vault_;
        token_.approve(address(vault_), type(uint256).max);
    }

    function deposit(uint256 amount, uint256 minShares) external returns (uint256) {
        return vault.deposit(amount, address(this), minShares);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return vault.redeem(shares, address(this));
    }

    function donate(uint256 amount) external {
        bool success = token.transfer(address(vault), amount);
        assert(success);
    }

    function tryRedeem(uint256 shares) external returns (bool success, bytes memory reason) {
        try vault.redeem(shares, address(this)) returns (uint256) {
            success = true;
        } catch (bytes memory revertData) {
            reason = revertData;
        }
    }
}

contract VaultHandler {
    uint256 private constant ACTOR_BALANCE = 1_000_000 ether;

    MockERC20 internal immutable token;
    SecureVault internal immutable vault;
    VaultActor public immutable actorA;
    VaultActor public immutable actorB;

    error CrossAccountRedemptionSucceeded();
    error CrossAccountBalanceChanged();

    constructor(MockERC20 token_, SecureVault vault_) {
        token = token_;
        vault = vault_;
        actorA = new VaultActor(token_, vault_);
        actorB = new VaultActor(token_, vault_);
        token_.mint(address(actorA), ACTOR_BALANCE);
        token_.mint(address(actorB), ACTOR_BALANCE);
    }

    function deposit(uint256 amount, bool useActorB) external {
        amount = bound(amount, 1, ACTOR_BALANCE);
        VaultActor actor = useActorB ? actorB : actorA;
        if (token.balanceOf(address(actor)) < amount) return;
        actor.deposit(amount, amount);
    }

    function redeem(uint256 shares, bool useActorB) external {
        VaultActor actor = useActorB ? actorB : actorA;
        uint256 owned = vault.sharesOf(address(actor));
        if (owned == 0) return;
        shares = bound(shares, 1, owned);
        if (vault.previewRedeem(shares) == 0) return;
        actor.redeem(shares);
    }

    function donate(uint256 amount, bool useActorB) external {
        amount = bound(amount, 1, 1_000 ether);
        VaultActor actor = useActorB ? actorB : actorA;
        if (token.balanceOf(address(actor)) < amount) return;
        actor.donate(amount);
    }

    /// @dev Makes the chosen actor empty, then has it try to redeem the other
    /// actor's exact balance. A successful call would demonstrate an account
    /// isolation failure and deliberately fails the invariant run.
    function crossRedeem(bool attackerIsActorB) external {
        VaultActor attacker = attackerIsActorB ? actorB : actorA;
        VaultActor victim = attackerIsActorB ? actorA : actorB;

        uint256 attackerShares = vault.sharesOf(address(attacker));
        if (attackerShares > 0) {
            if (vault.previewRedeem(attackerShares) == 0) return;
            attacker.redeem(attackerShares);
        }

        uint256 victimShares = vault.sharesOf(address(victim));
        if (victimShares == 0) return;

        (bool success,) = attacker.tryRedeem(victimShares);
        if (success) revert CrossAccountRedemptionSucceeded();
        if (vault.sharesOf(address(victim)) != victimShares) {
            revert CrossAccountBalanceChanged();
        }
    }

    function bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        return min + (value % (max - min + 1));
    }
}

contract SecureVaultInvariantTest is StdInvariant, Test {
    MockERC20 internal token;
    SecureVault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        token = new MockERC20();
        vault = new SecureVault(address(token), 1_000_000 ether, address(this));
        handler = new VaultHandler(token, vault);
        targetContract(address(handler));
    }

    function invariant_SharesHaveBackingAssets() public view {
        assertGe(vault.rawAssetBalance(), vault.totalAssets());
        if (vault.totalShares() > 0) assertGt(vault.totalAssets(), 0);
    }

    function invariant_TwoActorsHaveSeparateShareBalances() public view {
        uint256 actorAShares = vault.sharesOf(address(handler.actorA()));
        uint256 actorBShares = vault.sharesOf(address(handler.actorB()));
        assertEq(vault.totalShares(), actorAShares + actorBShares);
    }
}
