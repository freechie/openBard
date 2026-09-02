from app.models import NoteEvent, TranscriptionResult

C_MAJOR_CHORD_PITCHES = (60, 64, 67)


def build_demo_transcription() -> TranscriptionResult:
    notes = [
        NoteEvent(
            pitch_midi=pitch,
            onset_seconds=0.0,
            duration_seconds=2.0,
            velocity=0.8,
            confidence=1.0,
            staff_hint="treble",
        )
        for pitch in C_MAJOR_CHORD_PITCHES
    ]
    return TranscriptionResult(
        engine="dsp_v0",
        engine_version="0.1.0",
        tempo_bpm=120,
        key_guess="C major",
        note_events=notes,
    )
