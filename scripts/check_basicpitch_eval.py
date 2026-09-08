#!/usr/bin/env python3
"""
Verify Basic Pitch evaluation results meet acceptance criteria.

Checks fixtures/basic-pitch-eval-results.json for:
- Recall >= 95% (all expected notes detected)
- No spurious long notes (duration > 2s)

This ensures the Basic Pitch path doesn't regress.
"""
import json
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    results_path = repo_root / "fixtures" / "basic-pitch-eval-results.json"

    if not results_path.exists():
        print(f"ERROR: {results_path} not found")
        return 1

    with open(results_path) as f:
        results = json.load(f)

    accuracy = results["accuracy"]
    recall = accuracy["recall"]
    spurious_count = len(accuracy["spurious_long_notes"])

    print(f"Basic Pitch eval results (isolated-piano.wav):")
    print(f"  Recall: {recall:.1%}")
    print(f"  Spurious long notes: {spurious_count}")

    acceptance_recall = recall >= 0.95
    acceptance_spurious = spurious_count == 0

    if acceptance_recall and acceptance_spurious:
        print("✓ Basic Pitch meets acceptance criteria")
        return 0
    else:
        if not acceptance_recall:
            print(f"✗ FAIL: Recall {recall:.1%} < 95%")
        if not acceptance_spurious:
            print(f"✗ FAIL: Found {spurious_count} spurious long notes")
        return 1


if __name__ == "__main__":
    sys.exit(main())
