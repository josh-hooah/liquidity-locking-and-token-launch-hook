# Security Policy

## Scope
Contracts under `src/` are in scope.

## Reporting
Report vulnerabilities privately to project maintainers before public disclosure.

## Severity Guidance
High priority:

- premature unlock or over-withdrawal
- bypass of anti-snipe launch-window checks
- unauthorized policy/manager/vault state mutation

## Out of Scope
- test-only contracts from upstream dependencies
- local script-only operational errors

## Notes
This system is not attack-proof. See `docs/security.md` for threat model and residual risks.
