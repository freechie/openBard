from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse

from app.engines.fake import build_demo_transcription
from app.models import TranscriptionResult

REPO_ROOT = Path(__file__).resolve().parents[2]
DEMO_AUDIO_PATH = REPO_ROOT / "fixtures" / "c-major-chord.wav"
ALLOWED_AUDIO_SUFFIXES = {".wav", ".mp3", ".m4a", ".caf", ".aac"}

app = FastAPI(title="Audio2Score Worker")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/transcriptions/demo", response_model=TranscriptionResult)
def demo_transcription() -> TranscriptionResult:
    return build_demo_transcription()


@app.get("/v1/audio/demo")
def demo_audio() -> FileResponse:
    if not DEMO_AUDIO_PATH.is_file():
        raise HTTPException(status_code=500, detail="Demo audio fixture is missing")
    return FileResponse(
        DEMO_AUDIO_PATH,
        media_type="audio/wav",
        filename="c-major-chord.wav",
    )


@app.post("/v1/transcriptions", response_model=TranscriptionResult)
async def transcribe_audio(audio: UploadFile = File(...)) -> TranscriptionResult:
    filename = audio.filename or ""
    suffix = Path(filename).suffix.lower()
    if suffix not in ALLOWED_AUDIO_SUFFIXES:
        raise HTTPException(status_code=400, detail="Unsupported audio type")
    await audio.read()
    return build_demo_transcription()
