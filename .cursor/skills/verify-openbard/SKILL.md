---
name: verify-openbard
description: Drive the openBard FastAPI worker over HTTP on 127.0.0.1 (GET /health, GET /v1/transcriptions/demo, GET /v1/audio/demo, POST /v1/transcriptions with Basic Pitch). Use when proving worker behavior, reproducing a worker bug, or checking transcription JSON against fixtures. Does not drive the iOS piano-roll app.
---

# Verify openBard worker

openBard ships an iOS piano-roll editor and a FastAPI worker. The iOS app loads bundled JSON. It does not call the worker. This skill drives the worker over HTTP, which is the path an agent can launch on Linux and in local Python. On macOS, `./scripts/verify` still compiles iOS. It does not launch Simulator.

Read `features/README.md` before a drive. Drive from that map. A convenient extra endpoint is not coverage for a mapped feature you skipped.

## Launch

From the repo root:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
export OPENBARD_VERIFY_RUN_ID="${OPENBARD_VERIFY_RUN_ID:-default}"
export OPENBARD_VERIFY_PORT="${OPENBARD_VERIFY_PORT:-18765}"
export OPENBARD_VERIFY_EVIDENCE_DIR="${OPENBARD_VERIFY_EVIDENCE_DIR:-/tmp/openbard-verify-evidence}"
.cursor/skills/verify-openbard/scripts/control-openbard launch
```

Needs Python 3.11 via uv, `uv sync --frozen` in `worker/`, and `curl`. `worker/.python-version` pins 3.11. `worker/pyproject.toml` allows `>=3.11,<3.13`.

Ready when `GET http://127.0.0.1:18765/health` returns exactly `{"status":"ok"}`. The log at `/tmp/openbard-verify-run-$OPENBARD_VERIFY_RUN_ID/uvicorn.log` contains `Uvicorn running on http://127.0.0.1:18765`. Launch prints `url=`, `pid=`, and `log=`.

Do not use `uv run uvicorn --reload` for verification. The helper starts `worker/.venv/bin/uvicorn app.main:app` so the stored PID owns the listen socket. README's `--reload` command is for humans editing code.

Default verify port is `18765`, not README's `8000`, so a developer server on 8000 stays untouched. If 18765 is busy, set `OPENBARD_VERIFY_PORT` to a free port. Do not kill a process this run did not start.

A second instance is allowed. Give it a different `OPENBARD_VERIFY_RUN_ID` and `OPENBARD_VERIFY_PORT`. There is no shared writable data directory. Each process loads TensorFlow on the first `POST /v1/transcriptions`, so a second instance costs RAM. Do not drive a worker this run did not launch.

Linux has no Xcode. Do not run `./scripts/verify` or Simulator as part of this skill.

Teardown is `control-openbard cleanup`. Run it after a failed launch too.

## Doctor

```bash
.cursor/skills/verify-openbard/scripts/control-openbard doctor
```

Require all of the following.

- State file exists at `/tmp/openbard-verify-run-$OPENBARD_VERIFY_RUN_ID/state.env`.
- `OPENBARD_VERIFY_PID` is alive and `/proc/$pid/cmdline` contains both `uvicorn` and `app.main:app`.
- `127.0.0.1:$OPENBARD_VERIFY_PORT` accepts TCP.
- `GET /health` is exactly `{"status":"ok"}`.
- `GET /openapi.json` has `info.title` equal to `openBard Worker`.

If any check fails, stop driving. Relaunch this run's instance, or clean it up. Do not fall back to a random process on port 8000.

## Drive

Drive HTTP with `control-openbard`. It wraps curl against the launched URL. Multipart field name is `audio`. Paths come from `worker/app/main.py`.

```bash
.cursor/skills/verify-openbard/scripts/control-openbard doctor
.cursor/skills/verify-openbard/scripts/control-openbard get /health --expect 200 --save health
.cursor/skills/verify-openbard/scripts/control-openbard get /v1/transcriptions/demo --expect 200 --save demo-transcription
.cursor/skills/verify-openbard/scripts/control-openbard get /v1/audio/demo --expect 200 --save demo-audio
.cursor/skills/verify-openbard/scripts/control-openbard post-audio fixtures/c-major-chord.wav --expect 200 --save live-transcription
```

