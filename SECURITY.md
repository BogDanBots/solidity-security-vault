# Security policy

SecureVault is a deliberately small portfolio project. It is not a production
vault, an audit, or a security guarantee for real funds. Do not deposit assets
or use the contract on mainnet.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's
private vulnerability reporting for this repository when available. If that
option is unavailable, contact the repository owner through the
[BogDanBots GitHub profile](https://github.com/BogDanBots) and include:

- the affected commit or file;
- clear reproduction steps or a minimal proof of concept;
- the practical impact and any required assumptions; and
- a suggested mitigation, if known.

Please allow reasonable time for triage before making details public. Reports
about the portfolio documentation, test doubles, or deliberately unsupported
production features should be labelled as such so they can be separated from
issues in the compact vault model.

## Scope

The review scope is the Solidity under `src/`, its supporting interfaces, and
the security-relevant tests under `test/`. The deployment script and CI are
supporting material only. This project intentionally does not claim production
readiness; any real deployment would require independent review, integration
testing, and an external audit.
