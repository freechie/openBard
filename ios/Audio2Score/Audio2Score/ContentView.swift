import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var transcription: TranscriptionResult?
    @StateObject private var audioPlayer = DemoAudioPlayer()
    @State private var isImporterPresented = false
    @State private var playbackError: String?
    @State private var selectedFixture: AudioFixture = .cMajorChord

    init() {
        _transcription = State(initialValue: try? TranscriptionLoader.loadDemo())
    }

    var body: some View {
        VStack(spacing: 12) {
            if let transcription {
                Text("Audio2Score")
                    .font(.title)
                    .bold()
                Text("Engine: \(transcription.engine)")
                Text("Key: \(transcription.keyGuess)")
                Text("Tempo: \(transcription.tempoBpm, specifier: "%.0f") BPM")
                Text("Notes: \(transcription.noteEvents.count)")
                Text("Audio: \(audioPlayer.sourceName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("audio-source")

                PianoRollView(notes: transcription.noteEvents)
                    .frame(minHeight: 140)
                
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
                .appendingPathComponent("a2s-import-\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.copyItem(at: url, to: destination)
            try audioPlayer.play(url: destination, name: url.lastPathComponent)
        } catch {
            playbackError = "Could not play imported audio"
        }
    }
}

#Preview {
    ContentView()
}
