# Demo audio

Demo audio downloads the bundled C major chord WAV that the worker serves as `c-major-chord.wav`.

## Sub-features

- `demo-wav-headers` returns `Content-Type` `audio/wav` and filename `c-major-chord.wav`.
- `demo-wav-bytes` returns the same bytes as `fixtures/c-major-chord.wav`.

## How to get to it (user POV)

- Request `GET /v1/audio/demo` on the worker URL.

## Driving it with control-openbard

Preconditions:

- The worker is healthy at `http://127.0.0.1:18765`.
- `fixtures/c-major-chord.wav` exists in the repo.

- **Download audio.** Request the demo WAV. Run `.cursor/skills/verify-openbard/scripts/control-openbard get /v1/audio/demo --expect 200 --save demo-audio`. `status.txt` is `200`.
- **Check headers.** `headers.txt` contains `content-type: audio/wav` and `filename="c-major-chord.wav"`.
- **Check bytes.** `body.wav` starts with `RIFF` and `WAVE` at offset 8. `cmp body.wav fixtures/c-major-chord.wav` exits 0.
- **Proof.** Keep `$OPENBARD_VERIFY_EVIDENCE_DIR/demo-audio/body.wav` and `headers.txt`.

## Gotchas

- HTTP 500 with `Demo audio fixture is missing` means `fixtures/c-major-chord.wav` is absent from the checkout. Restore the fixture. Do not stub the bytes.
- A JSON transcription is a different feature. Do not treat `GET /v1/transcriptions/demo` as audio proof.
