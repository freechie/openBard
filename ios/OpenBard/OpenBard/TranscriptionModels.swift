import Foundation

struct TranscriptionResult: Decodable {
    let engine: String
    let engineVersion: String
    let tempoBpm: Double?
    let keyGuess: String?
    var noteEvents: [NoteEvent]
}

struct NoteEvent: Decodable, Identifiable {
    var pitchMidi: Int
    var onsetSeconds: Double
    var durationSeconds: Double
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
    
    init(pitchMidi: Int, onsetSeconds: Double, durationSeconds: Double, velocity: Double, confidence: Double, onsetUncertaintySeconds: Double? = nil, staffHint: StaffHint = .unknown, isLocked: Bool = false) {
        self.pitchMidi = pitchMidi
        self.onsetSeconds = onsetSeconds
        self.durationSeconds = durationSeconds
        self.velocity = velocity
        self.confidence = confidence
        self.onsetUncertaintySeconds = onsetUncertaintySeconds
        self.staffHint = staffHint
        self.isLocked = isLocked
    }
}

enum StaffHint: String, Decodable {
    case treble
    case bass
    case unknown
}
