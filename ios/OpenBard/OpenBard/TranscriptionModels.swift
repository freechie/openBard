import Foundation

struct TranscriptionResult: Decodable {
    let engine: String
    let engineVersion: String
    let tempoBpm: Double?
    let keyGuess: String?
    var noteEvents: [NoteEvent]
}

struct NoteEvent: Decodable, Identifiable {
    let pitchMidi: Int
    var onsetSeconds: Double
    let durationSeconds: Double
    let velocity: Double
    let confidence: Double
    let onsetUncertaintySeconds: Double?
    let staffHint: StaffHint
    var isLocked: Bool = false
    
    var id: String {
        "\(pitchMidi)-\(onsetSeconds)-\(durationSeconds)"
    }
    
    enum CodingKeys: String, CodingKey {
        case pitchMidi, onsetSeconds, durationSeconds, velocity, confidence, onsetUncertaintySeconds, staffHint
    }
}

enum StaffHint: String, Decodable {
    case treble
    case bass
    case unknown
}
