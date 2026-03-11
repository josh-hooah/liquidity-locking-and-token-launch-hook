# Launch Model

## Supported Modes
- `TIME`
- `VOLUME`
- `HYBRID = min(TIME, VOLUME)`

## Policy Constraints
- milestones must be strictly increasing
- milestone bps must be non-decreasing and `<=10000`
- time epoch and per-epoch bps must be valid for time-using modes

## Progression
`advance()` is permissionless and idempotent.
