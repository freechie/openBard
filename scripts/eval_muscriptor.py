#!/usr/bin/env python3
"""Evaluate MuScriptor on mixed-arrangement.wav.

Runs unconditioned transcription when the package imports. Writes blockers if
evaluation cannot finish.

MuScriptor weights are CC BY-NC 4.0. Local evaluation only.
"""
import json
import time
from pathlib import Path
from typing import Any

try:
    import psutil
    has_psutil = True
except ImportError:
    has_psutil = False
    print("WARNING: psutil not available, memory tracking disabled")


def load_ground_truth(path: Path) -> dict[str, Any]:
    with open(path) as f:
        return json.load(f)


def evaluate_muscriptor() -> dict[str, Any]:
    print("=" * 70)
        print("MuScriptor evaluation on mixed arrangement fixture")
    print("=" * 70)
    print()

    try:
        from muscriptor import TranscriptionModel
        print("MuScriptor imported successfully")
    except ImportError as e:
        return {
            "status": "blocked",
            "reason": "import_failed",
            "error": str(e),
            "message": "MuScriptor could not be imported",
        }

    try:
        print("Loading MuScriptor model (may download weights)...")
        model_start = time.time()
        model = TranscriptionModel.load_model()
        model_load_time = time.time() - model_start
        print(f"Model loaded in {model_load_time:.2f}s")
        print()
    except Exception as e:
        import traceback
        return {
            "status": "blocked",
            "reason": "model_load_failed",
            "error": str(e),
            "traceback": traceback.format_exc(),
            "message": f"Failed to load MuScriptor model: {type(e).__name__}",
        }

    repo_root = Path(__file__).resolve().parents[1]
    audio_path = repo_root / "fixtures" / "mixed-arrangement.wav"
    ground_truth_path = repo_root / "fixtures" / "mixed-arrangement-ground-truth.json"

    if not audio_path.exists():
        return {
            "status": "blocked",
            "reason": "missing_fixture",
            "message": f"Audio fixture not found at {audio_path}",
        }

    if not ground_truth_path.exists():
        return {
            "status": "blocked",
            "reason": "missing_ground_truth",
            "message": f"Ground truth not found at {ground_truth_path}",
        }

    ground_truth = load_ground_truth(ground_truth_path)
    print(f"Ground truth: {len(ground_truth['note_events'])} notes")
    print(f"Audio file: {audio_path.name} ({audio_path.stat().st_size / 1024:.1f} KB)")
    print()

    if has_psutil:
        process = psutil.Process()
        mem_before = process.memory_info().rss / 1024 / 1024  # MB
    else:
        mem_before = None

    try:
        print("Running MuScriptor transcription (unconditioned)...")
        start_time = time.time()

        events = list(model.transcribe(str(audio_path)))

        elapsed_time = time.time() - start_time

        if has_psutil:
            mem_after = process.memory_info().rss / 1024 / 1024  # MB
            mem_delta = mem_after - mem_before
        else:
            mem_after = None
            mem_delta = None

        print(f"Transcription completed in {elapsed_time:.2f}s")
        if has_psutil:
            print(f"  Memory usage: {mem_after:.1f} MB (delta {mem_delta:+.1f} MB)")
        print()

        from muscriptor import NoteStartEvent, NoteEndEvent

        note_starts = [e for e in events if isinstance(e, NoteStartEvent)]
        note_ends = [e for e in events if isinstance(e, NoteEndEvent)]

        print(f"MuScriptor detected {len(note_starts)} note start events")
        print(f"MuScriptor detected {len(note_ends)} note end events")
        print()

        if note_starts:
            print(f"Sample start event: {note_starts[0]}")
        if note_ends:
            print(f"Sample end event: {note_ends[0]}")
        print()

        return {
            "status": "success",
            "performance": {
                "latency_seconds": round(elapsed_time, 3),
                "memory_mb": round(mem_after, 1) if mem_after else None,
                "memory_delta_mb": round(mem_delta, 1) if mem_delta else None,
                "model_load_time_seconds": round(model_load_time, 3),
            },
            "detected_note_starts": len(note_starts),
            "detected_note_ends": len(note_ends),
            "ground_truth_notes": len(ground_truth['note_events']),
            "sample_start": str(note_starts[0]) if note_starts else None,
            "sample_end": str(note_ends[0]) if note_ends else None,
        }

    except Exception as e:
        import traceback
        return {
            "status": "blocked",
            "reason": "runtime_error",
            "error": str(e),
            "traceback": traceback.format_exc(),
            "message": f"MuScriptor execution failed: {type(e).__name__}",
        }


def main() -> None:
    result = evaluate_muscriptor()

    repo_root = Path(__file__).resolve().parents[1]
    results_path = repo_root / "fixtures" / "muscriptor-eval-results.json"

    with open(results_path, "w") as f:
        json.dump(result, f, indent=2)

    print()
    print(f"Results saved to: {results_path}")
    print()

    if result["status"] == "success":
        print("MuScriptor evaluation completed successfully")
        print(f"  Latency: {result['performance']['latency_seconds']}s")
        if result['performance']['memory_mb']:
            print(f"  Memory: {result['performance']['memory_mb']} MB")
    elif result["status"] == "blocked":
        print(f"FAIL: MuScriptor evaluation blocked: {result['reason']}")
        print(f"  {result['message']}")
        if 'error' in result:
            print(f"  Error: {result['error']}")
    elif result["status"] == "partial":
        print("WARN: MuScriptor ran with unexpected output format")
        print(f"  {result['message']}")

    print()
    print("=" * 70)


if __name__ == "__main__":
    main()
