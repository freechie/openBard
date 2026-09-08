import Foundation

enum NoteHelpers {
    /// Split a note at its midpoint into two equal-duration notes
    static func splitNote(_ note: NoteEvent) -> (NoteEvent, NoteEvent)? {
        guard note.durationSeconds > 0.1 else { return nil }
        guard !note.isLocked else { return nil }
        
        let splitPoint = note.durationSeconds / 2.0
        let firstNote = NoteEvent(
            pitchMidi: note.pitchMidi,
            onsetSeconds: note.onsetSeconds,
            durationSeconds: splitPoint,
            velocity: note.velocity,
            confidence: note.confidence,
            onsetUncertaintySeconds: note.onsetUncertaintySeconds,
            staffHint: note.staffHint,
            isLocked: false
        )
        let secondNote = NoteEvent(
            pitchMidi: note.pitchMidi,
            onsetSeconds: note.onsetSeconds + splitPoint,
            durationSeconds: splitPoint,
            velocity: note.velocity,
            confidence: note.confidence,
            onsetUncertaintySeconds: note.onsetUncertaintySeconds,
            staffHint: note.staffHint,
            isLocked: false
        )
        return (firstNote, secondNote)
    }
    
    /// Find an adjacent note that can be merged with the given note
    /// Rules: same pitch, adjacent timing (within 50ms), neither locked
    static func findMergeCandidate(for note: NoteEvent, in notes: [NoteEvent], currentIndex: Int) -> Int? {
        return notes.enumerated().first { otherIndex, otherNote in
            otherIndex != currentIndex &&
            !note.isLocked &&
            !otherNote.isLocked &&
            otherNote.pitchMidi == note.pitchMidi &&
            abs(otherNote.onsetSeconds - (note.onsetSeconds + note.durationSeconds)) < 0.05
        }?.offset
    }
    
    /// Merge two notes into one
    /// The merged note spans from the earlier onset to the end of the later note
    static func mergeNotes(_ note1: NoteEvent, _ note2: NoteEvent) -> NoteEvent? {
        guard note1.pitchMidi == note2.pitchMidi else { return nil }
        guard !note1.isLocked && !note2.isLocked else { return nil }
        
        let earlierNote = note1.onsetSeconds < note2.onsetSeconds ? note1 : note2
        let laterNote = note1.onsetSeconds < note2.onsetSeconds ? note2 : note1
        
        return NoteEvent(
            pitchMidi: earlierNote.pitchMidi,
            onsetSeconds: earlierNote.onsetSeconds,
            durationSeconds: (laterNote.onsetSeconds + laterNote.durationSeconds) - earlierNote.onsetSeconds,
            velocity: max(earlierNote.velocity, laterNote.velocity),
            confidence: max(earlierNote.confidence, laterNote.confidence),
            onsetUncertaintySeconds: earlierNote.onsetUncertaintySeconds,
            staffHint: earlierNote.staffHint,
            isLocked: false
        )
    }
    
    /// Adjust note timing and/or pitch
    static func nudgeNote(_ note: NoteEvent, timeOffset: Double, pitchOffset: Int) -> NoteEvent? {
        guard !note.isLocked else { return nil }
        
        let newOnset = max(0, note.onsetSeconds + timeOffset)
        let newPitch = note.pitchMidi + pitchOffset
        
        guard newPitch >= 0 && newPitch <= 127 else { return nil }
        
        var result = note
        result.onsetSeconds = newOnset
        result.pitchMidi = newPitch
        return result
    }
}
