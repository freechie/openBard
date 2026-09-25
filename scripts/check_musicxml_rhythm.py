#!/usr/bin/env python3
"""Line-faithful port of ScoreBuilder + MusicXMLExporter rhythm rules.

Linux cannot run the Swift tests. This script mirrors ios/OpenBard/OpenBard/
ScoreBuilder.swift and MusicXMLExporter.swift closely enough to assert that
every voice in every measure sums to a complete 4/4 bar, that overlapping
notes do not overflow, and that <type> matches <duration>.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

GRID_BEATS = 0.25
BEATS_PER_MEASURE = 4.0
DIVISIONS_PER_QUARTER = 4
MEASURE_DIVISIONS = int(BEATS_PER_MEASURE) * DIVISIONS_PER_QUARTER

DURATION_ATOMS = [
    (4.0, "whole", 0),
    (3.0, "half", 1),
    (2.0, "half", 0),
    (1.5, "quarter", 1),
    (1.0, "quarter", 0),
    (0.75, "eighth", 1),
    (0.5, "eighth", 0),
    (0.25, "16th", 0),
]


def swift_round(value: float) -> float:
    if value >= 0:
        return math.floor(value + 0.5)
    return math.ceil(value - 0.5)


def quantize(beats: float) -> float:
    return swift_round(beats / GRID_BEATS) * GRID_BEATS


@dataclass
class NoteEvent:
    pitch_midi: int
    onset_seconds: float
    duration_seconds: float


@dataclass
class ScoreNote:
    pitch_midi: int
    start_beat: float
    duration_beats: float
    tied_to_next: bool = False


@dataclass
class ScoreRest:
    start_beat: float
    duration_beats: float


@dataclass
class ScoreVoice:
    number: int
    items: list[object]


@dataclass
class ScoreMeasure:
    index: int
    voices: list[ScoreVoice]


@dataclass
class Score:
    tempo_bpm: float
    clef: str
    measures: list[ScoreMeasure]


def clamp_tempo(bpm: float) -> float:
    return min(max(bpm, 40), 208)


def snap_beat_seconds(interval: float) -> float:
    candidates = [0.25, 0.5, 1.0, 2.0]
    return min(candidates, key=lambda candidate: abs(candidate - interval))


def snap_power_of_two_beats(beats: float) -> float:
    candidates = [1.0, 2.0, 4.0, 8.0]
    return min(candidates, key=lambda candidate: abs(candidate - beats))


def estimate_tempo_bpm(notes: list[NoteEvent]) -> float:
    onsets = sorted(set(note.onset_seconds for note in notes))
    if len(onsets) >= 2:
        intervals = sorted(b - a for a, b in zip(onsets, onsets[1:]))
        median = intervals[len(intervals) // 2]
        beat_seconds = snap_beat_seconds(median)
        return clamp_tempo(60.0 / beat_seconds)

    start = min(note.onset_seconds for note in notes)
    end = max(note.onset_seconds + note.duration_seconds for note in notes)
    span = max(end - start, 0.001)
    beats_at_120 = span / 0.5
    snapped_beats = snap_power_of_two_beats(beats_at_120)
    beat_seconds = max(span / snapped_beats, 0.25)
    return clamp_tempo(60.0 / beat_seconds)


def quantized_note(note: NoteEvent, beat_seconds: float) -> ScoreNote:
    start_beat = quantize(note.onset_seconds / beat_seconds)
    duration_beats = max(GRID_BEATS, quantize(note.duration_seconds / beat_seconds))
    return ScoreNote(note.pitch_midi, start_beat, duration_beats, False)


def split_across_barlines(note: ScoreNote) -> list[ScoreNote]:
    remaining_start = note.start_beat
    remaining_duration = note.duration_beats
    slices: list[ScoreNote] = []
    while remaining_duration > 1e-9:
        measure_index = int(math.floor(remaining_start / BEATS_PER_MEASURE + 1e-9))
        bar_end = float(measure_index + 1) * BEATS_PER_MEASURE
        slice_duration = min(remaining_duration, bar_end - remaining_start)
        leftover = remaining_duration - slice_duration
        slices.append(
            ScoreNote(
                note.pitch_midi,
                remaining_start,
                quantize(slice_duration),
                leftover > 1e-9,
            )
        )
        remaining_start += slice_duration
        remaining_duration = leftover
    return slices


def can_place(note: ScoreNote, voice: list[ScoreNote]) -> bool:
    for existing in voice:
        same_start = abs(existing.start_beat - note.start_beat) < 1e-9
        same_duration = abs(existing.duration_beats - note.duration_beats) < 1e-9
        if same_start and same_duration:
            continue
        existing_end = existing.start_beat + existing.duration_beats
        note_end = note.start_beat + note.duration_beats
        overlaps = note.start_beat < existing_end - 1e-9 and existing.start_beat < note_end - 1e-9
        if overlaps:
            return False
    return True


def assign_voices(notes: list[ScoreNote]) -> list[list[ScoreNote]]:
    voices: list[list[ScoreNote]] = []
    for note in notes:
        placed = False
        for voice in voices:
            if can_place(note, voice):
                voice.append(note)
                placed = True
                break
        if not placed:
            voices.append([note])
    return voices


def insert_rests(notes: list[ScoreNote], origin: float) -> list[object]:
    items: list[object] = []
    cursor = origin
    bar_end = origin + BEATS_PER_MEASURE
    grouped: dict[float, list[ScoreNote]] = {}
    for note in notes:
        grouped.setdefault(note.start_beat, []).append(note)
    for start in sorted(grouped):
        if start > cursor + 1e-9:
            items.append(ScoreRest(cursor, quantize(start - cursor)))
        group = grouped[start]
        items.extend(group)
        group_end = max(note.start_beat + note.duration_beats for note in group)
        cursor = max(cursor, group_end)
    if bar_end > cursor + 1e-9:
        items.append(ScoreRest(cursor, quantize(bar_end - cursor)))
    return items


def pack_measures(notes: list[ScoreNote]) -> list[ScoreMeasure]:
    slices = [slice for note in notes for slice in split_across_barlines(note)]
    end_beat = max((note.start_beat + note.duration_beats for note in slices), default=BEATS_PER_MEASURE)
    measure_count = max(1, int(math.ceil(end_beat / BEATS_PER_MEASURE - 1e-9)))
    measures: list[ScoreMeasure] = []
    for index in range(measure_count):
        origin = float(index) * BEATS_PER_MEASURE
        in_measure = [
            note
            for note in slices
            if note.start_beat >= origin - 1e-9 and note.start_beat < origin + BEATS_PER_MEASURE - 1e-9
        ]
        in_measure.sort(key=lambda note: (note.start_beat, note.pitch_midi))
        assigned = assign_voices(in_measure)
        voices = [
            ScoreVoice(offset + 1, insert_rests(voice_notes, origin))
            for offset, voice_notes in enumerate(assigned)
        ]
        if not voices:
            voices = [ScoreVoice(1, insert_rests([], origin))]
        measures.append(ScoreMeasure(index, voices))
    return measures


def build_score(notes: list[NoteEvent], tempo_bpm: float | None = None) -> Score | None:
    if not notes:
        return None
    resolved = clamp_tempo(tempo_bpm) if tempo_bpm is not None else estimate_tempo_bpm(notes)
    beat_seconds = 60.0 / resolved
    quantized = [quantized_note(note, beat_seconds) for note in notes]
    clef = "bass" if all(note.pitch_midi < 60 for note in notes) else "treble"
    return Score(resolved, clef, pack_measures(quantized))


def duration_glyphs(duration_beats: float) -> list[tuple[float, str, int]]:
    remaining = quantize(duration_beats)
    glyphs: list[tuple[float, str, int]] = []
    while remaining > 1e-9:
        atom = next((item for item in DURATION_ATOMS if item[0] <= remaining + 1e-9), None)
        if atom is None:
            break
        glyphs.append(atom)
        remaining = quantize(remaining - atom[0])
    return glyphs


def midi_to_pitch(midi: int) -> tuple[str, int | None, int]:
    names = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
    alters = [None, 1, None, 1, None, None, 1, None, 1, None, 1, None]
    pc = ((midi % 12) + 12) % 12
    octave = midi // 12 - 1
    return names[pc], alters[pc], octave


def format_number(value: float) -> str:
    return f"{value:.2f}"


def format_beat(value: float) -> str:
    return f"{value:.4f}"


def tie_stop_keys(score: Score) -> set[str]:
    keys: set[str] = set()
    for measure in score.measures:
        for voice in measure.voices:
            for item in voice.items:
                if isinstance(item, ScoreNote) and item.tied_to_next:
                    end = item.start_beat + item.duration_beats
                    keys.add(f"{item.pitch_midi}@{format_beat(end)}")
    return keys


def emit_note_element(
    note: ScoreNote,
    voice: int,
    is_chord: bool,
    glyph: tuple[float, str, int],
    tie_stop: bool,
    tie_start: bool,
) -> str:
    duration_beats, type_name, dots = glyph
    duration = max(1, int(swift_round(duration_beats * DIVISIONS_PER_QUARTER)))
    step, alter, octave = midi_to_pitch(note.pitch_midi)
    xml = "      <note>\n"
    if is_chord:
        xml += "        <chord/>\n"
    xml += "        <pitch>\n"
    xml += f"          <step>{step}</step>\n"
    if alter is not None:
        xml += f"          <alter>{alter}</alter>\n"
    xml += f"          <octave>{octave}</octave>\n"
    xml += "        </pitch>\n"
    xml += f"        <duration>{duration}</duration>\n"
    if tie_stop:
        xml += '        <tie type="stop"/>\n'
    if tie_start:
        xml += '        <tie type="start"/>\n'
    xml += f"        <voice>{voice}</voice>\n"
    xml += f"        <type>{type_name}</type>\n"
    xml += "        <dot/>\n" * dots
    if tie_stop or tie_start:
        xml += "        <notations>\n"
        if tie_stop:
            xml += '          <tied type="stop"/>\n'
        if tie_start:
            xml += '          <tied type="start"/>\n'
        xml += "        </notations>\n"
    xml += "      </note>\n"
    return xml


def emit_rest(rest: ScoreRest, voice: int) -> str:
    xml = ""
    for duration_beats, type_name, dots in duration_glyphs(rest.duration_beats):
        duration = max(1, int(swift_round(duration_beats * DIVISIONS_PER_QUARTER)))
        xml += "      <note>\n"
        xml += "        <rest/>\n"
        xml += f"        <duration>{duration}</duration>\n"
        xml += f"        <voice>{voice}</voice>\n"
        xml += f"        <type>{type_name}</type>\n"
        xml += "        <dot/>\n" * dots
        xml += "      </note>\n"
    return xml


def emit_chord_group(notes: list[ScoreNote], voice: int, tie_stops: set[str]) -> str:
    glyphs = duration_glyphs(notes[0].duration_beats)
    xml = ""
    for glyph_index, glyph in enumerate(glyphs):
        for note_index, note in enumerate(notes):
            stop_key = f"{note.pitch_midi}@{format_beat(note.start_beat)}"
            needs_incoming_stop = glyph_index == 0 and stop_key in tie_stops
            tie_stop = glyph_index > 0 or needs_incoming_stop
            tie_start = glyph_index < len(glyphs) - 1 or note.tied_to_next
            xml += emit_note_element(
                note,
                voice,
                note_index > 0,
                glyph,
                tie_stop,
                tie_start,
            )
    return xml


def emit_voice(voice: ScoreVoice, tie_stops: set[str]) -> str:
    xml = ""
    index = 0
    items = voice.items
    while index < len(items):
        item = items[index]
        if isinstance(item, ScoreRest):
            xml += emit_rest(item, voice.number)
            index += 1
            continue
        group = [item]
        next_index = index + 1
        while next_index < len(items):
            other = items[next_index]
            if (
                isinstance(other, ScoreNote)
                and abs(other.start_beat - item.start_beat) < 1e-9
                and abs(other.duration_beats - item.duration_beats) < 1e-9
            ):
                group.append(other)
                next_index += 1
            else:
                break
        xml += emit_chord_group(group, voice.number, tie_stops)
        index = next_index
    return xml


def emit_measure(measure: ScoreMeasure, score: Score, tie_stops: set[str], is_first: bool) -> str:
    xml = f'    <measure number="{measure.index + 1}">\n'
    if is_first:
        xml += "      <attributes>\n"
        xml += f"        <divisions>{DIVISIONS_PER_QUARTER}</divisions>\n"
        xml += "        <key>\n"
        xml += "          <fifths>0</fifths>\n"
        xml += "        </key>\n"
        xml += "        <time>\n"
        xml += "          <beats>4</beats>\n"
        xml += "          <beat-type>4</beat-type>\n"
        xml += "        </time>\n"
        xml += "        <clef>\n"
        if score.clef == "bass":
            xml += "          <sign>F</sign>\n"
            xml += "          <line>4</line>\n"
        else:
            xml += "          <sign>G</sign>\n"
            xml += "          <line>2</line>\n"
        xml += "        </clef>\n"
        xml += "      </attributes>\n"
        xml += '      <direction placement="above">\n'
        xml += "        <direction-type>\n"
        xml += "          <metronome>\n"
        xml += "            <beat-unit>quarter</beat-unit>\n"
        xml += f"            <per-minute>{int(swift_round(score.tempo_bpm))}</per-minute>\n"
        xml += "          </metronome>\n"
        xml += "        </direction-type>\n"
        xml += f'        <sound tempo="{format_number(score.tempo_bpm)}"/>\n'
        xml += "      </direction>\n"
    for voice_index, voice in enumerate(measure.voices):
        if voice_index > 0:
            xml += "      <backup>\n"
            xml += f"        <duration>{MEASURE_DIVISIONS}</duration>\n"
            xml += "      </backup>\n"
        xml += emit_voice(voice, tie_stops)
    xml += "    </measure>\n"
    return xml


def make_musicxml(score: Score) -> str:
    tie_stops = tie_stop_keys(score)
    xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    xml += '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n'
    xml += '<score-partwise version="3.1">\n'
    xml += "  <work>\n"
    xml += "    <work-title>openBard</work-title>\n"
    xml += "  </work>\n"
    xml += "  <part-list>\n"
    xml += '    <score-part id="P1">\n'
    xml += "      <part-name>Music</part-name>\n"
    xml += "    </score-part>\n"
    xml += "  </part-list>\n"
    xml += '  <part id="P1">\n'
    for measure in score.measures:
        xml += emit_measure(measure, score, tie_stops, measure.index == 0)
    xml += "  </part>\n"
    xml += "</score-partwise>\n"
    return xml


def make_data(notes: list[NoteEvent], tempo_bpm: float | None = None) -> str:
    score = build_score(notes, tempo_bpm)
    if score is None:
        raise ValueError("no score")
    return make_musicxml(score)


def load_transcription(path: Path) -> tuple[list[NoteEvent], float | None]:
    payload = json.loads(path.read_text())
    notes = [
        NoteEvent(event["pitch_midi"], event["onset_seconds"], event["duration_seconds"])
        for event in payload["note_events"]
    ]
    return notes, payload.get("tempo_bpm")


@dataclass
class ParsedNote:
    is_chord: bool
    duration: int
    voice: int
    type: str
    dots: int


@dataclass
class ParsedMeasure:
    events: list[tuple[str, object]] = field(default_factory=list)

    @property
    def divisions_by_voice(self) -> dict[int, int]:
        totals: dict[int, int] = {}
        for kind, payload in self.events:
            if kind != "note":
                continue
            note: ParsedNote = payload  # type: ignore[assignment]
            if note.is_chord:
                continue
            totals[note.voice] = totals.get(note.voice, 0) + note.duration
        return totals

    @property
    def backup_count(self) -> int:
        return sum(1 for kind, _ in self.events if kind == "backup")

    @property
    def cursor_end(self) -> int:
        cursor = 0
        for kind, payload in self.events:
            if kind == "note":
                note: ParsedNote = payload  # type: ignore[assignment]
                if not note.is_chord:
                    cursor += note.duration
            elif kind == "backup":
                cursor -= int(payload)  # type: ignore[arg-type]
        return cursor


def divisions_for_type(type_name: str, dots: int) -> int:
    base = {"whole": 16, "half": 8, "quarter": 4, "eighth": 2, "16th": 1}[type_name]
    value = base
    add = base // 2
    for _ in range(dots):
        value += add
        add //= 2
    return value


def parse_measures(xml: str) -> list[ParsedMeasure]:
    bodies = re.findall(r"<measure number=\"\d+\">(.*?)</measure>", xml, flags=re.S)
    return [parse_measure(body) for body in bodies]


def parse_measure(body: str) -> ParsedMeasure:
    measure = ParsedMeasure()
    for match in re.finditer(r"<note>(.*?)</note>|<backup>(.*?)</backup>", body, flags=re.S):
        if match.group(1) is not None:
            note_body = match.group(1)
            duration = int(re.search(r"<duration>(\d+)</duration>", note_body).group(1))
            voice = int(re.search(r"<voice>(\d+)</voice>", note_body).group(1))
            type_name = re.search(r"<type>([^<]+)</type>", note_body).group(1)
            measure.events.append(
                (
                    "note",
                    ParsedNote(
                        is_chord="<chord/>" in note_body,
                        duration=duration,
                        voice=voice,
                        type=type_name,
                        dots=note_body.count("<dot/>"),
                    ),
                )
            )
        else:
            duration = int(re.search(r"<duration>(\d+)</duration>", match.group(2)).group(1))
            measure.events.append(("backup", duration))
    return measure


def assert_valid_measure(measure: ParsedMeasure, label: str) -> None:
    voices = measure.divisions_by_voice
    assert 1 in voices, f"{label}: missing voice 1"
    for voice, total in voices.items():
        assert total == MEASURE_DIVISIONS, f"{label}: voice {voice} summed to {total}, want {MEASURE_DIVISIONS}"
    assert measure.cursor_end == MEASURE_DIVISIONS, f"{label}: cursor ended at {measure.cursor_end}"
    assert measure.backup_count == max(len(voices) - 1, 0), f"{label}: backup count {measure.backup_count}"
    for kind, payload in measure.events:
        if kind != "note":
            continue
        note: ParsedNote = payload  # type: ignore[assignment]
        expected = divisions_for_type(note.type, note.dots)
        assert expected == note.duration, (
            f"{label}: type {note.type} dots={note.dots} duration={note.duration}, want {expected}"
        )


def event(pitch: int, onset: float, duration: float) -> NoteEvent:
    return NoteEvent(pitch, onset, duration)


def check_audit_1a() -> str:
    notes = [event(48, 0, 2.0), event(84, 0.5, 0.5)]
    score = build_score(notes, 120)
    assert score is not None
    assert len(score.measures) == 1
    assert len(score.measures[0].voices) == 2
    xml = make_musicxml(score)
    measures = parse_measures(xml)
    assert_valid_measure(measures[0], "audit-1a")
    assert "<backup>" in xml
    assert "<chord/>" not in xml
    return xml


def check_audit_1b() -> str:
    notes = [event(60, 0, 0.5), event(64, 0, 2.0)]
    xml = make_data(notes, 120)
    assert "<chord/>" not in xml
    measures = parse_measures(xml)
    assert_valid_measure(measures[0], "audit-1b")
    voice2 = [
        payload
        for kind, payload in measures[0].events
        if kind == "note" and not payload.is_chord and payload.voice == 2  # type: ignore[union-attr]
    ]
    assert any(note.duration == MEASURE_DIVISIONS and note.type == "whole" for note in voice2)
    return xml


def check_audit_1c() -> tuple[str, dict[str, str]]:
    rows = ["beats\tdivisions\tglyphs\tvoice1"]
    samples: dict[str, str] = {}
    for step in range(1, 17):
        beats = step * GRID_BEATS
        xml = make_data([event(60, 0, beats * 0.5)], 120)
        measures = parse_measures(xml)
        assert_valid_measure(measures[0], f"audit-1c-{beats}")
        glyphs = " + ".join(
            f"{name}{'.' * dots} ({int(swift_round(duration * DIVISIONS_PER_QUARTER))} div)"
            for duration, name, dots in duration_glyphs(beats)
        )
        rows.append(f"{beats:g}\t{step}\t{glyphs}\t{MEASURE_DIVISIONS}")
        if beats in (0.75, 1.25, 2.5, 3.75):
            samples[f"grid-{beats:g}-beats"] = xml
    return "\n".join(rows) + "\n", samples


def check_equal_duration_chord() -> str:
    notes = [event(60, 0, 2.0), event(64, 0, 2.0), event(67, 0, 2.0)]
    xml = make_data(notes, 120)
    assert "<chord/>" in xml
    assert_valid_measure(parse_measures(xml)[0], "c-major-chord")
    return xml


def check_fixtures(repo_root: Path) -> dict[str, str]:
    fixtures = {
        "transcription.example": repo_root / "contracts" / "transcription.example.json",
        "isolated-piano-basicpitch": repo_root / "fixtures" / "isolated-piano-basicpitch.json",
        "isolated-piano-ground-truth": repo_root / "fixtures" / "isolated-piano-ground-truth.json",
        "mixed-arrangement-ground-truth": repo_root / "fixtures" / "mixed-arrangement-ground-truth.json",
    }
    emitted: dict[str, str] = {}
    for name, path in fixtures.items():
        notes, tempo = load_transcription(path)
        xml = make_data(notes, tempo)
        measures = parse_measures(xml)
        assert measures, f"{name}: no measures"
        for index, measure in enumerate(measures, start=1):
            assert_valid_measure(measure, f"{name} m{index}")
        emitted[name] = xml
    return emitted


def write_emit_dir(emit_dir: Path, files: dict[str, str], summaries: Iterable[str]) -> None:
    emit_dir.mkdir(parents=True, exist_ok=True)
    for name, xml in files.items():
        (emit_dir / f"{name}.musicxml").write_text(xml)
    header = [
        "MusicXML rhythm proof (no MuseScore on Linux).",
        "Parser sums non-chord <duration> per voice; <backup> rewinds the measure cursor.",
        "Before: isolated-piano-basicpitch m1=22/16 m3=20/16; mixed-arrangement dyads lost duration onto the bass.",
        "After: every voice in every measure is 16/16 and the cursor ends at 16.",
        "",
    ]
    (emit_dir / "summary.txt").write_text("\n".join(header + list(summaries)) + "\n")


def summarize(name: str, xml: str) -> str:
    measures = parse_measures(xml)
    parts = []
    for index, measure in enumerate(measures, start=1):
        voices = ",".join(
            f"v{voice}={total}/{MEASURE_DIVISIONS}"
            for voice, total in sorted(measure.divisions_by_voice.items())
        )
        parts.append(f"m{index}[{voices} cursor={measure.cursor_end}]")
    return f"{name}: {len(measures)} measures; " + "; ".join(parts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit", type=Path, help="Directory for emitted MusicXML proof files")
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parents[1]
    emitted: dict[str, str] = {}
    emitted["overlap-whole-plus-quarter"] = check_audit_1a()
    emitted["mixed-duration-chord"] = check_audit_1b()
    emitted["c-major-chord"] = check_equal_duration_chord()
    grid_table, grid_samples = check_audit_1c()
    emitted.update(grid_samples)
    emitted.update(check_fixtures(repo_root))

    summaries = [summarize(name, xml) for name, xml in emitted.items()]
    summaries.append("grid-durations: 16/16 grid values; type+dots match duration; voice 1 == 16")

    if args.emit:
        write_emit_dir(args.emit, emitted, summaries)
        (args.emit / "grid-durations.txt").write_text(grid_table)

    print("✓ MusicXML rhythm checks passed")
    for line in summaries:
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
