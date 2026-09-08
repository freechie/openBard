import CoreGraphics
import Foundation
import Testing
@testable import OpenBard

final class TestBundleMarker {}

struct OpenBardTests {
    @Test func decodesDemoTranscription() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try TranscriptionLoader.loadDemo(from: bundle)

        #expect(transcription.engine == "dsp_v0")
        #expect(transcription.keyGuess == "C major")
        #expect(transcription.tempoBpm == 120)
        #expect(transcription.noteEvents.count == 3)
        #expect(transcription.noteEvents.map(\.pitchMidi) == [60, 64, 67])
        #expect(transcription.noteEvents.allSatisfy { $0.onsetSeconds == 0 })
        #expect(transcription.noteEvents.allSatisfy { $0.durationSeconds == 2 })
    }

    @Test func demoAudioIsBundled() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let url = try TranscriptionLoader.demoAudioURL(from: bundle)
        let data = try Data(contentsOf: url)

        #expect(url.lastPathComponent == "c-major-chord.wav")
        #expect(data.starts(with: Data("RIFF".utf8)))
    }
    
    @Test func fixtureAudioIsBundled() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        
        for fixture in AudioFixture.allCases {
            let url = try TranscriptionLoader.fixtureAudioURL(fixture, from: bundle)
            let data = try Data(contentsOf: url)
            
            #expect(url.lastPathComponent.hasSuffix(".wav"))
            #expect(data.starts(with: Data("RIFF".utf8)))
        }
    }
    
    @Test func fixtureGroundTruthLoads() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        
        let isolatedPianoTranscription = try TranscriptionLoader.loadFixture(.isolatedPiano, from: bundle)
        #expect(isolatedPianoTranscription != nil)
        #expect(isolatedPianoTranscription?.noteEvents.count == 12)
        
        let mixedTranscription = try TranscriptionLoader.loadFixture(.mixedArrangement, from: bundle)
        #expect(mixedTranscription != nil)
        #expect(mixedTranscription?.noteEvents.count == 32)
        
        let cMajorTranscription = try TranscriptionLoader.loadFixture(.cMajorChord, from: bundle)
        #expect(cMajorTranscription == nil)
    }

    @Test func pianoRollStacksChordNotes() {
        let notes = [
            NoteEvent(
                pitchMidi: 60,
                onsetSeconds: 0,
                durationSeconds: 2,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            ),
            NoteEvent(
                pitchMidi: 64,
                onsetSeconds: 0,
                durationSeconds: 2,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            ),
            NoteEvent(
                pitchMidi: 67,
                onsetSeconds: 0,
                durationSeconds: 2,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            ),
        ]
        let frames = PianoRollLayout.frames(
            notes: notes,
            in: CGSize(width: 200, height: 100)
        )

        #expect(frames.count == 3)
        #expect(frames[0].minX == frames[1].minX)
        #expect(frames[0].minX == frames[2].minX)
        #expect(frames[2].minY < frames[1].minY)
        #expect(frames[1].minY < frames[0].minY)
    }
    
    @Test func splitNoteAtMidpoint() {
        let note = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 1.0,
            durationSeconds: 2.0,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble
        )
        
        let result = NoteHelpers.splitNote(note)
        #expect(result != nil)
        
        let (first, second) = result!
        #expect(first.pitchMidi == 60)
        #expect(first.onsetSeconds == 1.0)
        #expect(first.durationSeconds == 1.0)
        #expect(second.onsetSeconds == 2.0)
        #expect(second.durationSeconds == 1.0)
        #expect(!first.isLocked && !second.isLocked)
    }
    
    @Test func splitRejectsShortNotes() {
        let shortNote = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 0.05,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble
        )
        
        #expect(NoteHelpers.splitNote(shortNote) == nil)
    }
    
    @Test func splitRejectsLockedNotes() {
        let lockedNote = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 2.0,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble,
            isLocked: true
        )
        
        #expect(NoteHelpers.splitNote(lockedNote) == nil)
    }
    
    @Test func mergeAdjacentNotes() {
        let note1 = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 1.0,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble
        )
        let note2 = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 1.0,
            durationSeconds: 1.0,
            velocity: 0.7,
            confidence: 0.85,
            staffHint: .treble
        )
        
        let merged = NoteHelpers.mergeNotes(note1, note2)
        #expect(merged != nil)
        #expect(merged!.pitchMidi == 60)
        #expect(merged!.onsetSeconds == 0)
        #expect(merged!.durationSeconds == 2.0)
        #expect(merged!.velocity == 0.8)
        #expect(merged!.confidence == 0.9)
        #expect(!merged!.isLocked)
    }
    
    @Test func mergeRejectsDifferentPitches() {
        let note1 = NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let note2 = NoteEvent(pitchMidi: 64, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        
        #expect(NoteHelpers.mergeNotes(note1, note2) == nil)
    }
    
    @Test func mergeRejectsLockedNotes() {
        let note1 = NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble, isLocked: true)
        let note2 = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        
        #expect(NoteHelpers.mergeNotes(note1, note2) == nil)
    }
    
    @Test func nudgeAdjustsTiming() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: 0.5, pitchOffset: 0)
        
        #expect(nudged != nil)
        #expect(nudged!.onsetSeconds == 1.5)
        #expect(nudged!.pitchMidi == 60)
    }
    
    @Test func nudgeAdjustsPitch() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: 0, pitchOffset: 2)
        
        #expect(nudged != nil)
        #expect(nudged!.onsetSeconds == 1.0)
        #expect(nudged!.pitchMidi == 62)
    }
    
    @Test func nudgeRejectsInvalidPitch() {
        let note = NoteEvent(pitchMidi: 127, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: 0, pitchOffset: 1)
        
        #expect(nudged == nil)
    }
    
    @Test func nudgeClampsNegativeTime() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 0.5, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: -1.0, pitchOffset: 0)
        
        #expect(nudged != nil)
        #expect(nudged!.onsetSeconds == 0)
    }
    
    @Test func findsMergeCandidate() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble),
            NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        ]
        
        let candidate = NoteHelpers.findMergeCandidate(for: notes[0], in: notes, currentIndex: 0)
        #expect(candidate == 1)
    }
}
