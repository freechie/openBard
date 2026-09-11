import json
from pathlib import Path

from jsonschema import Draft7Validator

from app.engines.basic_pitch import BasicPitchTranscriber, midi_to_staff_hint

REPO_ROOT = Path(__file__).resolve().parents[2]
C_MAJOR_WAV = REPO_ROOT / "fixtures" / "c-major-chord.wav"
SCHEMA_PATH = REPO_ROOT / "contracts" / "transcription.schema.json"


def test_midi_to_staff_hint() -> None:
    assert midi_to_staff_hint(59) == "bass"
    assert midi_to_staff_hint(60) == "treble"


def test_basic_pitch_transcribes_c_major_chord() -> None:
    result = BasicPitchTranscriber().transcribe(C_MAJOR_WAV)

    assert result.engine == "basic_pitch"
    assert result.tempo_bpm is None
    assert result.key_guess is None
    pitches = sorted(note.pitch_midi for note in result.note_events)
    assert pitches == [60, 64, 67]
    assert all(0.0 <= note.confidence <= 1.0 for note in result.note_events)
    assert all(note.confidence == note.velocity for note in result.note_events)
    assert all(note.duration_seconds > 0 for note in result.note_events)

    schema = json.loads(SCHEMA_PATH.read_text())
    payload = result.model_dump(mode="json", exclude_none=True)
    Draft7Validator(schema).validate(payload)
