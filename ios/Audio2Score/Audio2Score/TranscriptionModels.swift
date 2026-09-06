import Foundation

struct TranscriptionResult: Decodable {
    let engine: String
    let engineVersion: String
    let tempoBpm: Double
    let keyGuess: String
    let noteEvents: [NoteEvent]
}

struct NoteEvent: Decodable, Identifiable {
    var id: String {
        "\(pitchMidi)-\(onsetSeconds)-\(durationSeconds)"
    }
    let pitchMidi: Int
    let onsetSeconds: Double
    let durationSeconds: Double
    let velocity: Double
    let confidence: Double
    let staffHint: StaffHint
}

enum StaffHint: String, Decodable {
    case treble
    case bass
    case unknown
}
