import Foundation
import Testing
@testable import OpenBard

struct MusicXMLRhythmTests {
    private let divisionsPerQuarter = MusicXMLExporter.divisionsPerQuarter
    private var measureDivisions: Int { MusicXMLExporter.measureDivisions }

    private func note(
        pitch: Int,
        onset: Double,
        duration: Double,
        staffHint: StaffHint = .treble
    ) -> NoteEvent {
        NoteEvent(
            pitchMidi: pitch,
            onsetSeconds: onset,
            durationSeconds: duration,
            velocity: 0.8,
            confidence: 1,
            staffHint: staffHint
        )
    }

    private func loadFixture(_ resource: String) throws -> TranscriptionResult {
        let bundle = Bundle(for: TestBundleMarker.self)
        let url = try #require(bundle.url(forResource: resource, withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TranscriptionResult.self, from: Data(contentsOf: url))
    }

    private func xml(from notes: [NoteEvent], tempoBpm: Double? = 120) throws -> String {
        let data = try MusicXMLExporter.makeData(from: notes, tempoBpm: tempoBpm)
        return String(decoding: data, as: UTF8.self)
    }

    @Test func overlappingWholeAndQuarterUsesBackupAndFillsVoice1() throws {
        // Whole C3 at beat 0 plus quarter C6 at beat 1 (audit 1a).
        let notes = [
            note(pitch: 48, onset: 0, duration: 2.0, staffHint: .bass),
            note(pitch: 84, onset: 0.5, duration: 0.5),
        ]
        let score = try #require(ScoreBuilder.build(from: notes, tempoBpm: 120))
        #expect(score.measures.count == 1)
        #expect(score.measures[0].voices.count == 2)

        let voice1 = score.measures[0].voices[0]
        #expect(voice1.number == 1)
        #expect(advancingDivisions(voice1.items) == measureDivisions)

        let xml = try xml(from: notes)
        let measures = parseMeasures(xml)
        #expect(measures.count == 1)
        assertRhythmicallyValid(measures[0])
        #expect(measures[0].divisionsByVoice[1] == measureDivisions)
        #expect(measures[0].backupCount == 1)
        #expect(xml.contains("<backup>"))
        #expect(xml.contains("<step>C</step>"))
    }

    @Test func mixedDurationChordKeepsLongerTone() throws {
        // Lowest note is the shortest: C4 quarter + E4 whole (audit 1b).
        let notes = [
            note(pitch: 60, onset: 0, duration: 0.5),
            note(pitch: 64, onset: 0, duration: 2.0),
        ]
        let score = try #require(ScoreBuilder.build(from: notes, tempoBpm: 120))
        #expect(score.measures[0].voices.count == 2)

        let xml = try xml(from: notes)
        #expect(!xml.contains("<chord/>"))

        let measures = parseMeasures(xml)
        assertRhythmicallyValid(measures[0])
        #expect(measures[0].divisionsByVoice[1] == measureDivisions)
        #expect(measures[0].divisionsByVoice[2] == measureDivisions)

        let voice2Notes = measures[0].events.compactMap { event -> ParsedNote? in
            guard case .note(let parsed) = event, parsed.voice == 2, !parsed.isChord else { return nil }
            return parsed
        }
        #expect(voice2Notes.contains { $0.duration == measureDivisions && $0.type == "whole" })
    }

    @Test func typeMatchesDurationForEveryGridValue() throws {
        for step in 1...16 {
            let beats = Double(step) * ScoreBuilder.gridBeats
            let notes = [note(pitch: 60, onset: 0, duration: beats * 0.5)]
            let xml = try xml(from: notes)
            let measures = parseMeasures(xml)
            #expect(measures.count == 1)
            assertRhythmicallyValid(measures[0])
        }
    }

    @Test(arguments: [
        "transcription.example",
        "isolated-piano-basicpitch",
        "isolated-piano-ground-truth",
        "mixed-arrangement-ground-truth",
    ])
    func bundledFixtureVoice1FillsEveryMeasure(resource: String) throws {
        let transcription = try loadFixture(resource)
        let data = try MusicXMLExporter.makeData(
            from: transcription.noteEvents,
            tempoBpm: transcription.tempoBpm
        )
        let xml = String(decoding: data, as: UTF8.self)
        let measures = parseMeasures(xml)
        #expect(!measures.isEmpty)

        for measure in measures {
            assertRhythmicallyValid(measure)
            #expect(measure.divisionsByVoice[1] == measureDivisions)
        }
    }

