from pathlib import Path
from typing import BinaryIO

from app.engines.transcriber import Transcriber
from app.models import NoteEvent, TranscriptionResult

C_MAJOR_CHORD_PITCHES = (60, 64, 67)


class FakeTranscriber(Transcriber):
    """Demo transcriber that returns a hardcoded C major chord."""

    def transcribe(self, audio_file: Path | BinaryIO) -> TranscriptionResult:
        notes = [
            NoteEvent(
                pitch_midi=pitch,
                onset_seconds=0.0,
                duration_seconds=2.0,
                velocity=0.8,
                confidence=1.0,
                staff_hint="treble",
            )
            for pitch in C_MAJOR_CHORD_PITCHES
        ]
        return TranscriptionResult(
            engine=self.engine_name,
            engine_version=self.engine_version,
            tempo_bpm=120.0,
            key_guess="C major",
            note_events=notes,
        )

    @property
    def engine_name(self) -> str:
        return "dsp_v0"

    @property
    def engine_version(self) -> str:
        return "0.1.0"


def build_demo_transcription() -> TranscriptionResult:
    """Compatibility wrapper for existing tests."""
    return FakeTranscriber().transcribe(Path("/dev/null"))
