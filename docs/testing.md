# Testing

## Commands
```bash
make test
make coverage
```

Coverage command used in CI:

```bash
forge coverage --ir-minimum --exclude-tests --no-match-coverage "script/" --report summary --report lcov
```

## Suites
- `test/unit/LaunchManagerEdge.t.sol`
- `test/fuzz/LaunchManagerFuzz.t.sol`
- `test/integration/LaunchLifecycleIntegration.t.sol`

Covered edge behaviors:
- max-tx exact boundary
- cooldown boundary exact timestamp
- milestone off-by-one exact hit
- invalid policy ordering / bps overflow
- idempotent advance
- withdraw-before-unlock revert
- pause/unpause behavior
- hook permission mismatch and only-hook gating

Latest measured source coverage (contracts under `src/`): ~93.65% lines.
