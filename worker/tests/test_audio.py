from pathlib import Path

from fastapi.testclient import TestClient

from app.main import DEMO_AUDIO_PATH, app

client = TestClient(app)


def test_demo_audio_returns_wav_fixture() -> None:
    response = client.get("/v1/audio/demo")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/wav")
    body = response.content
    assert body[:4] == b"RIFF"
    assert body[8:12] == b"WAVE"
    assert body == DEMO_AUDIO_PATH.read_bytes()


def test_transcribe_accepts_wav_and_returns_basic_pitch_notes() -> None:
    wav = Path(__file__).resolve().parents[2] / "fixtures" / "c-major-chord.wav"

    response = client.post(
        "/v1/transcriptions",
        files={"audio": ("c-major-chord.wav", wav.read_bytes(), "audio/wav")},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["engine"] == "basic_pitch"
    assert body["tempo_bpm"] is None
    assert body["key_guess"] is None
    pitches = sorted(note["pitch_midi"] for note in body["note_events"])
    assert pitches == [60, 64, 67]
    assert all(note["confidence"] == note["velocity"] for note in body["note_events"])


def test_transcribe_rejects_unsupported_type() -> None:
    response = client.post(
        "/v1/transcriptions",
        files={"audio": ("notes.txt", b"not audio", "text/plain")},
    )

    assert response.status_code == 400
