from abc import ABC, abstractmethod
from pathlib import Path
from typing import BinaryIO

from app.models import TranscriptionResult


class Transcriber(ABC):
    @abstractmethod
    def transcribe(self, audio_file: Path | BinaryIO) -> TranscriptionResult:
        pass

    @property
    @abstractmethod
    def engine_name(self) -> str:
        pass

    @property
    @abstractmethod
    def engine_version(self) -> str:
        pass


class TranscriptionError(Exception):
    pass
