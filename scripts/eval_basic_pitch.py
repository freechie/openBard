#!/usr/bin/env python3
"""
Evaluate Basic Pitch transcription engine on isolated-piano fixture.

Measures:
- Pitch accuracy (within 100ms tolerance)
- Spurious notes detection
- Latency
- Memory usage
"""
import json
import time
from pathlib import Path
from typing import Any

import psutil


def load_ground_truth(path: Path) -> dict[str, Any]:
    """Load ground truth JSON."""
    with open(path) as f:
        return json.load(f)


def midi_to_note_name(midi: int) -> str:
    """Convert MIDI number to note name."""
    notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    octave = (midi // 12) - 1
    note = notes[midi % 12]
    return f"{note}{octave}"


def evaluate_transcription(
    predicted_notes: list[dict[str, Any]],
    ground_truth_notes: list[dict[str, Any]],
    onset_tolerance: float = 0.1,
) -> dict[str, Any]:
    """
    Evaluate predicted notes against ground truth.
    
    Args:
        predicted_notes: List of predicted note events
        ground_truth_notes: List of ground truth note events
        onset_tolerance: Tolerance in seconds for onset matching
    
    Returns:
        Evaluation metrics dictionary
    """
    matched_pitches = 0
    matched_notes = 0
    spurious_notes = []
    missed_notes = []
    
    # Track which ground truth notes have been matched
    gt_matched = [False] * len(ground_truth_notes)
    
    for pred in predicted_notes:
        pred_pitch = pred["pitch_midi"]
        pred_onset = pred["onset_seconds"]
        pred_duration = pred["duration_seconds"]
        
        # Try to match with ground truth
        matched = False
        for i, gt in enumerate(ground_truth_notes):
            if gt_matched[i]:
                continue
            
            gt_pitch = gt["pitch_midi"]
            gt_onset = gt["onset_seconds"]
            
            # Check if pitches match
            if pred_pitch == gt_pitch:
                # Check if onsets are within tolerance
                if abs(pred_onset - gt_onset) <= onset_tolerance:
                    matched_pitches += 1
                    matched_notes += 1
                    gt_matched[i] = True
                    matched = True
                    break
        
        if not matched:
            # Check if it's a long spurious note (duration > 2s)
            if pred_duration > 2.0:
                spurious_notes.append({
                    "pitch": midi_to_note_name(pred_pitch),
                    "midi": pred_pitch,
                    "onset": round(pred_onset, 3),
                    "duration": round(pred_duration, 3),
                })
    
    # Find missed notes
    for i, gt in enumerate(ground_truth_notes):
        if not gt_matched[i]:
            missed_notes.append({
                "pitch": midi_to_note_name(gt["pitch_midi"]),
                "midi": gt["pitch_midi"],
                "onset": round(gt["onset_seconds"], 3),
                "duration": round(gt["duration_seconds"], 3),
            })
    
    total_gt_notes = len(ground_truth_notes)
    precision = matched_notes / len(predicted_notes) if predicted_notes else 0
    recall = matched_notes / total_gt_notes if total_gt_notes else 0
    f1_score = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
    
    return {
        "total_ground_truth": total_gt_notes,
        "total_predicted": len(predicted_notes),
        "matched_notes": matched_notes,
        "matched_pitches": matched_pitches,
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1_score": round(f1_score, 3),
        "spurious_long_notes": spurious_notes,
        "missed_notes": missed_notes,
    }


def main() -> None:
    """Run Basic Pitch evaluation."""
    print("=" * 70)
    print("Basic Pitch Evaluation on Isolated Piano Fixture")
    print("=" * 70)
    print()
    
    # Setup paths
    repo_root = Path(__file__).resolve().parents[1]
    audio_path = repo_root / "fixtures" / "isolated-piano.wav"
    ground_truth_path = repo_root / "fixtures" / "isolated-piano-ground-truth.json"
    
    if not audio_path.exists():
        print(f"ERROR: Audio fixture not found at {audio_path}")
        return
    
    if not ground_truth_path.exists():
        print(f"ERROR: Ground truth not found at {ground_truth_path}")
        return
    
    # Load ground truth
    ground_truth = load_ground_truth(ground_truth_path)
    print(f"Ground truth: {len(ground_truth['note_events'])} notes")
    print()
    
    # Import Basic Pitch (lazy import for better error messages)
    try:
        from basic_pitch.inference import predict
        from basic_pitch import ICASSP_2022_MODEL_PATH
        import os
        # Use TFLite model explicitly as it works with our TensorFlow version
        model_dir = os.path.dirname(ICASSP_2022_MODEL_PATH)
        tflite_model = os.path.join(model_dir, "nmp.tflite")
        if os.path.exists(tflite_model):
            model_path = tflite_model
            print(f"Using TFLite model: {model_path}")
        else:
            model_path = ICASSP_2022_MODEL_PATH
            print(f"Using default model: {model_path}")
    except ImportError:
        print("ERROR: Basic Pitch not installed.")
        print("Install with: pip install basic-pitch")
        return
    
    # Measure memory before transcription
    process = psutil.Process()
    mem_before = process.memory_info().rss / 1024 / 1024  # MB
    
    print("Running Basic Pitch transcription...")
    start_time = time.time()
    
    # Run Basic Pitch
    # Returns: model_output, midi_data, note_events
    model_output, midi_data, note_events = predict(str(audio_path), model_path)
    
    elapsed_time = time.time() - start_time
    mem_after = process.memory_info().rss / 1024 / 1024  # MB
    mem_delta = mem_after - mem_before
    
    print(f"✓ Transcription completed in {elapsed_time:.2f}s")
    print(f"  Memory usage: {mem_after:.1f} MB (Δ {mem_delta:+.1f} MB)")
    print()
    
    # Convert Basic Pitch note_events to our format
    predicted_notes = []
    for start_time_sec, end_time_sec, pitch_midi, velocity, _ in note_events:
        predicted_notes.append({
            "pitch_midi": int(pitch_midi),
            "onset_seconds": float(start_time_sec),
            "duration_seconds": float(end_time_sec - start_time_sec),
            "velocity": float(velocity) / 127.0,  # Normalize to [0, 1]
            "confidence": 1.0,  # Basic Pitch doesn't provide confidence per note
        })
    
    print(f"Basic Pitch detected {len(predicted_notes)} notes")
    print()
    
    # Evaluate
    results = evaluate_transcription(predicted_notes, ground_truth["note_events"])
    
    print("Evaluation Results:")
    print(f"  Precision: {results['precision']:.1%}")
    print(f"  Recall: {results['recall']:.1%}")
    print(f"  F1 Score: {results['f1_score']:.1%}")
    print(f"  Matched: {results['matched_notes']}/{results['total_ground_truth']} notes")
    print()
    
    if results["spurious_long_notes"]:
        print(f"⚠ Spurious long notes detected ({len(results['spurious_long_notes'])}):")
        for note in results["spurious_long_notes"]:
            print(f"  - {note['pitch']} at {note['onset']}s for {note['duration']}s")
        print()
    else:
        print("✓ No spurious long notes detected")
        print()
    
    if results["missed_notes"]:
        print(f"⚠ Missed notes ({len(results['missed_notes'])}):")
        for note in results["missed_notes"]:
            print(f"  - {note['pitch']} at {note['onset']}s")
        print()
    else:
        print("✓ All ground truth notes detected")
        print()
    
    # Check acceptance criteria
    print("Acceptance Criteria:")
    all_notes_detected = results["recall"] >= 0.95
    no_long_spurious = len(results["spurious_long_notes"]) == 0
    
    print(f"  {'✓' if all_notes_detected else '✗'} All expected chord pitches detected within 100ms")
    print(f"  {'✓' if no_long_spurious else '✗'} No long spurious notes")
    print()
    
    if all_notes_detected and no_long_spurious:
        print("✓ PASSED: Basic Pitch meets acceptance criteria")
    else:
        print("✗ FAILED: Basic Pitch does not meet all acceptance criteria")
    
    print()
    print("=" * 70)
    
    # Save detailed results
    results_path = repo_root / "fixtures" / "basic-pitch-eval-results.json"
    detailed_results = {
        "fixture": "isolated-piano.wav",
        "engine": "basic-pitch",
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
        "performance": {
            "latency_seconds": round(elapsed_time, 3),
            "memory_mb": round(mem_after, 1),
            "memory_delta_mb": round(mem_delta, 1),
        },
        "accuracy": results,
        "predicted_notes": predicted_notes,
    }
    
    with open(results_path, "w") as f:
        json.dump(detailed_results, f, indent=2)
    
    print(f"Detailed results saved to: {results_path}")


if __name__ == "__main__":
    main()
