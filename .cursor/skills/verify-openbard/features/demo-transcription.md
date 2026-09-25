# Demo transcription

Demo transcription returns a canned C major chord from the fake `dsp_v0` engine without running Basic Pitch.

## Sub-features

- `demo-json` returns three treble notes at MIDI 60, 64, and 67.
- `demo-metadata` reports `engine` `dsp_v0`, `engine_version` `0.1.0`, `tempo_bpm` 120, and `key_guess` `C major`.

## How to get to it (user POV)

- Request `GET /v1/transcriptions/demo` on the worker URL.

## Driving it with control-openbard

Preconditions:

- The worker is healthy at `http://127.0.0.1:18765`.
- `control-openbard doctor` reports the expected URL.

- **Fetch demo.** Request the demo transcription. Run `.cursor/skills/verify-openbard/scripts/control-openbard get /v1/transcriptions/demo --expect 200 --save demo-transcription`. `body.json` has `engine` `dsp_v0`, `engine_version` `0.1.0`, `tempo_bpm` `120.0`, and `key_guess` `C major`.
- **Read notes.** Check `note_events`. There are three events. `pitch_midi` values are `60`, `64`, and `67` in that order. Each `onset_seconds` is `0.0`. Each `duration_seconds` is `2.0`. Each `staff_hint` is `treble`.
- **Proof.** Keep `$OPENBARD_VERIFY_EVIDENCE_DIR/demo-transcription/body.json`. The file must include those metadata fields and the three pitches. Matching `contracts/transcription.example.json` note events is sufficient.

## Gotchas

- This endpoint is not live inference. `engine` must stay `dsp_v0`. `basic_pitch` here means you hit `POST /v1/transcriptions` instead.
- `TestClient` against `app.main:app` is not this feature. Drive the launched server.
- Note order on demo is C, E, G as written, not a sorted copy of a different payload.
