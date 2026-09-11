# openBard status

Single source of truth for what has shipped and what is next.
Product direction and how to run the project live in [README.md](README.md).

**Updated:** 2026-09-11

## Next

1. Phase 4: guided recording + on-device Basic Pitch (app still uses bundled JSON only).
2. Edit polish: multi-select, undo/redo, editable velocity pins, richer overview; open exported MusicXML in MuseScore and document limits.

## Shipped

### Phase 0 — Prototype baseline
- Transcription JSON schema + example (`contracts/`)
- FastAPI worker: `GET /health`, `GET /v1/transcriptions/demo`, `GET /v1/audio/demo`
- Fake engine for demo/contract tests
- SwiftUI app loads bundled demo transcription + WAV playback / import-for-playback

### Phase 1 — Engine decision
- Fixtures: `isolated-piano.wav`, `mixed-arrangement.wav` + ground truth
- **Basic Pitch** chosen for publishable MVP (solo/isolated polyphonic)
- Eval on isolated piano: 100% recall, 0 long spurious notes, ~0.5s latency, Apache-2.0
- MuScriptor: research only (gated HF weights, CC BY-NC 4.0) — not for App Store without written permission
- Artifacts: `fixtures/basic-pitch-eval-results.json`, `scripts/eval_*.py`, `scripts/check_basicpitch_eval.py` in CI

### Phase 2 / 2b — Piano roll and edit loop
- `Transcriber` adapter; **`BasicPitchTranscriber`** on `POST /v1/transcriptions` (live inference)
- Demo GET still fake `dsp_v0`; amplitude mapped to velocity + confidence (no invented 1.0)
- Contract: optional tempo/key, `onset_uncertainty_seconds`, `basic_pitch` engine enum
- iOS: fixture picker (incl. precomputed `isolated-piano-basicpitch.json`), confidence opacity on piano roll
- Edit: Ableton-style transport (BPM default 120, Play/Stop, Draw); clip overview hotspot for zoom/pan; stable pitch viewport; L/R edge resize + drag move; Library New blank / fixtures optional
- Score builds from **all notes** (no lock gate); MIDI/MusicXML export from note list; Play synthesizes current notes
- Pinch-zoom time window on piano roll; staff still uses ZoomableViewport
- Worker + iOS unit tests; fixture-backed Basic Pitch recall check in `./scripts/verify`

### Phase 3 — Score (partial)
- `ScoreBuilder` from **locked** notes only (tempo/beat estimate, quantize, rests/ties/clef)
- Staff preview after Lock all
- **MIDI export** (Format 0 SMF) from locked notes via Score workspace ShareLink
- **MusicXML export** (partwise 3.1) from ScoreBuilder via Score workspace ShareLink
  - Limits: C major key only, no dotted rhythm encoding, rests typed but simple; validate in MuseScore

## Not shipped

| Area | Gap |
| --- | --- |
| Export | External-app validation notes for MusicXML (MuseScore); richer rhythm/key encoding |
| iOS ↔ engine | App does **not** call the worker; no on-device Basic Pitch yet |
| Import | User files are playback-only; piano roll stays on bundled JSON |
| Recording | No live capture, meters, or guided UX |
| Edit polish | Undo/redo, multi-select, velocity-lane pin editing, persist edited JSON |
| Research | MuScriptor multi-instrument; per-instrument models; larger fixture set |

## Honest limitations

- Worker live path needs a Basic Pitch backend (CoreML on macOS; TF/TFLite/ONNX elsewhere). `setuptools` pinned `<81` for `resampy`.
- Basic Pitch has no tempo/key; those fields stay null on live POST.
- Precision on isolated piano was ~57% (extra harmonics/phantoms); users edit before lock.
- Staff preview is deterministic for known fixtures, not publication-ready engraving.

## Verify quickly

```bash
# Worker tests + live upload
cd worker && uv sync && uv run pytest -q
uv run uvicorn app.main:app --reload
# elsewhere, from repo root:
curl -F "audio=@fixtures/c-major-chord.wav" http://127.0.0.1:8000/v1/transcriptions
# expect engine basic_pitch, pitches 60/64/67

# Full check (macOS + Xcode)
./scripts/verify
```

iOS: open `ios/OpenBard/OpenBard.xcodeproj`, run simulator — bundled fixtures + edit + Lock all → staff.
