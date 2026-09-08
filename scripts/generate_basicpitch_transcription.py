#!/usr/bin/env python3
"""
Generate isolated-piano-basicpitch.json from Basic Pitch eval results.

Converts the predicted_notes from fixtures/basic-pitch-eval-results.json
into a transcription that matches contracts/transcription.schema.json.
"""
import json
from pathlib import Path


def midi_to_staff_hint(midi: int) -> str:
    """Assign staff hint based on MIDI pitch."""
    if midi < 60:
        return "bass"
    else:
        return "treble"


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    eval_results_path = repo_root / "fixtures" / "basic-pitch-eval-results.json"
    output_path = repo_root / "fixtures" / "isolated-piano-basicpitch.json"

    with open(eval_results_path) as f:
        eval_results = json.load(f)

    predicted_notes = eval_results["predicted_notes"]

    # Convert to transcription format
    note_events = []
    for note in predicted_notes:
        note_events.append({
            "pitch_midi": note["pitch_midi"],
            "onset_seconds": note["onset_seconds"],
            "duration_seconds": note["duration_seconds"],
            "velocity": note["velocity"],
            "confidence": note["confidence"],
            "staff_hint": midi_to_staff_hint(note["pitch_midi"]),
        })

    transcription = {
        "engine": "basic_pitch",
        "engine_version": "0.3.0",
        "tempo_bpm": None,
        "key_guess": None,
        "note_events": note_events,
    }

    with open(output_path, "w") as f:
        json.dump(transcription, f, indent=2)

    print(f"✓ Generated {output_path}")
    print(f"  {len(note_events)} notes from Basic Pitch")


if __name__ == "__main__":
    main()
