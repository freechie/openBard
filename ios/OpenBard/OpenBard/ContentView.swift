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
        Group {
            if let transcription {
                GeometryReader { geo in
                    let landscape = geo.size.width > geo.size.height * 1.05
                    if landscape {
                        landscapeBody(transcription)
                    } else {
                        portraitBody(transcription)
                    }
                }
            } else {
                Text("Failed to create blank roll")
                    .foregroundColor(theme.danger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func portraitBody(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 10) {
            topBar(transcription)
            workspacePicker

            workspaceStage(transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            if isLibraryMenuExpanded {
                libraryMenu
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let playbackError {
                Text(playbackError)
                    .font(.footnote)
                    .foregroundColor(theme.danger)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLibraryMenuExpanded)
    }

    private func landscapeBody(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 10) {
            topBar(transcription)
            workspacePicker

            HStack(alignment: .top, spacing: 12) {
                workspaceStage(transcription)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isLibraryMenuExpanded {
                    libraryMenu
                        .frame(maxWidth: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            if let playbackError {
                Text(playbackError)
                    .font(.footnote)
                    .foregroundColor(theme.danger)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLibraryMenuExpanded)
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
                Label("Import audio", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
            .accessibilityIdentifier("import-audio")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.pianoRollBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("library-menu")
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: $workspace) {
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

            Text("Draw notes · drag edges to resize · pinch or overview to zoom")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("piano-roll-caption")

            toolStrip(transcription, mode: .pianoRoll)
        }
    }

    private func scoreWorkspace(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 8) {
            scoreSection(transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            toolStrip(transcription, mode: .score)
            Text("Score builds from all notes on the roll. Edit timing in Piano roll.")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// Ableton-inspired transport: BPM + play/stop + draw.
    private func transportBar(_ transcription: TranscriptionResult) -> some View {
        let bpm = transcription.tempoBpm ?? NoteHelpers.defaultTempoBpm
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(String(format: "%.0f", bpm))
                    .font(.system(.title3, design: .monospaced))
                    .bold()
                    .foregroundColor(theme.textPrimary)
                    .accessibilityIdentifier("tempo-bpm")
                Text("BPM")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)

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
                        disabled: selectedNoteIndex == nil
                    ) {
                        if let index = selectedNoteIndex {
                            mergeNote(at: index)
                        }
                    }
                } else {
                    if let midiData = try? MIDIExporter.makeData(
                        from: transcription.noteEvents,
                        tempoBpm: transcription.tempoBpm
                    ) {
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

                    if let musicXMLData = try? MusicXMLExporter.makeData(
                        from: transcription.noteEvents,
                        tempoBpm: transcription.tempoBpm
                    ) {
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
    private func scoreSection(_ transcription: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let score = ScoreBuilder.build(
                from: transcription.noteEvents,
                tempoBpm: transcription.tempoBpm
            ) {
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
            transcription = loaded
            let seeded = PianoRollViewport.seeded(
                from: loaded.noteEvents,
                tempoBpm: loaded.tempoBpm
            )
            pianoRollViewport = seeded
            timeWindow = .from(contentSeconds: seeded.timelineSeconds, tempoBpm: loaded.tempoBpm)
            audioPlayer.clearSource(name: "\(fixture.rawValue) notes")
        } catch {
            playbackError = "Could not load fixture: \(fixture.rawValue)"
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
        do {
            try audioPlayer.playNotes(transcription.noteEvents, name: "Notes")
        } catch {
            playbackError = "Could not play notes"
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

    private func mergeNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        let note = trans.noteEvents[index]

        let mergeCandidateIndex = trans.noteEvents.enumerated().first { otherIndex, otherNote in
            otherIndex != index &&
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
