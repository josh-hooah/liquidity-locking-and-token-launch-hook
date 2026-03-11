# Anti-Sniping

Launch window guards are enforced in `onBeforeSwap`:

- max transaction amount
- cooldown per address

Tradeoffs:

- per-address cooldown does not stop multi-address split attacks
- strict max-tx can reduce legitimate early flow if configured too low
