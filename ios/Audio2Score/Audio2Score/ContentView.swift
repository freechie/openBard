//
//  ContentView.swift
//  Audio2Score
//
//  Created by richie on 7/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private let transcription: TranscriptionResult?
    @StateObject private var audioPlayer = DemoAudioPlayer()
    @State private var isImporterPresented = false
    @State private var playbackError: String?

    init() {
        transcription = try? TranscriptionLoader.loadDemo()
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

                HStack {
                    Button(audioPlayer.isPlaying ? "Stop" : "Play demo audio") {
                        toggleDemoPlayback()
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

    private func toggleDemoPlayback() {
        playbackError = nil
        if audioPlayer.isPlaying {
            audioPlayer.stop()
            return
        }
        do {
            try audioPlayer.playDemo()
        } catch {
            playbackError = "Could not play demo audio"
        }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        playbackError = nil
        switch result {
        case .failure:
            playbackError = "Could not import audio"
        case .success(let urls):
            guard let url = urls.first else {
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
}

#Preview {
    ContentView()
}
