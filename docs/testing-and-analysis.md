# Testing and static analysis

The verification plan is intentionally visible and repeatable:

```text
forge fmt --check
forge build
forge test -vvv
forge test --match-test testFuzz -vvv
forge test --match-test invariant -vvv
slither . --config-file slither.config.json
```

The final README should record the exact Foundry, Solidity and Slither versions, the date of the run, test results, coverage if collected, gas observations and every static-analysis finding. Warnings must be reviewed individually; broad suppression is not acceptable.
