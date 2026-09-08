from typing import Literal

from pydantic import BaseModel, Field


class NoteEvent(BaseModel):
    pitch_midi: int = Field(ge=0, le=127)
    onset_seconds: float = Field(ge=0)
    duration_seconds: float = Field(gt=0)
    velocity: float = Field(ge=0, le=1)
    confidence: float = Field(ge=0, le=1)
    onset_uncertainty_seconds: float | None = Field(default=None, ge=0)
    staff_hint: Literal["treble", "bass", "unknown"] = "unknown"


class TranscriptionResult(BaseModel):
    engine: str
    engine_version: str
    tempo_bpm: float | None = Field(default=None, gt=0)
    key_guess: str | None = None
    note_events: list[NoteEvent]
