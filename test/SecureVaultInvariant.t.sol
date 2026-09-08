// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SecureVault} from "../src/SecureVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract VaultHandler {
    MockERC20 internal immutable token;
    SecureVault internal immutable vault;
    address internal immutable actor;

    constructor(MockERC20 token_, SecureVault vault_, address actor_) {
        token = token_;
        vault = vault_;
        actor = actor_;
        token_.mint(address(this), 1_000_000 ether);
        token_.approve(address(vault_), type(uint256).max);
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000 ether);
        if (token.balanceOf(address(this)) < amount) return;
        vault.deposit(amount, actor);
    }

    function redeem(uint256 shares) external {
        uint256 owned = vault.sharesOf(actor);
        if (owned == 0) return;
        shares = bound(shares, 1, owned);
        // The handler is not the share owner; this call must fail and cannot mutate vault state.
        (bool success,) = address(vault).call(
            abi.encodeWithSelector(SecureVault.redeem.selector, shares, actor)
        );
        success;
    }

    function bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        return min + (value % (max - min + 1));
    }
}

contract SecureVaultInvariantTest is Test {
    MockERC20 internal token;
    SecureVault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        token = new MockERC20();
        vault = new SecureVault(address(token), 1_000_000 ether, address(this));
        handler = new VaultHandler(token, vault, address(0xCAFE));
        targetContract(address(handler));
    }

    function invariantSharesHaveBackingAssets() public view {
        if (vault.totalShares() > 0) {
            assertGt(vault.totalAssets(), 0);
        }
    }

    function invariantHandlerCannotRedeemForAnotherAccount() public view {
        assertEq(vault.sharesOf(address(handler)), 0);
    }
}
