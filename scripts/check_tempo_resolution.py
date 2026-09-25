#!/usr/bin/env python3
"""Linux check for tempo-null load: one BPM for roll, score, MIDI, and the first plus tap.

Ports ScoreBuilder.estimateTempoBpm / clampTempo and ContentView's UI default and
adjustTempo. Linux has no Swift toolchain, so this locks the arithmetic. The Swift
tests lock TranscriptionLoader.loadFixture.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

UI_DEFAULT_BPM = 120.0


def clamp_tempo(bpm: float) -> float:
    return min(max(bpm, 40), 208)


def snap_beat_seconds(interval: float) -> float:
    candidates = [0.25, 0.5, 1.0, 2.0]
    return min(candidates, key=lambda candidate: abs(candidate - interval))


def snap_power_of_two_beats(beats: float) -> float:
    candidates = [1.0, 2.0, 4.0, 8.0]
    return min(candidates, key=lambda candidate: abs(candidate - beats))


def estimate_tempo_bpm(notes: list[dict]) -> float:
    onsets = sorted({note["onset_seconds"] for note in notes})
    if len(onsets) >= 2:
        intervals = sorted(later - earlier for earlier, later in zip(onsets, onsets[1:]))
        median = intervals[len(intervals) // 2]
        return clamp_tempo(60.0 / snap_beat_seconds(median))

    start = min((note["onset_seconds"] for note in notes), default=0)
    end = max(
        (note["onset_seconds"] + note["duration_seconds"] for note in notes),
        default=start,
    )
    span = max(end - start, 0.001)
    beat_seconds = max(span / snap_power_of_two_beats(span / 0.5), 0.25)
    return clamp_tempo(60.0 / beat_seconds)


def resolving_missing_tempo(tempo_bpm: float | None, notes: list[dict]) -> float | None:
    if tempo_bpm is None and notes:
        return estimate_tempo_bpm(notes)
    return tempo_bpm


def ui_bpm(tempo_bpm: float | None) -> float:
    return UI_DEFAULT_BPM if tempo_bpm is None else tempo_bpm


def score_bpm(notes: list[dict], tempo_bpm: float | None) -> float:
    if tempo_bpm is None:
        return estimate_tempo_bpm(notes)
    return clamp_tempo(tempo_bpm)


def midi_bpm(notes: list[dict], tempo_bpm: float | None) -> float:
    return clamp_tempo(tempo_bpm if tempo_bpm is not None else estimate_tempo_bpm(notes))


def first_plus_tap(tempo_bpm: float | None) -> float:
    current = tempo_bpm if tempo_bpm is not None else UI_DEFAULT_BPM
    return clamp_tempo(current + 1)


def load_fixture(path: Path) -> tuple[float | None, list[dict]]:
    payload = json.loads(path.read_text())
    notes = [
        {
            "onset_seconds": event["onset_seconds"],
            "duration_seconds": event["duration_seconds"],
        }
        for event in payload["note_events"]
    ]
    return payload.get("tempo_bpm"), notes


def surfaces(tempo_bpm: float | None, notes: list[dict]) -> dict[str, float]:
    return {
        "ui": ui_bpm(tempo_bpm),
        "score": score_bpm(notes, tempo_bpm),
        "midi": midi_bpm(notes, tempo_bpm),
        "tap": first_plus_tap(tempo_bpm),
    }


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    isolated_path = repo_root / "fixtures" / "isolated-piano-basicpitch.json"
    mixed_path = repo_root / "fixtures" / "mixed-arrangement-ground-truth.json"
    example_path = repo_root / "contracts" / "transcription.example.json"

    isolated_json, isolated_notes = load_fixture(isolated_path)
    mixed_json, mixed_notes = load_fixture(mixed_path)
    example_json, example_notes = load_fixture(example_path)

    if isolated_json is not None:
        return fail("isolated-piano-basicpitch.json must keep tempo_bpm null")
    if mixed_json != 120:
        return fail(f"mixed arrangement json tempo_bpm is {mixed_json}, expected 120")
    if example_json != 120:
        return fail(f"example json tempo_bpm is {example_json}, expected 120")

    before = surfaces(isolated_json, isolated_notes)
    stored = resolving_missing_tempo(isolated_json, isolated_notes)
    after = surfaces(stored, isolated_notes)
    mixed_after = surfaces(resolving_missing_tempo(mixed_json, mixed_notes), mixed_notes)
    example_after = surfaces(resolving_missing_tempo(example_json, example_notes), example_notes)

    print("Isolated Piano (tempo_bpm null in JSON)")
    print(
        f"  before load: UI={before['ui']:.0f} score={before['score']:.0f} "
        f"MIDI={before['midi']:.0f} plus-tap={before['tap']:.0f}"
    )
    print(f"  stored after load: {stored:.0f} BPM")
    print(
        f"  after load: UI={after['ui']:.0f} score={after['score']:.0f} "
        f"MIDI={after['midi']:.0f} plus-tap={after['tap']:.0f}"
    )

    if before != {"ui": 120.0, "score": 60.0, "midi": 60.0, "tap": 121.0}:
        return fail(f"raw Isolated Piano surfaces changed: {before}")
    if stored != 60.0:
        return fail(f"stored Isolated Piano tempo is {stored}, expected 60")
    if after != {"ui": 60.0, "score": 60.0, "midi": 60.0, "tap": 61.0}:
        return fail(f"resolved Isolated Piano surfaces are {after}")
    if mixed_after["ui"] != 120.0 or example_after["ui"] != 120.0:
        return fail("explicit 120 BPM JSON must stay 120")

    ninety = estimate_tempo_bpm(
        [{"onset_seconds": t, "duration_seconds": 0.25} for t in (0.0, 2 / 3, 4 / 3, 2.0)]
    )
    eleven_ms = estimate_tempo_bpm(
        [{"onset_seconds": t, "duration_seconds": 0.25} for t in (0.0, 0.011)]
    )
    two_s = estimate_tempo_bpm(
        [{"onset_seconds": t, "duration_seconds": 0.25} for t in (0.0, 2.0, 4.0)]
    )
    if (ninety, eleven_ms, two_s) != (120.0, 208.0, 40.0):
        return fail(f"estimator samples are {(ninety, eleven_ms, two_s)}, expected (120, 208, 40)")

    print("Explicit 120 BPM fixtures stay 120 after load")
    print("Estimator samples: 90 BPM IOI -> 120, 11 ms -> 208, 2 s -> 40")
    print("OK Isolated Piano load stores 60 BPM for roll, score, MIDI, and plus-tap 61")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
