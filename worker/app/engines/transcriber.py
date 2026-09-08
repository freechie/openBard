"""
Transcriber adapter interface for openBard.

This interface abstracts the transcription engine from the application logic,
allowing different models (Basic Pitch, MuScriptor, on-device Core ML) to be
swapped without changing the API contract.
"""
from abc import ABC, abstractmethod
from pathlib import Path
from typing import BinaryIO

from app.models import TranscriptionResult


class Transcriber(ABC):
    """Abstract interface for audio transcription engines."""

    @abstractmethod
    def transcribe(self, audio_file: Path | BinaryIO) -> TranscriptionResult:
        """
        Transcribe audio to note events.

        Args:
            audio_file: Path to audio file or file-like object

        Returns:
            TranscriptionResult with detected notes, confidence scores,
            and optional tempo/key estimates.

        Raises:
            TranscriptionError: If transcription fails
        """
        pass

    @property
    @abstractmethod
    def engine_name(self) -> str:
        """Return the engine identifier (e.g., 'basic_pitch', 'dsp_v0')."""
        pass

    @property
    @abstractmethod
    def engine_version(self) -> str:
        """Return the engine version string (semver)."""
        pass


class TranscriptionError(Exception):
    """Raised when transcription fails."""

    pass
