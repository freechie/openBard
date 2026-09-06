import CoreGraphics
import Foundation
import Testing
@testable import Audio2Score

final class TestBundleMarker {}

struct Audio2ScoreTests {
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
}
