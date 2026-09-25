#!/usr/bin/env python3
"""Write isolated-piano.wav and mixed-arrangement.wav plus ground-truth JSON."""
import json
from pathlib import Path
from typing import Any

import numpy as np
from scipy.io import wavfile


def midi_to_freq(midi_note: int) -> float:
    return 440.0 * 2.0 ** ((midi_note - 69) / 12.0)


def generate_piano_tone(
    freq: float,
    duration: float,
    sample_rate: int = 44100,
    amplitude: float = 0.3,
) -> np.ndarray:
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    
    # Piano-like harmonic series with decay
    harmonics = [1.0, 0.5, 0.25, 0.15, 0.1, 0.05]
    signal = np.zeros_like(t)
    
    for i, harmonic_amp in enumerate(harmonics, start=1):
        signal += harmonic_amp * np.sin(2 * np.pi * freq * i * t)
    
    # ADSR envelope approximation (simple exponential decay)
    attack = 0.01
    decay_rate = 2.0
    envelope = np.ones_like(t)
    attack_samples = int(attack * sample_rate)
    envelope[:attack_samples] = np.linspace(0, 1, attack_samples)
    envelope[attack_samples:] *= np.exp(-decay_rate * t[attack_samples:] / duration)
    
    return amplitude * signal * envelope


def generate_bass_tone(
    freq: float,
    duration: float,
    sample_rate: int = 44100,
    amplitude: float = 0.25,
) -> np.ndarray:
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    
    signal = np.sin(2 * np.pi * freq * t)
    signal += 0.3 * np.sin(2 * np.pi * freq * 2 * t)
    signal += 0.15 * np.sin(2 * np.pi * freq * 3 * t)
    
    attack = 0.02
    decay_rate = 1.5
    envelope = np.ones_like(t)
    attack_samples = int(attack * sample_rate)
    envelope[:attack_samples] = np.linspace(0, 1, attack_samples)
    envelope[attack_samples:] *= np.exp(-decay_rate * t[attack_samples:] / duration)
    
    return amplitude * signal * envelope


def create_isolated_piano_fixture(
    output_path: Path, ground_truth_path: Path, sample_rate: int = 44100
) -> None:
    """C major, G major, A minor, F major. Each chord is about 2.5s. Total about 10s."""
    # (onset_seconds, duration_seconds, [midi_notes], velocity)
    chord_progression = [
        # C major (C4, E4, G4)
        (0.0, 2.5, [60, 64, 67], 0.8),
        # G major (G3, B3, D4)
        (2.5, 2.5, [55, 59, 62], 0.75),
        # A minor (A3, C4, E4)
        (5.0, 2.5, [57, 60, 64], 0.7),
        # F major (F3, A3, C4)
        (7.5, 2.5, [53, 57, 60], 0.75),
    ]
    
    total_duration = 10.0
    audio = np.zeros(int(sample_rate * total_duration))
    
    note_events = []
    
    for onset, duration, pitches, velocity in chord_progression:
        onset_sample = int(onset * sample_rate)
        for pitch in pitches:
            freq = midi_to_freq(pitch)
            tone = generate_piano_tone(freq, duration, sample_rate, amplitude=velocity * 0.3)
            end_sample = onset_sample + len(tone)
            audio[onset_sample:end_sample] += tone
            
            note_events.append({
                "pitch_midi": pitch,
                "onset_seconds": onset,
                "duration_seconds": duration,
                "velocity": velocity,
                "confidence": 1.0,
                "staff_hint": "treble" if pitch >= 60 else "bass"
            })
    
    # Peak-normalize so stacked chord tones do not clip.
    max_val = np.max(np.abs(audio))
    if max_val > 0:
        audio = audio / max_val * 0.9
    
    audio_int16 = (audio * 32767).astype(np.int16)
    wavfile.write(output_path, sample_rate, audio_int16)
    
    ground_truth = {
        "engine": "synthetic",
        "engine_version": "1.0.0",
        "tempo_bpm": 120.0,
        "key_guess": "C major",
        "note_events": note_events
    }
    
    with open(ground_truth_path, "w") as f:
        json.dump(ground_truth, f, indent=2)
    
    print(f"Created isolated piano fixture: {output_path}")
    print(f"Ground truth: {ground_truth_path}")
    print(f"Duration: {total_duration:.1f}s, Notes: {len(note_events)}")


