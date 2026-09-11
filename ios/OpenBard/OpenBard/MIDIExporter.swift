import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum MIDIExportError: Error, Equatable {
    case noNotes
}

enum MIDIExporter {
    static let defaultTicksPerQuarter = 480
    static let defaultTempoBpm = 120.0

    /// Build a Format-0 Standard MIDI File from note events (wall-clock timing).
    static func makeData(
        from notes: [NoteEvent],
        tempoBpm: Double? = nil,
        ticksPerQuarter: Int = defaultTicksPerQuarter
    ) throws -> Data {
        guard !notes.isEmpty else { throw MIDIExportError.noNotes }

        let tempo = ScoreBuilder.clampTempo(tempoBpm ?? ScoreBuilder.estimateTempoBpm(notes))
        let ticks = max(ticksPerQuarter, 1)

        var absoluteEvents: [(tick: Int, bytes: [UInt8])] = []
        absoluteEvents.append((0, tempoMetaEvent(bpm: tempo)))

        for note in notes.sorted(by: { lhs, rhs in
            if lhs.onsetSeconds != rhs.onsetSeconds {
                return lhs.onsetSeconds < rhs.onsetSeconds
            }
            return lhs.pitchMidi < rhs.pitchMidi
        }) {
            let pitch = UInt8(clamping: note.pitchMidi)
            let velocity = midiVelocity(note.velocity)
            let startTick = secondsToTicks(note.onsetSeconds, tempoBpm: tempo, ticksPerQuarter: ticks)
            let endTick = max(
                startTick + 1,
                secondsToTicks(
                    note.onsetSeconds + max(note.durationSeconds, 0.001),
                    tempoBpm: tempo,
                    ticksPerQuarter: ticks
                )
            )
            absoluteEvents.append((startTick, [0x90, pitch, velocity]))
            absoluteEvents.append((endTick, [0x80, pitch, 0x40]))
        }

        absoluteEvents.sort { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            // Note-offs before note-ons at the same tick avoids zero-length hangs.
            return lhs.bytes[0] < rhs.bytes[0]
        }

        var track = Data()
        var lastTick = 0
        for event in absoluteEvents {
            track.append(contentsOf: vlq(event.tick - lastTick))
            track.append(contentsOf: event.bytes)
            lastTick = event.tick
        }
        track.append(contentsOf: vlq(0))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        data.append(u32(6))
        data.append(u16(0)) // format 0
        data.append(u16(1)) // one track
        data.append(u16(UInt16(ticks)))

        data.append(contentsOf: Array("MTrk".utf8))
        data.append(u32(UInt32(track.count)))
        data.append(track)
        return data
    }

    static func makeData(from transcription: TranscriptionResult) throws -> Data {
        try makeData(from: transcription.noteEvents, tempoBpm: transcription.tempoBpm)
    }

    static func secondsToTicks(_ seconds: Double, tempoBpm: Double, ticksPerQuarter: Int) -> Int {
        let beats = seconds * tempoBpm / 60.0
        return max(0, Int((beats * Double(ticksPerQuarter)).rounded()))
    }

    static func midiVelocity(_ velocity: Double) -> UInt8 {
        UInt8(clamping: max(1, Int((velocity * 127.0).rounded())))
    }

    // MARK: - Encoding helpers

    private static func clampTempo(_ bpm: Double) -> Double {
        min(max(bpm, 30.0), 300.0)
    }

    private static func tempoMetaEvent(bpm: Double) -> [UInt8] {
        let micros = max(1, Int((60_000_000.0 / bpm).rounded()))
        return [
            0xFF, 0x51, 0x03,
            UInt8((micros >> 16) & 0xFF),
            UInt8((micros >> 8) & 0xFF),
            UInt8(micros & 0xFF),
        ]
    }

    static func vlq(_ value: Int) -> [UInt8] {
        var buffer = [UInt8]()
        var remaining = max(0, value)
        buffer.insert(UInt8(remaining & 0x7F), at: 0)
        remaining >>= 7
        while remaining > 0 {
            buffer.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
            remaining >>= 7
        }
        return buffer
    }

    private static func u16(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func u32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }
}

struct MIDIFileDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .midi) { document in
            document.data
        }
    }
}

extension UTType {
    static var midi: UTType {
        UTType(filenameExtension: "mid") ?? .data
    }
}
