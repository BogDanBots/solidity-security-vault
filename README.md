# SecureVault — compact Solidity security portfolio project

SecureVault is a deliberately small, single-asset ERC-20 vault written for reviewability. It demonstrates accounting, explicit authorization, reentrancy boundaries, adversarial token testing, fuzzing, invariants and static analysis without introducing an unnecessary strategy layer.

This is an open-source portfolio project, not a production vault and not an audit. It does not copy the private SolTrench vault implementation.

## Design choices

- One immutable underlying ERC-20 asset.
- Non-transferable internal shares to keep the ownership surface small.
- Actual-received accounting for fee-on-transfer tolerance.
- Deposit cap, pause control and two-step ownership transfer.
- No strategy adapter, yield source or live-funds integration.
- Underlying asset cannot be recovered through the administrative token-recovery function.

## Review focus

The most important files are `src/SecureVault.sol`, `docs/threat-model.md` and the Foundry tests. The test suite covers normal flows, rounding, authorization, pause behavior, adversarial token callbacks, fuzzed amounts and stateful invariants.

## Verification

Install Foundry and the pinned `forge-std` test dependency, then run the commands in `docs/testing-and-analysis.md`. The repository should only publish measured results from an actual run; no audit, security guarantee or production readiness is implied.
