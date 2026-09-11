"""Basic Pitch transcription adapter."""

from __future__ import annotations

import tempfile
from importlib.metadata import version
from pathlib import Path
from typing import BinaryIO

from app.engines.transcriber import Transcriber, TranscriptionError
from app.models import NoteEvent, TranscriptionResult


def midi_to_staff_hint(midi: int) -> str:
    """Assign staff hint from MIDI pitch. Middle C and above → treble."""
    if midi < 60:
        return "bass"
    return "treble"


class BasicPitchTranscriber(Transcriber):
    """Spotify Basic Pitch (Apache-2.0) for solo/isolated polyphonic audio."""

    def transcribe(self, audio_file: Path | BinaryIO) -> TranscriptionResult:
        path, cleanup = self._as_path(audio_file)
        try:
            try:
                from basic_pitch.inference import predict
            except ImportError as exc:
                raise TranscriptionError(
                    "basic-pitch is not installed or its backend failed to import"
                ) from exc

            try:
                _model_output, _midi_data, note_events = predict(str(path))
            except Exception as exc:  # noqa: BLE001 — surface any model failure
                raise TranscriptionError(f"Basic Pitch transcription failed: {exc}") from exc

            return self._to_result(note_events)
        finally:
            if cleanup is not None:
                cleanup.unlink(missing_ok=True)

    @property
    def engine_name(self) -> str:
        return "basic_pitch"

    @property
    def engine_version(self) -> str:
        return version("basic-pitch")

    def _as_path(self, audio_file: Path | BinaryIO) -> tuple[Path, Path | None]:
        if isinstance(audio_file, Path):
            return audio_file, None

        suffix = ".wav"
        name = getattr(audio_file, "name", "") or ""
        if isinstance(name, str) and Path(name).suffix:
            suffix = Path(name).suffix.lower()

        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            tmp.write(audio_file.read())
            tmp_path = Path(tmp.name)
        return tmp_path, tmp_path

    def _to_result(self, note_events: list) -> TranscriptionResult:
        # Basic Pitch note tuples: (start_s, end_s, pitch_midi, amplitude[, pitch_bends])
        # amplitude is already in [0, 1]. There is no separate confidence field;
        # map amplitude to both velocity and confidence rather than inventing 1.0.
        notes: list[NoteEvent] = []
        for event in note_events:
            start_s, end_s, pitch_midi, amplitude = event[0], event[1], event[2], event[3]
            duration = float(end_s) - float(start_s)
            if duration <= 0:
                continue
            amp = max(0.0, min(1.0, float(amplitude)))
            pitch = int(pitch_midi)
            notes.append(
                NoteEvent(
                    pitch_midi=pitch,
                    onset_seconds=max(0.0, float(start_s)),
                    duration_seconds=duration,
                    velocity=amp,
                    confidence=amp,
                    staff_hint=midi_to_staff_hint(pitch),
                )
            )
        notes.sort(key=lambda note: (note.onset_seconds, note.pitch_midi))
        return TranscriptionResult(
            engine=self.engine_name,
            engine_version=self.engine_version,
            tempo_bpm=None,
            key_guess=None,
            note_events=notes,
        )
