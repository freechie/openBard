from fastapi.testclient import TestClient

from app.engines.fake import C_MAJOR_CHORD_PITCHES, build_demo_transcription
from app.main import app

client = TestClient(app)


def test_fake_engine_returns_c_major_chord() -> None:
    result = build_demo_transcription()

    assert result.engine == "dsp_v0"
    assert result.key_guess == "C major"
    assert [note.pitch_midi for note in result.note_events] == list(
        C_MAJOR_CHORD_PITCHES
    )
    assert all(note.onset_seconds == 0.0 for note in result.note_events)
    assert all(note.duration_seconds == 2.0 for note in result.note_events)


def test_demo_endpoint_returns_note_events() -> None:
    response = client.get("/v1/transcriptions/demo")

    assert response.status_code == 200

    body = response.json()
    assert body["engine"] == "dsp_v0"
    assert body["tempo_bpm"] == 120
    assert len(body["note_events"]) == 3
    assert [note["pitch_midi"] for note in body["note_events"]] == [60, 64, 67]
    assert body["note_events"][0]["onset_seconds"] == 0.0
