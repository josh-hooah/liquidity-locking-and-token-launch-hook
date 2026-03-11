# Security

## Threats
- creator rug through policy abuse
- wash-trade volume inflation
- multi-address sniper bypass
- stability-band griefing
- storage growth through per-address state

## Mitigations
- policy validation on create/update
- manager/vault/hook access controls
- min-trade filter for volume counting
- bounded launch-window cooldown mapping usage
- monotonic unlock and vault withdrawal bounds

## Residual Risks
No claim of attack-proof behavior.