    @Test func equalDurationChordStillUsesChordTag() throws {
        let notes = [
            note(pitch: 60, onset: 0, duration: 2.0),
            note(pitch: 64, onset: 0, duration: 2.0),
            note(pitch: 67, onset: 0, duration: 2.0),
        ]
        let xml = try xml(from: notes)
        #expect(xml.contains("<chord/>"))
        let measures = parseMeasures(xml)
        assertRhythmicallyValid(measures[0])
        #expect(measures[0].divisionsByVoice[1] == measureDivisions)
        let advancing = measures[0].events.reduce(0) { total, event in
            guard case .note(let parsed) = event, !parsed.isChord, parsed.voice == 1 else { return total }
            return total + parsed.duration
        }
        #expect(advancing == measureDivisions)
    }

    @Test func dottedAndTiedGlyphsCoverOffGridValues() {
        let dottedEighth = MusicXMLExporter.durationGlyphs(for: 0.75)
        #expect(dottedEighth == [DurationGlyph(durationBeats: 0.75, type: "eighth", dots: 1)])

        let fiveSixteenths = MusicXMLExporter.durationGlyphs(for: 1.25)
        #expect(fiveSixteenths.map(\.type) == ["quarter", "16th"])
        #expect(fiveSixteenths.map(\.dots) == [0, 0])

        let tenSixteenths = MusicXMLExporter.durationGlyphs(for: 2.5)
        #expect(tenSixteenths.map(\.type) == ["half", "eighth"])
    }

    @Test func scoreBuilderPutsOverlapsOnSeparateVoices() throws {
        let notes = [
            note(pitch: 48, onset: 0, duration: 2.0, staffHint: .bass),
            note(pitch: 84, onset: 0.5, duration: 0.5),
        ]
        let score = try #require(ScoreBuilder.build(from: notes, tempoBpm: 120))
        #expect(score.measures[0].voices.count == 2)
        let voice1Notes = score.measures[0].voices[0].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        let voice2Notes = score.measures[0].voices[1].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        #expect(voice1Notes.map(\.pitchMidi) == [48])
        #expect(voice1Notes[0].durationBeats == 4)
        #expect(voice2Notes.map(\.pitchMidi) == [84])
        #expect(voice2Notes[0].durationBeats == 1)
    }

    private func advancingDivisions(_ items: [ScoreItem]) -> Int {
        var total = 0.0
        var lastStart: Double?
        var lastDuration: Double?
        for item in items {
            switch item {
            case .rest(let rest):
                total += rest.durationBeats
                lastStart = nil
                lastDuration = nil
            case .note(let note):
                let isChord = lastStart.map { abs($0 - note.startBeat) < 1e-9 } ?? false
                    && lastDuration.map { abs($0 - note.durationBeats) < 1e-9 } ?? false
                if !isChord {
                    total += note.durationBeats
                }
                lastStart = note.startBeat
                lastDuration = note.durationBeats
            }
        }
        return Int((total * Double(divisionsPerQuarter)).rounded())
    }

    private func assertRhythmicallyValid(_ measure: ParsedMeasure) {
        #expect(measure.divisionsByVoice[1] == measureDivisions)
        for (_, divisions) in measure.divisionsByVoice {
            #expect(divisions == measureDivisions)
        }
        #expect(measure.cursorEnd == measureDivisions)
        #expect(measure.backupCount == max(measure.divisionsByVoice.count - 1, 0))
        for event in measure.events {
            guard case .note(let parsed) = event else { continue }
            let type = parsed.type ?? "16th"
            let expected = divisions(type: type, dots: parsed.dots)
            #expect(expected == parsed.duration)
        }
    }

    private func divisions(type: String, dots: Int) -> Int? {
        let base: [String: Int] = [
            "whole": 16,
            "half": 8,
            "quarter": 4,
            "eighth": 2,
            "16th": 1,
        ]
        guard var value = base[type] else { return nil }
        var add = value / 2
        for _ in 0..<dots {
            value += add
            add /= 2
        }
        return value
    }

