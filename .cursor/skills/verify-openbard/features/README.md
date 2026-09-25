# openBard worker verification map

This directory is the maintained source for verifying the HTTP worker. Read this index before driving, then use the matching feature file as the recipe.

The iOS piano-roll app is a different surface. This map does not cover it.

## Baseline preconditions

- Launch with `.cursor/skills/verify-openbard/scripts/control-openbard launch` from the repo root.
- Default URL is `http://127.0.0.1:18765`. Override with `OPENBARD_VERIFY_HOST` and `OPENBARD_VERIFY_PORT`.
- Set `OPENBARD_VERIFY_EVIDENCE_DIR` to a directory that must survive cleanup.
- Put `uv` on `PATH` (`$HOME/.local/bin` after the uv installer).
- Run `control-openbard doctor` and require `title=openBard Worker` and `health={"status":"ok"}`.
- Never drive an instance that this verification run did not start.

## Driving conventions

- Start every recipe from the baseline state unless its preconditions say otherwise.
- Treat every command as literal. Keep paths, field names, and flags unchanged.
- Run HTTP through `control-openbard get` and `control-openbard post-audio`.
- Restore nothing after GET. POST does not write durable worker state. Cleanup still kills the process this run started.
- Do not remove proof artifacts during cleanup.

## Proof and skip reporting

- Capture the request line and the response body, not only the final status code.
- JSON proof includes `status.txt` and `body.json`.
- WAV proof includes `headers.txt` and `body.wav`, compared to `fixtures/c-major-chord.wav`.
- Record the feature ID and `--save` name with every artifact.
- Report an unreachable path with the attempted command and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with control-openbard` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

## Features

- [Health](./health.md) covers `GET /health` on a live worker.
- [Demo transcription](./demo-transcription.md) covers the fake `dsp_v0` C major JSON.
- [Demo audio](./demo-audio.md) covers the WAV bytes for `c-major-chord.wav`.
- [Live transcription](./live-transcription.md) covers Basic Pitch `POST /v1/transcriptions` and rejected types.
