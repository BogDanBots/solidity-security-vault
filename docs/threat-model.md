# Threat model

This project deliberately holds one ERC-20 asset and issues non-transferable internal shares. It has no strategy adapter, external yield source or live deployment target.

## In scope

- reentrancy through token callbacks;
- false-returning or reverting token transfers;
- fee-on-transfer accounting differences;
- direct-token-transfer donation attacks and share-price manipulation;
- first-deposit and zero-share rounding cases;
- caller slippage tolerance when the exchange rate changes;
- cap, pause and ownership authorization;
- stale previews and withdrawal rounding;
- accidental recovery of the underlying asset;
- malicious callers and arbitrary receiver addresses.

## Supported token behavior

The vault expects an ERC-20-like asset exposing `balanceOf`, `transfer` and
`transferFrom`. A token call must succeed and may return either no data or an
ABI-decodable `true`; reverts, false returns and malformed return data are
rejected.

Incoming fee-on-transfer behavior is supported because deposits credit shares
against the balance delta actually received. Outgoing fee-on-transfer behavior
is not silently treated as compatible: withdrawals verify that the receiver's
balance increased by the requested amount and revert otherwise. Rebasing
tokens, tokens that mutate balances outside the transfer being measured, and
other non-standard accounting behavior are outside this compact project's
support guarantee.

## Trust assumptions

- The token contract may be adversarial and is treated as an external call boundary.
- The owner key is a privileged administrative trust assumption.
- Users must validate the asset address and receiver before submitting transactions.
- The project is not audited and is not intended to hold production funds.

## Design response

The vault prices shares from `managedAssets`, an internal ledger updated only
after a successful measured deposit or withdrawal. Direct transfers are
reported by `unaccountedAssets()` but do not change the exchange rate, so the
small-deposit-plus-donation attack does not dilute a later depositor. Every
deposit also requires a caller-supplied `minShares` value.

Those direct donations are permanently locked in this compact design. They are
visible for accounting diagnostics, but there is no recovery or distribution
path for the owner or share holders.

It uses a reentrancy guard around state-changing flows, keeps the underlying
asset unrecoverable by the owner, separates ownership transfer into two steps,
and tests authorization plus adversarial token behavior.

## Administrative freeze risk

The owner can pause deposits and withdrawals indefinitely. There is no
timelock, expiry or permissionless unpause path in this deliberately small
example. The owner key is therefore a full administrative trust assumption;
users should not treat the pause control as a guarantee of timely recovery.
