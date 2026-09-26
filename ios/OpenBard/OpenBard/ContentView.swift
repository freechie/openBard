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
    @State private var isDraggingNote = false
    @State private var workspace: Workspace = .pianoRoll
    @State private var isLibraryMenuExpanded = false
    @State private var pianoRollViewport: PianoRollViewport = .blank
    @State private var timeWindow: PianoRollTimeWindow = .blank()
    @State private var isDrawMode = true
    @State private var isTranscribing = false
    @State private var preparedScore: Score?
    @State private var preparedMIDI: Data?
    @State private var preparedMusicXML: Data?
    @AppStorage(WorkerSettings.storageKey) private var workerBaseURLString = WorkerSettings.defaultBaseURLString

    init() {
        _transcription = State(initialValue: TranscriptionResult(
            engine: "manual",
            engineVersion: "0",
            tempoBpm: NoteHelpers.defaultTempoBpm,
            keyGuess: nil,
            noteEvents: []
        ))
        _pianoRollViewport = State(initialValue: .blank)
        _timeWindow = State(initialValue: .blank())
    }
    
    private var theme: AbletonTheme {
        AbletonTheme.current(for: colorScheme)
    }

    enum Workspace: String, CaseIterable, Identifiable {
        case pianoRoll = "Piano roll"
        case score = "Score"

        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let canvas = proxy.size
            ZStack {
                Group {
                    if let transcription {
                        editorBody(transcription)
                    } else {
                        Text("Failed to create blank roll")
                            .foregroundColor(theme.danger)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: canvas.width, height: canvas.height)

                if isLibraryMenuExpanded {
                    libraryWindow
                        .frame(width: canvas.width, height: canvas.height)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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

    private func editorBody(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 10) {
            topBar(transcription)
            workspacePicker

            workspaceStage(transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            statusFooter
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if isTranscribing {
            Text("Transcribing...")
                .font(.footnote)
                .foregroundColor(theme.textSecondary)
                .accessibilityIdentifier("transcribe-status")
        } else if let playbackError {
            Text(playbackError)
                .font(.footnote)
                .foregroundColor(theme.danger)
                .accessibilityIdentifier("import-error")
        }
    }

    private func topBar(_ transcription: TranscriptionResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            metadataHeader(transcription)
            Spacer(minLength: 8)
            libraryMenuToggle
        }
    }

    private var libraryMenuToggle: some View {
        Button {
            isLibraryMenuExpanded.toggle()
        } label: {
            Image(systemName: isLibraryMenuExpanded ? "xmark.circle.fill" : "line.3.horizontal.circle")
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundColor(theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLibraryMenuExpanded ? "Close library menu" : "Open library menu")
        .accessibilityIdentifier("library-menu-button")
    }

    private var libraryMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.subheadline)
                .bold()
                .foregroundColor(theme.textPrimary)

            Text("Bundled fixtures")
                .font(.caption)
                .foregroundColor(theme.textSecondary)

            Picker("Select Audio", selection: $selectedFixture) {
                ForEach(AudioFixture.allCases) { fixture in
                    Text(fixture.rawValue).tag(fixture)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fixture-picker")
            .onChange(of: selectedFixture) { _, newFixture in
                selectedNoteIndex = nil
                loadFixture(newFixture)
            }

            Button {
                createBlankRoll()
            } label: {
                Label("New blank", systemImage: "doc")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(theme.accentDim)
            .accessibilityIdentifier("new-blank")

            Button {
                audioPlayer.stop()
                isImporterPresented = true
            } label: {
                Label(isTranscribing ? "Transcribing..." : "Import audio", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .disabled(isTranscribing)
            .accessibilityIdentifier("import-audio")

            Text("Worker URL")
                .font(.caption)
                .foregroundColor(theme.textSecondary)

            TextField(WorkerSettings.defaultBaseURLString, text: $workerBaseURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.plain)
                .font(.footnote)
                .padding(8)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border, lineWidth: 1)
                )
                .accessibilityIdentifier("worker-base-url")

            Text("Simulator default is \(WorkerSettings.defaultBaseURLString)")
                .font(.caption2)
                .foregroundColor(theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("library-menu")
    }

    /// Same size as the editor underneath. The card is centered in that rect and does not join the roll's stack.
    private var libraryWindow: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture {
                    isLibraryMenuExpanded = false
                }
                .accessibilityLabel("Dismiss library")
                .accessibilityIdentifier("library-menu-scrim")

            libraryMenu
                .frame(maxWidth: 420)
                .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 10)
                .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: workspaceSelection) {
            ForEach(Workspace.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("workspace-picker")
        .onChange(of: workspace) { _, _ in
            selectedNoteIndex = nil
            isDraggingNote = false
        }
    }

    private var workspaceSelection: Binding<Workspace> {
        Binding(
            get: { workspace },
            set: { newValue in
                if newValue == .score, let transcription {
                    refreshScoreExports(for: transcription)
                }
                workspace = newValue
            }
        )
    }

    private func refreshScoreExports(for transcription: TranscriptionResult) {
        let score = ScoreBuilder.build(
            from: transcription.noteEvents,
            tempoBpm: transcription.tempoBpm
        )
        preparedScore = score
        preparedMIDI = try? MIDIExporter.makeData(
            from: transcription.noteEvents,
            tempoBpm: transcription.tempoBpm
        )
        if let score {
            preparedMusicXML = try? MusicXMLExporter.makeData(from: score)
        } else {
            preparedMusicXML = nil
        }
    }

    @ViewBuilder
    private func workspaceStage(_ transcription: TranscriptionResult) -> some View {
        switch workspace {
        case .pianoRoll:
            pianoWorkspace(transcription)
        case .score:
            scoreWorkspace(transcription)
        }
    }

    private func pianoWorkspace(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 8) {
            transportBar(transcription)

            PianoRollOverview(
                notes: transcription.noteEvents,
                timeWindow: $timeWindow,
                tempoBpm: transcription.tempoBpm ?? NoteHelpers.defaultTempoBpm,
                theme: theme
            )

            pianoViewport(transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Draw notes. Drag edges to resize. Pinch or use the overview to zoom")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("piano-roll-caption")

            toolStrip(transcription, mode: .pianoRoll)
        }
    }

    private func scoreWorkspace(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 8) {
            scoreSection()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            toolStrip(transcription, mode: .score)
            Text("Score builds from all notes on the roll. Edit timing in Piano roll.")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func transportBar(_ transcription: TranscriptionResult) -> some View {
        let bpm = transcription.tempoBpm ?? NoteHelpers.defaultTempoBpm
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(String(format: "%.0f", bpm))
                    .font(.system(.title3, design: .monospaced))
                    .bold()
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("tempo-bpm")
                Text("BPM")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    adjustTempo(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(theme.accentDim)
                .accessibilityIdentifier("tempo-down")

                Button {
                    adjustTempo(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(theme.accentDim)
                .accessibilityIdentifier("tempo-up")
            }

            Spacer(minLength: 8)

            iconButton(
                systemName: audioPlayer.isPlaying ? "stop.fill" : "play.fill",
                tint: theme.accent,
                foreground: theme.accent,
                label: audioPlayer.isPlaying ? "Stop" : "Play",
                id: "play-demo-audio",
                disabled: !audioPlayer.isPlaying && transcription.noteEvents.isEmpty
            ) {
                togglePlayback(transcription)
            }

            iconButton(
                systemName: "pencil",
                tint: isDrawMode ? theme.accent : theme.accentDim,
                foreground: isDrawMode ? theme.accent : theme.accent.opacity(0.85),
                label: isDrawMode ? "Draw on" : "Draw",
                id: "draw-button"
            ) {
                isDrawMode.toggle()
            }
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("transport-bar")
    }

    private func pianoViewport(_ transcription: TranscriptionResult) -> some View {
        PianoRollView(
            notes: transcription.noteEvents,
            viewport: pianoRollViewport,
            timeWindow: $timeWindow,
            tempoBpm: transcription.tempoBpm,
            isDrawMode: isDrawMode,
            selectedNoteIndex: $selectedNoteIndex,
            isDraggingNote: $isDraggingNote,
            theme: theme,
            onEditNote: { index, note in
                applyEditedNote(note, at: index)
            },
            onCreateNote: { note in
                createNote(note)
            }
        )
        .background(theme.pianoRollBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("piano-roll-viewport")
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

    private func toolStrip(_ transcription: TranscriptionResult, mode: Workspace) -> some View {
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if mode == .pianoRoll {
                    iconButton(
                        systemName: "trash",
                        tint: theme.danger,
                        foreground: theme.danger,
                        label: "Delete",
                        id: "delete-button",
                        disabled: selectedNoteIndex == nil
                    ) {
                        if let index = selectedNoteIndex {
                            deleteNote(at: index)
                        }
                    }

                    iconButton(
                        systemName: "scissors",
                        tint: theme.accentDim,
                        foreground: theme.accent.opacity(0.85),
                        label: "Split",
                        id: "split-button",
                        disabled: selectedNoteIndex == nil
                    ) {
                        if let index = selectedNoteIndex {
                            splitNote(at: index)
                        }
                    }

                    iconButton(
                        systemName: "arrow.triangle.merge",
                        tint: theme.accentDim,
                        foreground: theme.accent.opacity(0.85),
                        label: "Merge",
                        id: "merge-button",
                        disabled: !canMergeSelectedNote(in: transcription)
                    ) {
                        if let index = selectedNoteIndex {
                            mergeNote(at: index)
                        }
                    }
                } else {
                    if let midiData = preparedMIDI {
                        ShareLink(
                            item: MIDIFileDocument(data: midiData),
                            preview: SharePreview("openBard.mid")
                        ) {
                            Label("Export MIDI", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .frame(minHeight: 44)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                        .accessibilityIdentifier("export-midi")
                    }

                    if let musicXMLData = preparedMusicXML {
                        ShareLink(
                            item: MusicXMLFileDocument(data: musicXMLData),
                            preview: SharePreview("openBard.musicxml")
                        ) {
                            Label("Export MusicXML", systemImage: "doc.richtext")
                                .labelStyle(.titleAndIcon)
                                .frame(minHeight: 44)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accentDim)
                        .accessibilityIdentifier("export-musicxml")
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityIdentifier("tool-strip")
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        tint: Color,
        foreground: Color,
        label: String,
        id: String,
        disabled: Bool = false,
        showsTitle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if showsTitle {
                Label(label, systemImage: systemName)
                    .labelStyle(.titleAndIcon)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 6)
            } else {
                Image(systemName: systemName)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .foregroundColor(foreground)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func scoreSection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let score = preparedScore {
                Text(StaffLayout.summary(for: score))
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("score-summary")
                ZoomableViewport(theme: theme) {
                    StaffPreviewView(score: score, theme: theme)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("staff-viewport")
            } else {
                ZoomableViewport(theme: theme) {
                    Text("Draw notes in Piano roll to build a score")
                        .font(.subheadline)
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("score-empty")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("staff-viewport")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 160)
    }

    private func loadFixture(_ fixture: AudioFixture) {
        playbackError = nil
        selectedNoteIndex = nil
        isDrawMode = false
        audioPlayer.stop()

        do {
            let loaded: TranscriptionResult
            if let fixtureTranscription = try TranscriptionLoader.loadFixture(fixture) {
                loaded = fixtureTranscription
            } else {
                loaded = try TranscriptionLoader.loadDemo()
            }
            presentTranscription(loaded, drawMode: false)
            audioPlayer.clearSource(name: "\(fixture.rawValue) notes")
        } catch {
            playbackError = "Could not load fixture: \(fixture.rawValue)"
        }
    }

    private func presentTranscription(_ loaded: TranscriptionResult, drawMode: Bool) {
        selectedNoteIndex = nil
        isDrawMode = drawMode
        transcription = loaded
        let seeded = PianoRollViewport.seeded(
            from: loaded.noteEvents,
            tempoBpm: loaded.tempoBpm
        )
        pianoRollViewport = seeded
        timeWindow = .from(contentSeconds: seeded.timelineSeconds, tempoBpm: loaded.tempoBpm)
        if workspace == .score {
            refreshScoreExports(for: loaded)
        }
    }

    private func createBlankRoll() {
        playbackError = nil
        selectedNoteIndex = nil
        isDrawMode = true
        audioPlayer.clearSource(name: "Blank")
        transcription = TranscriptionResult(
            engine: "manual",
            engineVersion: "0",
            tempoBpm: NoteHelpers.defaultTempoBpm,
            keyGuess: nil,
            noteEvents: []
        )
        pianoRollViewport = .blank
        timeWindow = .blank()
        workspace = .pianoRoll
    }

    private func adjustTempo(by delta: Double) {
        guard var trans = transcription else { return }
        let current = trans.tempoBpm ?? NoteHelpers.defaultTempoBpm
        trans.tempoBpm = ScoreBuilder.clampTempo(current + delta)
        transcription = trans
    }

    private func syncTimeline(for note: NoteEvent) {
        pianoRollViewport = pianoRollViewport.expanding(toFit: note)
        var window = timeWindow
        window.syncContentSeconds(pianoRollViewport.timelineSeconds)
        timeWindow = window
    }

    private func togglePlayback(_ transcription: TranscriptionResult) {
        playbackError = nil
        if audioPlayer.isPlaying {
            audioPlayer.stop()
            return
        }
        guard !transcription.noteEvents.isEmpty else {
            playbackError = "Draw notes to play"
            return
        }
        let notes = transcription.noteEvents
        Task {
            do {
                try await audioPlayer.playNotes(notes, name: "Notes")
            } catch {
                playbackError = "Could not play notes"
            }
        }
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
            transcribeImportedAudio(at: destination, name: url.lastPathComponent)
        } catch {
            playbackError = "Could not import audio"
        }
    }

    private func transcribeImportedAudio(at fileURL: URL, name: String) {
        isTranscribing = true
        playbackError = nil
        audioPlayer.stop()
        Task {
            defer { isTranscribing = false }
            do {
                let baseURL = try WorkerSettings.baseURL(from: workerBaseURLString)
                let data = try await WorkerClient.transcribe(fileURL: fileURL, baseURL: baseURL)
                let loaded: TranscriptionResult
                do {
                    loaded = try TranscriptionLoader.decodeTranscription(from: data)
                } catch {
                    throw WorkerError.invalidTranscription
                }
                presentTranscription(loaded, drawMode: false)
                do {
                    try await audioPlayer.play(url: fileURL, name: name)
                } catch {
                    playbackError = "Could not play imported audio"
                }
            } catch let error as WorkerError {
                playbackError = error.localizedDescription
            } catch {
                playbackError = "Could not import audio"
            }
        }
    }

    private func deleteNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        trans.noteEvents.remove(at: index)
        transcription = trans
        selectedNoteIndex = nil
    }

    private func applyEditedNote(_ note: NoteEvent, at index: Int) {
        guard var trans = transcription else { return }
        guard trans.noteEvents.indices.contains(index) else { return }
        trans.noteEvents[index] = note
        transcription = trans
        syncTimeline(for: note)
    }

    private func createNote(_ note: NoteEvent) {
        guard var trans = transcription else { return }
        trans.noteEvents.append(note)
        transcription = trans
        selectedNoteIndex = trans.noteEvents.count - 1
        syncTimeline(for: note)
    }

    private func splitNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }

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

    private func canMergeSelectedNote(in transcription: TranscriptionResult) -> Bool {
        guard let index = selectedNoteIndex,
              transcription.noteEvents.indices.contains(index) else {
            return false
        }
        return NoteHelpers.findMergeCandidate(
            for: transcription.noteEvents[index],
            in: transcription.noteEvents,
            currentIndex: index
        ) != nil
    }

    private func mergeNote(at index: Int) {
        guard var trans = transcription else { return }
        guard trans.noteEvents.indices.contains(index) else { return }
        let note = trans.noteEvents[index]
        guard let mergeIndex = NoteHelpers.findMergeCandidate(
            for: note,
            in: trans.noteEvents,
            currentIndex: index
        ) else { return }
        guard let mergedNote = NoteHelpers.mergeNotes(note, trans.noteEvents[mergeIndex]) else {
            return
        }

        let insertIndex = min(index, mergeIndex)
        trans.noteEvents.remove(at: max(index, mergeIndex))
        trans.noteEvents.remove(at: min(index, mergeIndex))
        trans.noteEvents.insert(mergedNote, at: insertIndex)
        transcription = trans
        selectedNoteIndex = insertIndex
    }
}

#Preview {
    ContentView()
}
