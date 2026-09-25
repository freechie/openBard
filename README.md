# openBard

openBard is an experimental iOS app. You edit note events on a piano roll, hear a
sine preview, and export MIDI and MusicXML. Import posts audio to the FastAPI
worker (`POST /v1/transcriptions`) and puts the returned notes on the roll.

![openBard piano roll on iOS](docs/ios-piano-roll.jpg)

## iOS app

Open the Xcode project.

```bash
open ios/OpenBard/OpenBard.xcodeproj
```

The app launches on a blank piano roll with Draw turned on. Draw notes, pinch or
drag the clip overview to zoom time, tap Play for a sine preview, then switch to
Score for a staff plus MIDI and MusicXML export. Library can load bundled
fixtures or import audio. Import sends the file to the worker and plays it
locally. The default worker URL is `http://127.0.0.1:8000` (Simulator to the
uvicorn port below). Change it in Library if your worker listens elsewhere.

## Worker

The worker needs Python 3.11 and [uv](https://docs.astral.sh/uv/).

```bash
cd worker
uv sync
uv run uvicorn app.main:app --reload
```

From the repo root, with the worker running, transcribe a fixture.

```bash
curl -F "audio=@fixtures/c-major-chord.wav" http://127.0.0.1:8000/v1/transcriptions
```

Worker tests run with `cd worker && uv run pytest -q`. On macOS with Xcode,
`./scripts/verify` runs those checks and compiles the iOS app.

## Where the code lives

```text
ios/        SwiftUI app and tests
worker/     FastAPI worker and Python tests
contracts/  Transcription JSON schema
fixtures/   Audio fixtures and eval results
scripts/    Verify, fixture generation, engine eval
docs/       Screenshots
```

## License

Application code and the synthesized `fixtures/c-major-chord.wav` are MIT. See
[LICENSE](LICENSE). Transcription engines keep their own terms.