Prefer these handles over coordinates or tab order.

- `GET /health`
- `GET /v1/transcriptions/demo` (fake `dsp_v0` C major chord)
- `GET /v1/audio/demo` (bytes of `fixtures/c-major-chord.wav`)
- `POST /v1/transcriptions` with form field `audio`
- Allowed upload suffixes `.wav`, `.mp3`, `.m4a`, `.caf`, `.aac`

Recipes live in `features/`. Capture the request and the resulting body. After a mutation-style POST, read the JSON fields. Do not trust a 200 with an empty `note_events` list for the C major fixture.

First `POST /v1/transcriptions` after process start can take several seconds while Basic Pitch loads TensorFlow. Wait for HTTP 200. The helper curl timeout is 120 seconds. Do not treat a slow first call as a hang. After that first POST, later POSTs reuse the loaded model.

`GET /docs` is FastAPI Swagger. It is not an openBard product screen. Do not use it as proof of a mapped feature.

## Evidence

Set `OPENBARD_VERIFY_EVIDENCE_DIR` to a directory that must survive cleanup. Default is `/tmp/openbard-verify-evidence`. Cleanup deletes only `/tmp/openbard-verify-run-$OPENBARD_VERIFY_RUN_ID`.

`--save <name>` writes `$OPENBARD_VERIFY_EVIDENCE_DIR/<name>/` with `request.txt`, `status.txt`, `headers.txt`, `summary.txt`, and `body.json` or `body.wav`.

Proof standards:

- Exercise the HTTP path a user of the worker uses. That is curl against the live server, not `TestClient` and not a private Python call into `BasicPitchTranscriber`.
- Keep the request line and the response body. A screenshot of `/docs` is not enough.
- For `POST /v1/transcriptions` on `fixtures/c-major-chord.wav`, require `engine` `basic_pitch`, `tempo_bpm` JSON null, `key_guess` JSON null, and `pitch_midi` values `[60, 64, 67]` when sorted. Each note's `confidence` equals its `velocity`.
- For `GET /v1/audio/demo`, require `Content-Type` `audio/wav`, filename `c-major-chord.wav`, and body bytes equal to `fixtures/c-major-chord.wav`.
- For `GET /v1/transcriptions/demo`, require `engine` `dsp_v0`, `engine_version` `0.1.0`, `tempo_bpm` `120.0`, `key_guess` `C major`, and pitches `[60, 64, 67]` with onset `0.0` and duration `2.0`.
- Unsupported upload type must return HTTP 400 and `{"detail":"Unsupported audio type"}`.
- Do not mock Basic Pitch. The live POST is the production worker path.

## Cleanup

```bash
.cursor/skills/verify-openbard/scripts/control-openbard cleanup
```

Cleanup sends TERM, then KILL, to the PID in the state file. It then removes the state directory. It does not `pkill uvicorn` and it does not delete `OPENBARD_VERIFY_EVIDENCE_DIR`.

If a launch or drive fails, run cleanup before the next attempt so port `18765` is free.

After cleanup, confirm evidence files still exist under `OPENBARD_VERIFY_EVIDENCE_DIR`.

## Helpers

`scripts/control-openbard` is executable. Invoke it from the repo root.

```bash
.cursor/skills/verify-openbard/scripts/control-openbard launch
.cursor/skills/verify-openbard/scripts/control-openbard doctor
.cursor/skills/verify-openbard/scripts/control-openbard url
.cursor/skills/verify-openbard/scripts/control-openbard get /health --expect 200 --save health
.cursor/skills/verify-openbard/scripts/control-openbard post-audio fixtures/c-major-chord.wav --expect 200 --save live-transcription
.cursor/skills/verify-openbard/scripts/control-openbard cleanup
```

`launch` is idempotent for a healthy instance of the same `OPENBARD_VERIFY_RUN_ID`. A second launch prints `already running` and leaves the process up.

Keep the map honest with `/maintain-verification-skill` when worker routes or fixtures change.
