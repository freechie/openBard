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
                    editMode: editMode
                )
                .frame(minHeight: 200)
                .onTapGesture { location in
                    handlePianoRollTap(location: location, in: transcription.noteEvents)
                }
                
                HStack(spacing: 12) {
                    Button(editMode == .nudge ? "Nudge ✓" : "Nudge") {
                        editMode = editMode == .nudge ? .inactive : .nudge
                        selectedNoteIndex = nil
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
    
    private func handlePianoRollTap(location: CGPoint, in notes: [NoteEvent]) {
        guard editMode != .inactive else { return }
        selectedNoteIndex = nil
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
}

#Preview {
    ContentView()
}
