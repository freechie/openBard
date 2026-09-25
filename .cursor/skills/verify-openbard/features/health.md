# Health

Health tells a caller whether the openBard worker process is up and willing to take HTTP.

## Sub-features

- `health-ok` returns JSON `{"status":"ok"}` with HTTP 200.

## How to get to it (user POV)

- Request `GET /health` on the worker URL, for example `curl http://127.0.0.1:18765/health`.

## Driving it with control-openbard

Preconditions:

- The worker is healthy at `http://127.0.0.1:18765`.
- `control-openbard doctor` prints `title=openBard Worker` and `health={"status":"ok"}`.

- **Ask health.** Request the health document. Run `.cursor/skills/verify-openbard/scripts/control-openbard get /health --expect 200 --save health`. `status.txt` is `200`. Parsed `body.json` has `status` equal to `ok`.
- **Proof.** Keep `$OPENBARD_VERIFY_EVIDENCE_DIR/health/body.json` and `request.txt`. The request line is `GET http://127.0.0.1:18765/health`.

## Gotchas

- A TCP accept on 8000 is not this instance. Doctor must match the PID in the state file.
- `GET /` is not health. Unmatched paths return FastAPI 404 and do not prove this feature.
