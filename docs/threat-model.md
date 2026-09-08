# Threat model

This project deliberately holds one ERC-20 asset and issues non-transferable internal shares. It has no strategy adapter, external yield source or live deployment target.

## In scope

- reentrancy through token callbacks;
- false-returning or reverting token transfers;
- fee-on-transfer accounting differences;
- first-deposit and zero-share rounding cases;
- cap, pause and ownership authorization;
- stale previews and withdrawal rounding;
- accidental recovery of the underlying asset;
- malicious callers and arbitrary receiver addresses.

## Trust assumptions

- The token contract may be adversarial and is treated as an external call boundary.
- The owner key is a privileged administrative trust assumption.
- Users must validate the asset address and receiver before submitting transactions.
- The project is not audited and is not intended to hold production funds.

## Design response

The vault measures actual tokens received, uses a reentrancy guard around state-changing flows, keeps the underlying asset unrecoverable by the owner, separates ownership transfer into two steps, and tests authorization plus adversarial token behavior.
