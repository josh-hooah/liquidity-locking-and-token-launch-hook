# Frontend Launch Console

Static frontend for launch setup, pool initialization, swap sequence execution, unlock progression, and withdrawal operations.

## Run

From repo root:

```bash
python3 -m http.server 8080
```

Open:

- `http://localhost:8080/frontend/`

## Notes

- Serve from repository root so the app can load ABIs from `shared/abi/*`.
- Wallet interaction requires an injected wallet (e.g., MetaMask).
- For local demo use addresses printed by `make demo-local`.
