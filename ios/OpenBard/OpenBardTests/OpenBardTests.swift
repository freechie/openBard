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
        #expect(isolatedPianoTranscription?.noteEvents.count == 21)
        
        let mixedTranscription = try TranscriptionLoader.loadFixture(.mixedArrangement, from: bundle)
        #expect(mixedTranscription != nil)
        #expect(mixedTranscription?.noteEvents.count == 37)
        
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
    
    @Test func pianoRollLabelPositionsMatchFrames() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0.5, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 67, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let size = CGSize(width: 300, height: 150)
        let frames = PianoRollLayout.frames(notes: notes, in: size)
        
        let pitches = notes.map(\.pitchMidi)
        guard let minPitch = pitches.min(), let maxPitch = pitches.max() else {
            #expect(Bool(false))
            return
        }
        
        let pitchSpan = maxPitch - minPitch
        let rowHeight = size.height / CGFloat(pitchSpan + 1)
        
        for (index, note) in notes.enumerated() {
            let frame = frames[index]
            let expectedLabelY = CGFloat(maxPitch - note.pitchMidi) * rowHeight + rowHeight / 2
            let frameCenterY = frame.midY
            
            #expect(abs(expectedLabelY - frameCenterY) < rowHeight / 2)
            #expect(expectedLabelY >= 0)
            #expect(expectedLabelY <= size.height)
        }
    }

    @Test func pianoRollKeepsIsolatedPianoNotesVisible() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try TranscriptionLoader.loadFixture(.isolatedPiano, from: bundle)
        let notes = try #require(transcription?.noteEvents)
        let size = CGSize(width: 320, height: 200)
        let frames = PianoRollLayout.frames(notes: notes, in: size)

        #expect(frames.count == 21)
        #expect(frames.allSatisfy { $0.width >= 2 && $0.height >= 2 })
        #expect(frames.allSatisfy { $0.minY >= 0 && $0.maxY <= size.height + 0.5 })
    }

    @Test func scoreBuilderReturnsNilWithoutLockedNotes() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        #expect(ScoreBuilder.build(from: notes) == nil)
    }

    @Test func scoreBuilderIgnoresUnlockedNotes() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 72, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        let noteCount = score!.measures.flatMap(\.items).filter {
            if case .note = $0 { return true }
            return false
        }.count
        #expect(noteCount == 1)
    }

    @Test func scoreBuilderQuantizesLockedCMajorChordToOneMeasure() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        #expect(score!.tempoBpm == 120)
        #expect(score!.clef == .treble)
        #expect(score!.measures.count == 1)
        let notesInScore = score!.measures[0].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        #expect(notesInScore.map(\.pitchMidi) == [60, 64, 67])
        #expect(notesInScore.allSatisfy { $0.startBeat == 0 && $0.durationBeats == 4 && !$0.tiedToNext })
        #expect(!score!.measures[0].items.contains { if case .rest = $0 { return true }; return false })
    }

    @Test func scoreBuilderInsertsTrailingRestAfterQuarter() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 0.5, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        #expect(score!.measures.count == 1)
        guard case .note(let note) = score!.measures[0].items.first else {
            #expect(Bool(false))
            return
        }
        #expect(note.durationBeats == 1)
        guard case .rest(let rest) = score!.measures[0].items.last else {
            #expect(Bool(false))
            return
        }
        #expect(rest.startBeat == 1)
        #expect(rest.durationBeats == 3)
    }

    @Test func scoreBuilderTiesNoteAcrossBarline() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 1.5, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        #expect(score!.tempoBpm == 120)
        #expect(score!.measures.count == 2)
        let firstNotes = score!.measures[0].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        let secondNotes = score!.measures[1].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        #expect(firstNotes.count == 1)
        #expect(firstNotes[0].startBeat == 3)
        #expect(firstNotes[0].durationBeats == 1)
        #expect(firstNotes[0].tiedToNext)
        #expect(secondNotes.count == 1)
        #expect(secondNotes[0].startBeat == 4)
        #expect(secondNotes[0].durationBeats == 1)
        #expect(!secondNotes[0].tiedToNext)
    }

    @Test func zoomMathClampsScale() {
        #expect(ZoomMath.clamp(0) == ZoomMath.minimum)
        #expect(ZoomMath.clamp(1) == 1)
        #expect(ZoomMath.clamp(99) == ZoomMath.maximum)
    }

    @Test func zoomMathScalesContentToViewport() {
        let size = ZoomMath.contentSize(viewport: CGSize(width: 100, height: 50), scale: 2)
        #expect(size.width == 200)
        #expect(size.height == 100)
    }

    @Test func zoomMathClampsPanToScaledExtra() {
        let offset = ZoomMath.clampOffset(
            CGSize(width: 5000, height: -5000),
            viewport: CGSize(width: 100, height: 80),
            scale: 2
        )
        #expect(offset.width == 74)
        #expect(offset.height == -64)
    }

    @Test func staffLineSpacingGrowsWithViewportHeight() {
        let small = StaffLayout.lineSpacing(in: CGSize(width: 320, height: 96))
        let large = StaffLayout.lineSpacing(in: CGSize(width: 320, height: 240))
        #expect(large > small)
        #expect(small >= 8)
    }
}
