import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from app.engines.basic_pitch import BasicPitchTranscriber, amplitude_fields
from eval_basic_pitch import predicted_notes_from_events

FIXTURE = REPO_ROOT / "fixtures" / "isolated-piano-basicpitch.json"
IOS_COPY = REPO_ROOT / "ios" / "OpenBard" / "OpenBard" / "isolated-piano-basicpitch.json"


def test_isolated_piano_fixture_uses_amplitude_as_velocity_and_confidence() -> None:
    payload = json.loads(FIXTURE.read_text())
    notes = payload["note_events"]
    assert notes
    velocities = [note["velocity"] for note in notes]
    assert min(velocities) >= 0.2
    assert max(velocities) <= 1.0
    assert all(note["confidence"] == note["velocity"] for note in notes)
    assert any(note["confidence"] != 1.0 for note in notes)


def test_isolated_piano_ios_copy_matches_fixtures_copy() -> None:
    assert FIXTURE.read_text() == IOS_COPY.read_text()


def test_to_result_maps_amplitude_to_velocity_and_confidence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr("app.engines.basic_pitch.version", lambda _name: "0.4.0")
    result = BasicPitchTranscriber()._to_result([(0.0, 1.0, 60, 0.5)])
    note = result.note_events[0]
    assert note.velocity == 0.5
    assert note.confidence == 0.5


def test_eval_maps_amplitude_tuple_to_velocity_and_confidence() -> None:
    notes = predicted_notes_from_events([(0.0, 1.0, 60, 0.5, None)])
    assert notes[0]["velocity"] == 0.5
    assert notes[0]["confidence"] == 0.5


def test_amplitude_fields_uses_unit_interval_directly() -> None:
    velocity, confidence = amplitude_fields(0.5)
    assert velocity == 0.5
    assert confidence == 0.5


def test_amplitude_fields_clamps_to_unit_interval() -> None:
    assert amplitude_fields(1.2) == (1.0, 1.0)
    assert amplitude_fields(-0.1) == (0.0, 0.0)
