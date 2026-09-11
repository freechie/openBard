# Fixtures

| File | Role |
| --- | --- |
| `c-major-chord.wav` | 2s mono C4–E4–G4 (original synth); demo + POST smoke test |
| `isolated-piano.wav` + `*-ground-truth.json` | Phase 1 Basic Pitch eval (12 notes) |
| `isolated-piano-basicpitch.json` | Precomputed Basic Pitch notes for iOS fixture picker |
| `mixed-arrangement.wav` + ground truth | Multi-instrument research fixture |
| `basic-pitch-eval-results.json` | Committed eval metrics (CI checks recall) |
| `muscriptor-eval-results.json` | MuScriptor blocker notes |

Matching demo note events for the C major chord: `contracts/transcription.example.json`.
