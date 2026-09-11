# Live transcription

Live transcription uploads audio to Basic Pitch and returns note events in the shared transcription JSON shape.

## Sub-features

- `live-c-major` transcribes `fixtures/c-major-chord.wav` to MIDI pitches 60, 64, and 67.
- `live-metadata` reports `engine` `basic_pitch` with `tempo_bpm` and `key_guess` JSON null.
- `live-confidence` copies model amplitude into both `velocity` and `confidence`.
- `live-reject-type` rejects an upload whose suffix is not an allowed audio type.

## How to get to it (user POV)

- `POST /v1/transcriptions` with multipart field `audio` set to a `.wav`, `.mp3`, `.m4a`, `.caf`, or `.aac` file.
- From the repo root, `curl -F "audio=@fixtures/c-major-chord.wav" http://127.0.0.1:18765/v1/transcriptions`.

## Driving it with control-openbard

Preconditions:

- The worker is healthy at `http://127.0.0.1:18765`.
- `control-openbard doctor` reports the expected URL.
- `fixtures/c-major-chord.wav` exists.

- **Upload chord.** Send the C major fixture. Run `.cursor/skills/verify-openbard/scripts/control-openbard post-audio fixtures/c-major-chord.wav --expect 200 --save live-transcription`. `status.txt` is `200`.
- **Read engine.** `body.json` has `engine` `basic_pitch`. `tempo_bpm` is JSON null. `key_guess` is JSON null.
- **Read pitches.** Sorted `pitch_midi` values are `60`, `64`, and `67`. There are three notes.
- **Read amplitude mapping.** For every note, `confidence` equals `velocity`. Each `duration_seconds` is greater than 0. Each `staff_hint` is `treble`.
- **Reject type.** Upload a `.txt` file. Run `curl -sS -D - -o /tmp/openbard-reject.json -F "audio=@-;filename=notes.txt;type=text/plain" "$(.cursor/skills/verify-openbard/scripts/control-openbard url)/v1/transcriptions" <<< 'not audio'`. HTTP status is 400. Body is `{"detail":"Unsupported audio type"}`. Copy those headers and body into `$OPENBARD_VERIFY_EVIDENCE_DIR/live-transcription-reject/` if you need them for the same run.
- **Proof.** Keep `$OPENBARD_VERIFY_EVIDENCE_DIR/live-transcription/request.txt` and `body.json`. The request names `fixtures/c-major-chord.wav`. The body shows `basic_pitch` and pitches 60, 64, and 67.

## Gotchas

- The first POST after process start can take several seconds while Basic Pitch loads. Wait for HTTP 200. Do not kill the worker at 1 second.
- `GET /v1/transcriptions/demo` is the fake engine. It does not prove live transcription.
- Allowed suffixes are `.wav`, `.mp3`, `.m4a`, `.caf`, and `.aac`. The worker keys off the filename suffix, not only `Content-Type`.
- Basic Pitch does not guess tempo or key. Nulls are required. A filled tempo here is the wrong endpoint or a stale mock.
- Extra harmonic pitches on other fixtures are expected. The C major smoke fixture must stay 60, 64, and 67.
- iOS does not call this endpoint. A passing POST does not prove the piano-roll app.
