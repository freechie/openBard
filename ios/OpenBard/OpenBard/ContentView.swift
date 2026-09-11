import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
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
    
    private var theme: AbletonTheme {
        AbletonTheme.current(for: colorScheme)
    }
    
    enum EditMode {
        case inactive
        case nudge
        case delete
        case split
        case merge
    }

    var body: some View {
        VStack(spacing: 8) {
            if let transcription {
                metadataHeader(transcription)

                ZoomableViewport(allowsPan: editMode != .nudge, theme: theme) {
                    PianoRollView(
                        notes: transcription.noteEvents,
                        selectedNoteIndex: $selectedNoteIndex,
                        editMode: editMode,
                        theme: theme,
                        onNudge: { index, translation in
                            nudgeNote(at: index, by: translation)
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 140)
                .layoutPriority(1)
                .accessibilityIdentifier("piano-roll-viewport")

                editToolbar(transcription)

                Button("Lock all") {
                    lockAllNotes()
                }
                .tint(theme.success)
                .disabled(transcription.noteEvents.isEmpty || transcription.noteEvents.allSatisfy(\.isLocked))
                .accessibilityIdentifier("lock-all-button")

                scoreSection(transcription)

                fixturePicker

                HStack {
                    Button(audioPlayer.isPlaying ? "Stop" : "Play") {
                        togglePlayback()
                    }
                    .tint(theme.accent)
                    .accessibilityIdentifier("play-demo-audio")

                    Button("Import audio") {
                        audioPlayer.stop()
                        isImporterPresented = true
                    }
                    .tint(theme.accent)
                    .accessibilityIdentifier("import-audio")
                }

                if let playbackError {
                    Text(playbackError)
                        .font(.footnote)
                        .foregroundColor(theme.danger)
                }
            } else {
                Text("Failed to load demo transcription")
                    .foregroundColor(theme.danger)
            }
        }
        .padding()
        .background(theme.background)
        .foregroundColor(theme.textPrimary)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio, .wav, .mpeg4Audio, .mp3],
            allowsMultipleSelection: false
        ) { result in
            importAudio(result)
        }
    }

    private func metadataHeader(_ transcription: TranscriptionResult) -> some View {
        let key = transcription.keyGuess.map { " · \($0)" } ?? ""
        let tempo = transcription.tempoBpm.map { String(format: " · %.0f BPM", $0) } ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text("openBard")
                .font(.headline)
                .bold()
                .foregroundColor(theme.textPrimary)
            Text("\(transcription.engine)\(key)\(tempo) · \(transcription.noteEvents.count) notes")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(audioPlayer.sourceName)
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .accessibilityIdentifier("audio-source")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editToolbar(_ transcription: TranscriptionResult) -> some View {
        HStack(spacing: 12) {
            Button {
                editMode = editMode == .nudge ? .inactive : .nudge
            } label: {
                Image(systemName: editMode == .nudge ? "hand.draw.fill" : "hand.draw")
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundColor(editMode == .nudge ? theme.accent : theme.textSecondary)
            }
            .buttonStyle(.bordered)
            .tint(editMode == .nudge ? theme.accent : theme.border)
            .accessibilityLabel("Nudge")
            .accessibilityIdentifier("nudge-button")

            Button {
                if let index = selectedNoteIndex {
                    deleteNote(at: index)
                }
            } label: {
                Image(systemName: "trash")
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundColor(theme.danger)
            }
            .buttonStyle(.bordered)
            .tint(theme.danger)
            .disabled(selectedNoteIndex == nil)
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("delete-button")

            Button {
                if let index = selectedNoteIndex {
                    lockNote(at: index)
                }
            } label: {
                Image(systemName: "lock")
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundColor(theme.success)
            }
            .buttonStyle(.bordered)
            .tint(theme.success)
            .disabled(selectedNoteIndex == nil)
            .accessibilityLabel("Lock")
            .accessibilityIdentifier("lock-button")

            Button {
                if let index = selectedNoteIndex {
                    splitNote(at: index)
                }
            } label: {
                Image(systemName: "scissors")
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundColor(theme.accent.opacity(0.85))
            }
            .buttonStyle(.bordered)
            .tint(theme.accentDim)
            .disabled(selectedNoteIndex == nil || (selectedNoteIndex.map { transcription.noteEvents[$0].isLocked } ?? false))
            .accessibilityLabel("Split")
            .accessibilityIdentifier("split-button")

            Button {
                if let index = selectedNoteIndex {
                    mergeNote(at: index)
                }
            } label: {
                Image(systemName: "arrow.triangle.merge")
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundColor(theme.accent.opacity(0.85))
            }
            .buttonStyle(.bordered)
            .tint(theme.accentDim)
            .disabled(selectedNoteIndex == nil || (selectedNoteIndex.map { transcription.noteEvents[$0].isLocked } ?? false))
            .accessibilityLabel("Merge")
            .accessibilityIdentifier("merge-button")
        }
    }

    @ViewBuilder
    private func scoreSection(_ transcription: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Score")
                .font(.subheadline)
                .bold()
                .foregroundColor(theme.textPrimary)
            if let score = ScoreBuilder.build(from: transcription.noteEvents) {
                Text(StaffLayout.summary(for: score))
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .accessibilityIdentifier("score-summary")
                ZoomableViewport(theme: theme) {
                    StaffPreviewView(score: score, theme: theme)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 120)
                .accessibilityIdentifier("staff-viewport")
            } else {
                ZoomableViewport(theme: theme) {
                    Text("Lock notes to build a score")
                        .font(.subheadline)
                        .foregroundColor(theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("score-empty")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 120)
                .accessibilityIdentifier("staff-viewport")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 150)
        .layoutPriority(1)
    }

    private var fixturePicker: some View {
        VStack(spacing: 6) {
            Text("Bundled Fixtures")
                .font(.subheadline)
                .bold()
                .foregroundColor(theme.textPrimary)

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

    private func lockAllNotes() {
        guard var trans = transcription else { return }
        for index in trans.noteEvents.indices {
            trans.noteEvents[index].isLocked = true
        }
        transcription = trans
        selectedNoteIndex = nil
        editMode = .inactive
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