    private func parseMeasures(_ xml: String) -> [ParsedMeasure] {
        measureBodies(in: xml).map { parseMeasure($0) }
    }

    private func measureBodies(in xml: String) -> [String] {
        var bodies: [String] = []
        var search = xml.startIndex
        while let start = xml.range(of: "<measure ", range: search..<xml.endIndex),
              let openEnd = xml.range(of: ">", range: start.upperBound..<xml.endIndex),
              let close = xml.range(of: "</measure>", range: openEnd.upperBound..<xml.endIndex) {
            bodies.append(String(xml[openEnd.upperBound..<close.lowerBound]))
            search = close.upperBound
        }
        return bodies
    }

    private func parseMeasure(_ body: String) -> ParsedMeasure {
        var events: [RhythmEvent] = []
        var search = body.startIndex
        while search < body.endIndex {
            let rest = search..<body.endIndex
            let noteStart = body.range(of: "<note>", range: rest)
            let backupStart = body.range(of: "<backup>", range: rest)
            switch (noteStart, backupStart) {
            case (nil, nil):
                search = body.endIndex
            case (let noteRange?, nil):
                guard let close = body.range(of: "</note>", range: noteRange.upperBound..<body.endIndex) else {
                    search = body.endIndex
                    break
                }
                events.append(.note(parseNote(String(body[noteRange.lowerBound..<close.upperBound]))))
                search = close.upperBound
            case (nil, let backupRange?):
                guard let close = body.range(of: "</backup>", range: backupRange.upperBound..<body.endIndex) else {
                    search = body.endIndex
                    break
                }
                events.append(.backup(firstInt(in: String(body[backupRange.lowerBound..<close.upperBound]), tag: "duration") ?? 0))
                search = close.upperBound
            case (let noteRange?, let backupRange?):
                if noteRange.lowerBound < backupRange.lowerBound {
                    guard let close = body.range(of: "</note>", range: noteRange.upperBound..<body.endIndex) else {
                        search = body.endIndex
                        break
                    }
                    events.append(.note(parseNote(String(body[noteRange.lowerBound..<close.upperBound]))))
                    search = close.upperBound
                } else {
                    guard let close = body.range(of: "</backup>", range: backupRange.upperBound..<body.endIndex) else {
                        search = body.endIndex
                        break
                    }
                    events.append(.backup(firstInt(in: String(body[backupRange.lowerBound..<close.upperBound]), tag: "duration") ?? 0))
                    search = close.upperBound
                }
            }
        }
        return ParsedMeasure(events: events)
    }

    private func parseNote(_ body: String) -> ParsedNote {
        ParsedNote(
            isChord: body.contains("<chord/>"),
            duration: firstInt(in: body, tag: "duration") ?? 0,
            voice: firstInt(in: body, tag: "voice") ?? 1,
            type: firstText(in: body, tag: "type"),
            dots: body.components(separatedBy: "<dot/>").count - 1
        )
    }

    private func firstInt(in body: String, tag: String) -> Int? {
        firstText(in: body, tag: tag).flatMap(Int.init)
    }

    private func firstText(in body: String, tag: String) -> String? {
        guard let start = body.range(of: "<\(tag)>"),
              let end = body.range(of: "</\(tag)>", range: start.upperBound..<body.endIndex) else {
            return nil
        }
        return String(body[start.upperBound..<end.lowerBound])
    }
}

private struct ParsedNote {
    var isChord: Bool
    var duration: Int
    var voice: Int
    var type: String?
    var dots: Int
}

private enum RhythmEvent {
    case note(ParsedNote)
    case backup(Int)
}

private struct ParsedMeasure {
    var events: [RhythmEvent]

    var divisionsByVoice: [Int: Int] {
        var totals: [Int: Int] = [:]
        for event in events {
            guard case .note(let note) = event, !note.isChord else { continue }
            totals[note.voice, default: 0] += note.duration
        }
        return totals
    }

    var backupCount: Int {
        events.reduce(0) { count, event in
            if case .backup = event { return count + 1 }
            return count
        }
    }

    var cursorEnd: Int {
        var cursor = 0
        for event in events {
            switch event {
            case .note(let note):
                if !note.isChord {
                    cursor += note.duration
                }
            case .backup(let duration):
                cursor -= duration
            }
        }
        return cursor
    }
}
