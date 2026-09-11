# openBard

openBard is an experimental iOS app. It turns recorded or imported music into
editable notes, then later into sheet music.

**Shipped today:** JSON contract, FastAPI worker with live Basic Pitch on
upload, iOS piano-roll edit loop, ScoreBuilder staff preview, MIDI and
MusicXML export from locked notes.
**Not shipped:** on-device inference, guided recording.
The iOS app still loads bundled JSON; it does not call the worker.

Status, shipped checklist, and next work: **[STATUS.md](STATUS.md)**.

## Product direction

openBard should transcribe one or more instruments from an audio file, a MIDI
file, or an on-device live recording. If several sources are too hard to
notate, the app isolates one instrument and builds an editable notation file
from that.

The first release must export MIDI and MusicXML so the file opens in other
notation software.

The first App Store version targets solo or isolated pitched instruments,
including polyphonic playing such as piano or guitar chords. Transcription
runs on-device when the model fits. That avoids a per-request server bill.
Recordings stay on the phone.

Full-song, multi-instrument transcription is a research track. The project
will not claim publication-ready notation from arbitrary commercial recordings.
Detecting notes and building a score are separate problems. They are built and
tested separately.

## MVP accuracy plan

1. **Constrain the problem.** Short clips, one clear instrument, guided
   recording with real-time gain, noise, and clipping meters so the engine
   gets clean input.

2. **Small on-device models per instrument.** Piano, guitar, and strings get
   their own networks instead of one generic network. Basic Pitch is the MVP
   candidate. An adapter lets you swap or blend models.

3. **Show model output before quantization.** The piano roll shows confidence
   scores, onset uncertainty, and possible octave or harmonic flags before any
   ScoreBuilder pass. Users see what the model detected.

4. **Edit, then lock, then score.** Start on a blank roll, Draw notes, Play to
   hear a synth preview, then lock and build the staff. Fixtures remain optional
   in Library.

5. **Fixture checks in CI.** Each model change must report recall and
   spurious-note rates on known chords and scales. An accuracy drop needs an
   explicit note in the change.

## Scope

### Publishable MVP

- Import or record a short solo or isolated instrument performance with guided
  recording (gain, noise, and clipping meters).
- Detect simultaneous notes, onsets, and durations with a small on-device
  model (Basic Pitch).
- Show raw transcription on an unquantized piano roll, including confidence,
  onset uncertainty, and harmonic or octave flags.
- Split, merge, or drag notes. Lock confirmed events.
- Convert locked note events into a staff preview with ScoreBuilder.
- Export MIDI and MusicXML for other notation software.
- CI checks recall and spurious-note rates on known fixtures.

### Research track

- Transcribe realistic multi-instrument mixes.
- Evaluate instrument-conditioned transcription (MuScriptor).
- Blend small per-instrument models.
- Keep experimental model code behind adapters so the app is not locked to one
  engine.

### Not in the first release

- Importing or downloading from Apple Music, YouTube, or other streaming
  services.
- Guaranteed separation of arbitrary instruments from dense mixes.
- Unbounded cloud processing or permanent storage of uploaded recordings.

## Architecture

```mermaid
flowchart LR
    A["Audio input + recording meters"] --> B["Transcriber adapter"]
    B --> C["Raw note events + confidence"]
    C --> D["Piano-roll editor"]
    D --> E["Validated note events"]
    E --> F["ScoreBuilder"]
    F --> G["Staff preview"]
    F --> H["MIDI / MusicXML export"]
```

The transcription JSON stores what was heard, in seconds, including confidence
and onset uncertainty. The piano-roll editor shows those fields and lets users
split, merge, or drag notes before locking them. After lock, `ScoreBuilder`
estimates beats and measures, quantizes durations, assigns voices, and creates
rests and ties.

ScoreBuilder runs only on locked notes. The staff is not the raw model output.

Model-specific dependencies and output mapping live behind a small transcriber
interface. Per-instrument models can load one at a time. Do not add a plugin
framework, model microservice, background job system, or source-separation
stage until measurements show you need them.

## Model and licensing policy

| Engine | Intended use | Current policy |
| --- | --- | --- |
| Fake engine | Contract and UI development | Included now (`GET /v1/transcriptions/demo`) |
| [Basic Pitch](https://github.com/spotify/basic-pitch) | Solo or isolated polyphonic instruments | MVP candidate; live on worker `POST /v1/transcriptions`; Apache-2.0 |
| [MuScriptor](https://github.com/muscriptor/muscriptor) | Full mixes and instrument-conditioned research | Local evaluation only until public App Store use is confirmed in writing; code is MIT, weights are CC BY-NC 4.0 |

openBard is a personal project with no licensing budget. Monetization is
undecided. Do not add a paid feature, ads, tips, or a public MuScriptor-powered
service until the model terms for that use are confirmed.

## Release gates

A public App Store build requires all of the following:

- a model license compatible with the exact release and monetization plan
- acceptable results on the project's fixture set
- a clear statement that users may process only audio they are authorized to
  use
- documented handling of recordings and generated results
- inference that does not require a per-request cloud bill, preferably by
  running on-device

## Repository layout

```text
STATUS.md   Shipped / next / gaps (read this for progress)
contracts/  Shared JSON schema and example transcription
fixtures/   Audio fixtures, ground truth, eval results
ios/        SwiftUI application and iOS tests
worker/     FastAPI worker, engine adapters, and Python tests
scripts/    verify, fixture generation, engine eval
```

## Development

### Worker

Requirements: Python 3.11 and [uv](https://docs.astral.sh/uv/).
`worker/pyproject.toml` sets `requires-python = ">=3.11,<3.13"` because of
Basic Pitch. GitHub Actions installs 3.11.

```bash
cd worker
uv sync
uv run uvicorn app.main:app --reload
```

Endpoints:

- `GET /health`
- `GET /v1/transcriptions/demo` (fake `dsp_v0` C major chord)
- `GET /v1/audio/demo`
- `POST /v1/transcriptions` (multipart field `audio`; live Basic Pitch)

```bash
# from repo root, with worker running
curl -F "audio=@fixtures/c-major-chord.wav" http://127.0.0.1:8000/v1/transcriptions
```

Worker tests: `cd worker && uv run pytest -q`

Full repo check on macOS with Xcode:

```bash
./scripts/verify
```

That command checks the locked Python environment, worker tests, dependency
advisories, and static analysis, then compiles the iOS app and test bundles
without code signing. GitHub Actions runs the same command on `macos-26`.

### iOS app

```bash
open ios/OpenBard/OpenBard.xcodeproj
```

The app loads bundled transcription JSON and WAV fixtures. It shows a piano
roll, edit toolbar, Score viewport (empty until Lock all), Play, and
Import audio (playback only). It does not call the worker.

## License

The application code and the synthesized `fixtures/c-major-chord.wav` are MIT.
See [LICENSE](LICENSE). Candidate transcription engines keep their own terms
under [Model and licensing policy](#model-and-licensing-policy). This is a
personal prototype. Do not assume pull requests are reviewed.

## Open decisions

- Whether MuScriptor's authors permit use in a free, ad-free personal App Store
  release.
- Whether a backend is ever necessary for the public application.
- What monetization model, if any, can fund the app after users validate the
  MVP.
