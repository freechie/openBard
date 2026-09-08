import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var transcription: TranscriptionResult?
    @StateObject private var audioPlayer = DemoAudioPlayer()
    @State private var isImporterPresented = false
    @State private var playbackError: String?
    @State private var selectedFixture: AudioFixture = .cMajorChord
    @State private var selectedNoteIndex: Int?
    @State private var editMode: EditMode = .inactive

    init() {
        _transcription = State(initialValue: try? TranscriptionLoader.loadDemo())
    }
    
    enum EditMode {
        case inactive
        case nudge
        case delete
        case split
        case merge
    }

    var body: some View {
        VStack(spacing: 12) {
            if let transcription {
                Text("openBard")
                    .font(.title)
                    .bold()
                Text("Engine: \(transcription.engine)")
                if let keyGuess = transcription.keyGuess {
                    Text("Key: \(keyGuess)")
                }
                if let tempoBpm = transcription.tempoBpm {
                    Text("Tempo: \(tempoBpm, specifier: "%.0f") BPM")
                }
                Text("Notes: \(transcription.noteEvents.count)")
                Text("Audio: \(audioPlayer.sourceName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("audio-source")

                PianoRollView(
                    notes: transcription.noteEvents,
                    selectedNoteIndex: $selectedNoteIndex,
                    editMode: editMode,
                    onNudge: { index, translation in
                        nudgeNote(at: index, by: translation)
                    }
                )
                .frame(minHeight: 200)
                
                HStack(spacing: 12) {
                    Button(editMode == .nudge ? "Nudge ✓" : "Nudge") {
                        editMode = editMode == .nudge ? .inactive : .nudge
                    }
                    .buttonStyle(.bordered)
                    .tint(editMode == .nudge ? .blue : .gray)
                    .accessibilityIdentifier("nudge-button")
                    
                    Button("Delete") {
                        if let index = selectedNoteIndex {
                            deleteNote(at: index)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(selectedNoteIndex == nil)
                    .accessibilityIdentifier("delete-button")
                    
                    Button("Lock") {
                        if let index = selectedNoteIndex {
                            lockNote(at: index)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(selectedNoteIndex == nil)
                    .accessibilityIdentifier("lock-button")
                    
                    Button("Split") {
                        if let index = selectedNoteIndex {
                            splitNote(at: index)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(selectedNoteIndex == nil || (selectedNoteIndex.map { transcription.noteEvents[$0].isLocked } ?? false))
                    .accessibilityIdentifier("split-button")
                    
                    Button("Merge") {
                        if let index = selectedNoteIndex {
                            mergeNote(at: index)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                    .disabled(selectedNoteIndex == nil || (selectedNoteIndex.map { transcription.noteEvents[$0].isLocked } ?? false))
                    .accessibilityIdentifier("merge-button")
                }
                .padding(.vertical, 4)
                
                VStack(spacing: 8) {
                    Text("Bundled Fixtures")
                        .font(.headline)
                    
                    Picker("Select Audio", selection: $selectedFixture) {
                        ForEach(AudioFixture.allCases) { fixture in
                            Text(fixture.rawValue).tag(fixture)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fixture-picker")
                    .onChange(of: selectedFixture) { _, newFixture in
                        editMode = .inactive
                        selectedNoteIndex = nil
                        loadFixture(newFixture)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Button(audioPlayer.isPlaying ? "Stop" : "Play") {
                        togglePlayback()
                    }
                    .accessibilityIdentifier("play-demo-audio")

                    Button("Import audio") {
                        audioPlayer.stop()
                        isImporterPresented = true
                    }
                    .accessibilityIdentifier("import-audio")
                }

                if let playbackError {
                    Text(playbackError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Failed to load demo transcription")
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio, .wav, .mpeg4Audio, .mp3],
            allowsMultipleSelection: false
        ) { result in
            importAudio(result)
        }
    }

    private func loadFixture(_ fixture: AudioFixture) {
        playbackError = nil
        
        do {
            let url = try TranscriptionLoader.fixtureAudioURL(fixture)
            try audioPlayer.play(url: url, name: "\(fixture.rawValue).wav")
            
            if let fixtureTranscription = try TranscriptionLoader.loadFixture(fixture) {
                transcription = fixtureTranscription
            } else {
                transcription = try TranscriptionLoader.loadDemo()
            }
        } catch {
            playbackError = "Could not load fixture: \(fixture.rawValue)"
        }
    }

    private func togglePlayback() {
        playbackError = nil
        if audioPlayer.isPlaying {
            audioPlayer.stop()
            return
        }
        loadFixture(selectedFixture)
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        playbackError = nil
        guard case .success(let urls) = result, let url = urls.first else {
            playbackError = "Could not import audio"
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("openbard-import-\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.copyItem(at: url, to: destination)
            try audioPlayer.play(url: destination, name: url.lastPathComponent)
        } catch {
            playbackError = "Could not play imported audio"
        }
    }
    
    private func deleteNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        trans.noteEvents.remove(at: index)
        transcription = trans
        selectedNoteIndex = nil
    }
    
    private func lockNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        trans.noteEvents[index].isLocked = true
        transcription = trans
        selectedNoteIndex = nil
    }
    
    private func nudgeNote(at index: Int, by translation: CGSize) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        guard !trans.noteEvents[index].isLocked else { return }
        
        let timeScale: Double = 0.01
        let pitchScale: Double = 1.0 / 20.0
        
        let timeOffset = Double(translation.width) * timeScale
        let pitchOffset = Int(-translation.height * pitchScale)
        
        trans.noteEvents[index].onsetSeconds = max(0, trans.noteEvents[index].onsetSeconds + timeOffset)
        
        let newPitch = trans.noteEvents[index].pitchMidi + pitchOffset
        if newPitch >= 0 && newPitch <= 127 {
            trans.noteEvents[index].pitchMidi = newPitch
        }
        
        transcription = trans
    }
    
    private func splitNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        guard !trans.noteEvents[index].isLocked else { return }
        
        let note = trans.noteEvents[index]
        guard note.durationSeconds > 0.1 else { return }
        
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
        
        trans.noteEvents.remove(at: index)
        trans.noteEvents.insert(firstNote, at: index)
        trans.noteEvents.insert(secondNote, at: index + 1)
        transcription = trans
        selectedNoteIndex = index + 1
    }
    
    private func mergeNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        let note = trans.noteEvents[index]
        guard !note.isLocked else { return }
        
        let mergeCandidateIndex = trans.noteEvents.enumerated().first { otherIndex, otherNote in
            otherIndex != index &&
            !otherNote.isLocked &&
            otherNote.pitchMidi == note.pitchMidi &&
            abs(otherNote.onsetSeconds - (note.onsetSeconds + note.durationSeconds)) < 0.05
        }?.offset
        
        guard let mergeIndex = mergeCandidateIndex else { return }
        
        let otherNote = trans.noteEvents[mergeIndex]
        let earlierIndex = note.onsetSeconds < otherNote.onsetSeconds ? index : mergeIndex
        let laterIndex = note.onsetSeconds < otherNote.onsetSeconds ? mergeIndex : index
        let earlierNote = trans.noteEvents[earlierIndex]
        let laterNote = trans.noteEvents[laterIndex]
        
        let mergedNote = NoteEvent(
            pitchMidi: earlierNote.pitchMidi,
            onsetSeconds: earlierNote.onsetSeconds,
            durationSeconds: (laterNote.onsetSeconds + laterNote.durationSeconds) - earlierNote.onsetSeconds,
            velocity: max(earlierNote.velocity, laterNote.velocity),
            confidence: max(earlierNote.confidence, laterNote.confidence),
            onsetUncertaintySeconds: earlierNote.onsetUncertaintySeconds,
            staffHint: earlierNote.staffHint,
            isLocked: false
        )
        
        trans.noteEvents.remove(at: max(earlierIndex, laterIndex))
        trans.noteEvents.remove(at: min(earlierIndex, laterIndex))
        trans.noteEvents.insert(mergedNote, at: min(earlierIndex, laterIndex))
        transcription = trans
        selectedNoteIndex = min(earlierIndex, laterIndex)
    }
}

#Preview {
    ContentView()
}
