import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
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