def create_mixed_arrangement_fixture(
    output_path: Path, ground_truth_path: Path, sample_rate: int = 44100
) -> None:
    """Piano dyads plus a walking bass. Total about 12s."""
    # Piano part is two-note dyads
    piano_notes = [
        # C-E dyad
        (0.0, 2.0, [60, 64], 0.7),
        # G-B dyad
        (2.0, 2.0, [55, 59], 0.65),
        # A-C dyad
        (4.0, 2.0, [57, 60], 0.7),
        # F-A dyad
        (6.0, 2.0, [53, 57], 0.65),
        # C-E dyad (repeat)
        (8.0, 2.0, [60, 64], 0.7),
        # G major triad
        (10.0, 2.0, [55, 59, 62], 0.75),
    ]
    
    # Bass line is walking quarter notes (0.5s each at 120 bpm)
    bass_line = [
        (0.0, 0.5, 48),    # C2
        (0.5, 0.5, 50),    # D2
        (1.0, 0.5, 52),    # E2
        (1.5, 0.5, 53),    # F2
        (2.0, 0.5, 43),    # G1
        (2.5, 0.5, 45),    # A1
        (3.0, 0.5, 47),    # B1
        (3.5, 0.5, 50),    # D2
        (4.0, 0.5, 45),    # A1
        (4.5, 0.5, 48),    # C2
        (5.0, 0.5, 50),    # D2
        (5.5, 0.5, 52),    # E2
        (6.0, 0.5, 41),    # F1
        (6.5, 0.5, 43),    # G1
        (7.0, 0.5, 45),    # A1
        (7.5, 0.5, 48),    # C2
        (8.0, 0.5, 48),    # C2
        (8.5, 0.5, 50),    # D2
        (9.0, 0.5, 52),    # E2
        (9.5, 0.5, 53),    # F2
        (10.0, 0.5, 43),   # G1
        (10.5, 0.5, 45),   # A1
        (11.0, 0.5, 47),   # B1
        (11.5, 0.5, 50),   # D2
    ]
    
    total_duration = 12.0
    audio = np.zeros(int(sample_rate * total_duration))
    note_events = []
    
    for onset, duration, pitches, velocity in piano_notes:
        onset_sample = int(onset * sample_rate)
        for pitch in pitches:
            freq = midi_to_freq(pitch)
            tone = generate_piano_tone(freq, duration, sample_rate, amplitude=velocity * 0.25)
            end_sample = onset_sample + len(tone)
            audio[onset_sample:end_sample] += tone
            
            note_events.append({
                "pitch_midi": pitch,
                "onset_seconds": onset,
                "duration_seconds": duration,
                "velocity": velocity,
                "confidence": 1.0,
                "staff_hint": "treble"
            })
    
    bass_velocity = 0.6
    for onset, duration, pitch in bass_line:
        onset_sample = int(onset * sample_rate)
        freq = midi_to_freq(pitch)
        tone = generate_bass_tone(freq, duration, sample_rate, amplitude=0.3)
        end_sample = onset_sample + len(tone)
        audio[onset_sample:end_sample] += tone
        
        note_events.append({
            "pitch_midi": pitch,
            "onset_seconds": onset,
            "duration_seconds": duration,
            "velocity": bass_velocity,
            "confidence": 1.0,
            "staff_hint": "bass"
        })
    
    max_val = np.max(np.abs(audio))
    if max_val > 0:
        audio = audio / max_val * 0.9
    
    audio_int16 = (audio * 32767).astype(np.int16)
    wavfile.write(output_path, sample_rate, audio_int16)
    
    ground_truth = {
        "engine": "synthetic",
        "engine_version": "1.0.0",
        "tempo_bpm": 120.0,
        "key_guess": "C major",
        "note_events": sorted(note_events, key=lambda n: (n["onset_seconds"], n["pitch_midi"]))
    }
    
    with open(ground_truth_path, "w") as f:
        json.dump(ground_truth, f, indent=2)
    
    print(f"Created mixed arrangement fixture: {output_path}")
    print(f"Ground truth: {ground_truth_path}")
    print(f"Duration: {total_duration:.1f}s, Notes: {len(note_events)}")


def main() -> None:
    fixtures_dir = Path(__file__).resolve().parents[1] / "fixtures"
    fixtures_dir.mkdir(exist_ok=True)
    
    create_isolated_piano_fixture(
        fixtures_dir / "isolated-piano.wav",
        fixtures_dir / "isolated-piano-ground-truth.json"
    )
    
    print()
    
    create_mixed_arrangement_fixture(
        fixtures_dir / "mixed-arrangement.wav",
        fixtures_dir / "mixed-arrangement-ground-truth.json"
    )


if __name__ == "__main__":
    main()
