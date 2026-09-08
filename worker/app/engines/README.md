# Transcription Engine Adapters

This directory contains adapter implementations for different transcription engines.

## Architecture

The `Transcriber` abstract interface (`transcriber.py`) defines the contract for all engines:

```python
class Transcriber(ABC):
    def transcribe(self, audio_file: Path | BinaryIO) -> TranscriptionResult:
        """Returns note events with confidence scores."""

    @property
    def engine_name(self) -> str:
        """Engine identifier matching contracts/transcription.schema.json."""

    @property
    def engine_version(self) -> str:
        """Semantic version of the engine."""
```

## Implemented Engines

### FakeTranscriber (`fake.py`)
- Returns hardcoded C major chord
- Used for testing and demo endpoints
- No external dependencies

### Basic Pitch (planned)
- Spotify's Basic Pitch model
- Polyphonic transcription for solo/isolated instruments
- Apache 2.0 license
- See `docs/phase1-engine-decision.md` for evaluation results

## Adding a New Engine

1. Create a new file in this directory (e.g., `basic_pitch.py`)
2. Implement the `Transcriber` interface
3. Map model outputs to `TranscriptionResult`:
   - `tempo_bpm` and `key_guess` can be `None` if unsupported
   - Include confidence scores if available
   - Set `engine_name` to match the schema enum
4. Add tests in `tests/`
5. Update `main.py` to use the new engine

## Privacy and On-Device Direction

The long-term goal is **on-device transcription** for privacy and zero marginal cost. 
The worker architecture exists for:
- Development and testing without iOS simulator overhead
- Future optional cloud processing for heavy models
- Adapter pattern validation

Do not assume cloud processing is the production path.
