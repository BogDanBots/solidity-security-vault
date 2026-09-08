# Slither review

This document records the static-analysis result for the portfolio snapshot.
It is a reviewed report, not an audit and not a claim that the code is safe for
production funds.

## Run context

- Slither: 0.11.6
- Foundry: 1.8.1
- Solidity: 0.8.24
- Command: `slither . --config-file slither.config.json --json slither-report.json`
- Date: 2026-09-08
- Result: 15 findings reported; no detector was broadly suppressed.
- CI baseline: [`docs/slither-baseline.json`](slither-baseline.json)

## Findings and disposition

### `reentrancy-balance`, `reentrancy-no-eth` and `reentrancy-benign`

Slither flags `SecureVault.deposit` because it reads the raw asset balance,
calls an external token, then updates the managed-asset ledger and share state.
That ordering is intentional: the vault must measure the actual received amount
while keeping unsolicited donations out of share pricing. Slither also flags
`_safeTransfer` because it reads the receiver balance before and after an
external token call.

The state-changing entry points are protected by `nonReentrant`, which is the
control that prevents a token callback from entering a second vault operation.
The adversarial callback test in `test/SecureVault.t.sol` supplies the callback
token with both balance and allowance, then asserts the exact `Reentrancy()`
return data. These findings remain visible because the external-call boundaries
deserve review.

The additional `reentrancy-no-eth` finding on the test-only `ReentrantToken`
comes from deliberately restoring its hook flag after making the callback. It
exists to make the negative test viable and observable, not as production vault
logic.

### `incorrect-equality`

The strict equality checks are explicit zero-state guards: zero received
assets, an insolvent vault, zero shares, or zero assets out. They are not
authorization checks and are required to reject ambiguous first-deposit and
rounding cases. They are kept visible for reviewer attention.

### `low-level-calls`

The vault uses a small compatibility wrapper for ERC-20 contracts that return
`true`, return no data, or revert. The wrapper accepts only a successful call
with empty data or a decodable `true` value. The mock reentrant token uses a
low-level callback deliberately to model a hostile token.

### Baseline policy

The CI job requires successful Slither analysis and compares complete
normalized findings with the reviewed baseline. Every affected element is
retained, including its type, name, source file/location, parent chain and
auxiliary metadata. The comparison uses a multiset rather than a set, so
duplicate findings and changes to the number of affected elements cannot be
hidden. Machine-specific absolute paths are removed, while source offsets are
kept intentionally so source-shape changes require an explicit baseline review.
An unexpected finding, changed duplicate count or missing baseline finding
fails CI and requires human review of the changed analysis surface.

## Review conclusion

No finding is silently treated as a clean-audit result. The production-facing
contract has an explicit reentrancy guard, checks token-call outcomes, measures
actual received assets, prices shares from the managed ledger, rejects outgoing
short-delivery, and keeps the underlying asset out of the recovery path. Any
real deployment would still require independent review, integration testing
against the chosen token, and an external audit.
