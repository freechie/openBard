# Transcription Engine Adapters

`Transcriber` (`transcriber.py`) is the swap point for engines.

## Engines

| Engine | File | Used by |
| --- | --- | --- |
| Fake | `fake.py` | `GET /v1/transcriptions/demo`, contract tests |
| Basic Pitch | `basic_pitch.py` | `POST /v1/transcriptions` (live) |

Basic Pitch maps model amplitude to both `velocity` and `confidence`. Tempo and
key stay `null`. Decision and eval numbers: [README.md § Status](../../../README.md#status).

## Adding an engine

1. Implement `Transcriber` in this directory.
2. Map outputs to `TranscriptionResult` without inventing fields the model
   does not provide. Register `engine` in `contracts/transcription.schema.json`.
3. Add tests under `tests/`.
4. Wire `main.py` (or keep fake for demo and live for POST).

## On-device direction

Long-term inference should run on-device. The worker is for development,
fixture eval, and adapter validation — not the assumed production path.
