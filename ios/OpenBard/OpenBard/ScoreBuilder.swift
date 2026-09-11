import Foundation

struct Score: Equatable {
    var tempoBpm: Double
    var beatsPerMeasure: Double
    var clef: StaffHint
    var measures: [ScoreMeasure]
}

struct ScoreMeasure: Equatable {
    var index: Int
    var items: [ScoreItem]
}

enum ScoreItem: Equatable {
    case note(ScoreNote)
    case rest(ScoreRest)
}

struct ScoreNote: Equatable {
    var pitchMidi: Int
    var startBeat: Double
    var durationBeats: Double
    var tiedToNext: Bool
}

struct ScoreRest: Equatable {
    var startBeat: Double
    var durationBeats: Double
}

enum ScoreBuilder {
    static let beatsPerMeasure = 4.0
    static let gridBeats = 0.25

    static func build(from notes: [NoteEvent], tempoBpm: Double? = nil) -> Score? {
        guard !notes.isEmpty else { return nil }

        let resolvedTempo = tempoBpm.map(clampTempo) ?? estimateTempoBpm(notes)
        let beatSeconds = 60.0 / resolvedTempo
        let quantized = notes.map { note in
            quantizedNote(note, beatSeconds: beatSeconds)
        }

        let clef: StaffHint = notes.allSatisfy({ $0.pitchMidi < 60 }) ? .bass : .treble
        let measures = packMeasures(quantized)

        return Score(
            tempoBpm: resolvedTempo,
            beatsPerMeasure: beatsPerMeasure,
            clef: clef,
            measures: measures
        )
    }

    static func estimateTempoBpm(_ notes: [NoteEvent]) -> Double {
        let onsets = Array(Set(notes.map(\.onsetSeconds))).sorted()
        if onsets.count >= 2 {
            let intervals = zip(onsets, onsets.dropFirst()).map { $1 - $0 }.sorted()
            let median = intervals[intervals.count / 2]
            let beatSeconds = snapBeatSeconds(median)
            return clampTempo(60.0 / beatSeconds)
        }

        let start = notes.map(\.onsetSeconds).min() ?? 0
        let end = notes.map { $0.onsetSeconds + $0.durationSeconds }.max() ?? start
        let span = max(end - start, 0.001)
        let beatsAt120 = span / 0.5
        let snappedBeats = snapPowerOfTwoBeats(beatsAt120)
        let beatSeconds = max(span / snappedBeats, 0.25)
        return clampTempo(60.0 / beatSeconds)
    }

    private static func quantizedNote(_ note: NoteEvent, beatSeconds: Double) -> ScoreNote {
        let startBeat = quantize(note.onsetSeconds / beatSeconds)
        let durationBeats = max(gridBeats, quantize(note.durationSeconds / beatSeconds))
        return ScoreNote(
            pitchMidi: note.pitchMidi,
            startBeat: startBeat,
            durationBeats: durationBeats,
            tiedToNext: false
        )
    }

    private static func packMeasures(_ notes: [ScoreNote]) -> [ScoreMeasure] {
        let slices = notes.flatMap { splitAcrossBarlines($0) }
        let endBeat = slices.map { $0.startBeat + $0.durationBeats }.max() ?? beatsPerMeasure
        let measureCount = max(1, Int(ceil(endBeat / beatsPerMeasure - 1e-9)))

        return (0..<measureCount).map { index in
            let origin = Double(index) * beatsPerMeasure
            let inMeasure = slices
                .filter { $0.startBeat >= origin - 1e-9 && $0.startBeat < origin + beatsPerMeasure - 1e-9 }
                .sorted { lhs, rhs in
                    if lhs.startBeat != rhs.startBeat { return lhs.startBeat < rhs.startBeat }
                    return lhs.pitchMidi < rhs.pitchMidi
                }
            let items = insertRests(notes: inMeasure, origin: origin)
            return ScoreMeasure(index: index, items: items)
        }
    }

    private static func splitAcrossBarlines(_ note: ScoreNote) -> [ScoreNote] {
        var remainingStart = note.startBeat
        var remainingDuration = note.durationBeats
        var slices: [ScoreNote] = []

        while remainingDuration > 1e-9 {
            let measureIndex = Int(floor(remainingStart / beatsPerMeasure + 1e-9))
            let barEnd = Double(measureIndex + 1) * beatsPerMeasure
            let sliceDuration = min(remainingDuration, barEnd - remainingStart)
            let leftover = remainingDuration - sliceDuration
            slices.append(
                ScoreNote(
                    pitchMidi: note.pitchMidi,
                    startBeat: remainingStart,
                    durationBeats: quantize(sliceDuration),
                    tiedToNext: leftover > 1e-9
                )
            )
            remainingStart += sliceDuration
            remainingDuration = leftover
        }

        return slices
    }

    private static func insertRests(notes: [ScoreNote], origin: Double) -> [ScoreItem] {
        var items: [ScoreItem] = []
        var cursor = origin
        let barEnd = origin + beatsPerMeasure
        let grouped = Dictionary(grouping: notes, by: \.startBeat)
        let starts = grouped.keys.sorted()

        for start in starts {
            if start > cursor + 1e-9 {
                items.append(.rest(ScoreRest(startBeat: cursor, durationBeats: quantize(start - cursor))))
            }
            for note in grouped[start] ?? [] {
                items.append(.note(note))
            }
            let groupEnd = (grouped[start] ?? []).map { $0.startBeat + $0.durationBeats }.max() ?? start
            cursor = max(cursor, groupEnd)
        }

        if barEnd > cursor + 1e-9 {
            items.append(.rest(ScoreRest(startBeat: cursor, durationBeats: quantize(barEnd - cursor))))
        }

        return items
    }

    private static func quantize(_ beats: Double) -> Double {
        (beats / gridBeats).rounded() * gridBeats
    }

    private static func snapBeatSeconds(_ interval: Double) -> Double {
        let candidates = [0.25, 0.5, 1.0, 2.0]
        return candidates.min(by: { abs($0 - interval) < abs($1 - interval) }) ?? 0.5
    }

    private static func snapPowerOfTwoBeats(_ beats: Double) -> Double {
        let candidates = [1.0, 2.0, 4.0, 8.0]
        return candidates.min(by: { abs($0 - beats) < abs($1 - beats) }) ?? 4.0
    }

    static func clampTempo(_ bpm: Double) -> Double {
        min(max(bpm, 40), 208)
    }
}
