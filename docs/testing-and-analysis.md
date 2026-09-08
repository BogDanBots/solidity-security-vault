# Testing and static analysis

The verification plan is intentionally visible and repeatable:

```text
forge install foundry-rs/forge-std@16cb9c998736cab8f14aebd5199cdf6a02fde055 --no-commit
forge fmt --check
forge build
forge test --match-test testFuzz -vvv
forge test --show-progress -vvv
slither . --config-file slither.config.json --json slither-report.json
```

The default invariant campaign is configured in `foundry.toml` as 64 runs with
128 calls per run. It exercises deposits and redemptions from two independent
actors, direct donations and cross-account redemption attempts.
The fuzz tests use Foundry's default 256 cases unless overridden by the caller.

The regression suite includes the concrete 2-unit deposit, 999-unit direct
donation and 1,000-unit victim deposit sequence, plus a mandatory minimum-share
failure case. It also covers two-step ownership transfer, false outgoing token
returns, outgoing fee-on-transfer rejection, and a callback with enough token
balance and allowance to prove that the reentrancy guard—not an incidental
allowance failure—stops the nested deposit.

The CI job records Slither findings as an artifact. Exit code 255 is accepted
only long enough to inspect the generated JSON; `scripts/check_slither_baseline.py`
then requires successful analysis and exact agreement with the reviewed,
complete finding multiset in `docs/slither-baseline.json`. Every affected
element and its location is compared, and duplicate counts are preserved.
New findings, changed counts, missing baseline findings, compiler errors and
analysis-execution failures fail CI.
