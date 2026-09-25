from contextlib import asynccontextmanager, suppress
from io import BytesIO
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse

from app.engines.basic_pitch import BasicPitchTranscriber
from app.engines.fake import build_demo_transcription
from app.engines.transcriber import TranscriptionError
from app.models import TranscriptionResult

REPO_ROOT = Path(__file__).resolve().parents[2]
DEMO_AUDIO_PATH = REPO_ROOT / "fixtures" / "c-major-chord.wav"
ALLOWED_AUDIO_SUFFIXES = {".wav", ".mp3", ".m4a", ".caf", ".aac"}

_transcriber = BasicPitchTranscriber()


@asynccontextmanager
async def lifespan(_: FastAPI):
    with suppress(TranscriptionError):
        _transcriber.load_model()
    yield


app = FastAPI(title="openBard Worker", lifespan=lifespan)


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
def transcribe_audio(audio: UploadFile = File(...)) -> TranscriptionResult:
    suffix = Path(audio.filename or "").suffix.lower()
    if suffix not in ALLOWED_AUDIO_SUFFIXES:
        raise HTTPException(status_code=400, detail="Unsupported audio type")

    payload = BytesIO(audio.file.read())
    payload.name = audio.filename or f"upload{suffix}"
    try:
        return _transcriber.transcribe(payload)
    except TranscriptionError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
