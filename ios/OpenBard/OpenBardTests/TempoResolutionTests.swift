import Foundation
import Testing
@testable import OpenBard

struct TempoResolutionTests {
    @Test func isolatedPianoLoadSharesOneTempoAcrossRollScoreAndExport() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try #require(try TranscriptionLoader.loadFixture(.isolatedPiano, from: bundle))
        let notes = transcription.noteEvents
        #expect(notes.count == 21)

        let estimated = ScoreBuilder.estimateTempoBpm(notes)
        #expect(estimated == 60)
        #expect(transcription.tempoBpm == 60)
        #expect(transcription.tempoBpm == estimated)

        let uiBpm = transcription.tempoBpm ?? NoteHelpers.defaultTempoBpm
        #expect(uiBpm == 60)
        #expect(ScoreBuilder.clampTempo(uiBpm + 1) == 61)

        let score = try #require(ScoreBuilder.build(from: notes, tempoBpm: transcription.tempoBpm))
        #expect(score.tempoBpm == 60)

        let midi = try MIDIExporter.makeData(from: notes, tempoBpm: transcription.tempoBpm)
        #expect(midiTempoBpm(in: midi) == 60)

        let xml = String(decoding: try MusicXMLExporter.makeData(
            from: notes,
            tempoBpm: transcription.tempoBpm
        ), as: UTF8.self)
        #expect(xml.contains("<per-minute>60</per-minute>"))
    }

    @Test func mixedArrangementKeepsExplicitTempo() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try #require(try TranscriptionLoader.loadFixture(.mixedArrangement, from: bundle))
        #expect(transcription.tempoBpm == 120)
        #expect(transcription.noteEvents.count == 37)
    }
}

private func midiTempoBpm(in data: Data) -> Int? {
    let bytes = [UInt8](data)
    var index = 0
    while index + 5 < bytes.count {
        if bytes[index] == 0xFF, bytes[index + 1] == 0x51, bytes[index + 2] == 0x03 {
            let micros = (Int(bytes[index + 3]) << 16)
                | (Int(bytes[index + 4]) << 8)
                | Int(bytes[index + 5])
            guard micros > 0 else { return nil }
            return Int((60_000_000.0 / Double(micros)).rounded())
        }
        index += 1
    }
    return nil
}
