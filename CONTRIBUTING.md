# Contributing

## Setup
```bash
make bootstrap
make build
make test
```

## Standards
- Solidity: `^0.8.24`, deterministic behavior first.
- Keep hook logic minimal; policy/accounting goes in manager/vault.
- Add tests for every behavior change.

## PR Checklist
- [ ] `make deps-check`
- [ ] `make build`
- [ ] `make test`
- [ ] `make coverage`
- [ ] docs updated for API or behavior changes
