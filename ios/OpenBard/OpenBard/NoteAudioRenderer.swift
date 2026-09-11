import Foundation

/// Renders note events to a simple polyphonic sine WAV for preview playback.
enum NoteAudioRenderer {
    static let sampleRate: Double = 44_100
    static let maxDurationSeconds: Double = 120

    enum RenderError: Error, Equatable {
        case noNotes
        case emptyBuffer
    }

    /// Frequency for MIDI note number (A4 = 440 Hz at MIDI 69).
    static func frequency(midiPitch: Int) -> Double {
        440.0 * pow(2.0, (Double(midiPitch) - 69.0) / 12.0)
    }

    static func timelineEnd(notes: [NoteEvent]) -> Double {
        notes.map { $0.onsetSeconds + max($0.durationSeconds, 0.05) }.max() ?? 0
    }

    /// Build a mono 16-bit PCM WAV for the given notes (wall-clock timing).
    static func makeWAVData(from notes: [NoteEvent]) throws -> Data {
        guard !notes.isEmpty else { throw RenderError.noNotes }

        let end = min(max(timelineEnd(notes: notes) + 0.05, 0.1), maxDurationSeconds)
        let frameCount = max(Int((end * sampleRate).rounded(.up)), 1)
        var samples = [Float](repeating: 0, count: frameCount)

        for note in notes {
            let startFrame = max(0, Int((note.onsetSeconds * sampleRate).rounded(.down)))
            let durationFrames = max(1, Int((max(note.durationSeconds, 0.05) * sampleRate).rounded(.up)))
            let endFrame = min(frameCount, startFrame + durationFrames)
            guard startFrame < endFrame else { continue }

            let freq = frequency(midiPitch: note.pitchMidi)
            let amplitude = Float(min(max(note.velocity, 0.05), 1.0)) * 0.22
            let attack = min(Int(0.01 * sampleRate), max(durationFrames / 8, 1))
            let release = min(Int(0.04 * sampleRate), max(durationFrames / 4, 1))

            for frame in startFrame..<endFrame {
                let local = frame - startFrame
                var envelope: Float = 1
                if local < attack {
                    envelope = Float(local) / Float(attack)
                } else if local > durationFrames - release {
                    envelope = Float(max(durationFrames - local, 0)) / Float(release)
                }
                let t = Double(local) / sampleRate
                let sample = Float(sin(2.0 * Double.pi * freq * t)) * amplitude * envelope
                samples[frame] += sample
            }
        }

        // Soft clip
        for i in samples.indices {
            let x = samples[i]
            samples[i] = max(-1, min(1, x))
        }

        return wavData(from: samples, sampleRate: Int(sampleRate))
    }

    private static func wavData(from samples: [Float], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendASCII(_ s: String) {
            data.append(contentsOf: s.utf8)
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendU32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendU32(16) // PCM chunk size
        appendU16(1) // PCM
        appendU16(1) // mono
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2)) // byte rate
        appendU16(2) // block align
        appendU16(16) // bits
        appendASCII("data")
        appendU32(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, Double(sample)))
            let intSample = Int16((clamped * Double(Int16.max)).rounded())
            var le = intSample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
