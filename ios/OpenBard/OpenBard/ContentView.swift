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
    @State private var workspace: Workspace = .pianoRoll
    @State private var isLibraryMenuExpanded = false

    init() {
        _transcription = State(initialValue: try? TranscriptionLoader.loadDemo())
    }
    
    private var theme: AbletonTheme {
        AbletonTheme.current(for: colorScheme)
    }

    enum Workspace: String, CaseIterable, Identifiable {
        case pianoRoll = "Piano roll"
        case score = "Score"

        var id: String { rawValue }
    }
    
    enum EditMode {
        case inactive
        case nudge
        case delete
        case split
        case merge
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
                Text("Failed to load demo transcription")
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
                editMode = .inactive
                selectedNoteIndex = nil
                loadFixture(newFixture)
            }

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
            editMode = .inactive
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
            pianoViewport(transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            toolStrip(transcription, mode: .pianoRoll)
        }
    }

    private func scoreWorkspace(_ transcription: TranscriptionResult) -> some View {
        VStack(spacing: 8) {
            scoreSection(transcription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            toolStrip(transcription, mode: .score)
            Text("Lock notes here to build the staff. Edit pitches and timing in Piano roll.")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func pianoViewport(_ transcription: TranscriptionResult) -> some View {
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
        let selectedLocked = selectedNoteIndex.map { transcription.noteEvents[$0].isLocked } ?? false
        let allLocked = !transcription.noteEvents.isEmpty && transcription.noteEvents.allSatisfy(\.isLocked)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                iconButton(
                    systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill",
                    tint: theme.accent,
                    foreground: theme.accent,
                    label: audioPlayer.isPlaying ? "Pause" : "Play",
                    id: "play-demo-audio"
                ) {
                    togglePlayback()
                }

                if mode == .pianoRoll {
                    iconButton(
                        systemName: editMode == .nudge ? "hand.draw.fill" : "hand.draw",
                        tint: editMode == .nudge ? theme.accent : theme.border,
                        foreground: editMode == .nudge ? theme.accent : theme.textSecondary,
                        label: "Nudge",
                        id: "nudge-button"
                    ) {
                        editMode = editMode == .nudge ? .inactive : .nudge
                    }

                    iconButton(
                        systemName: "trash",
                        tint: theme.danger,
                        foreground: theme.danger,
                        label: "Delete",
                        id: "delete-button",
                        disabled: selectedNoteIndex == nil || selectedLocked
                    ) {
                        if let index = selectedNoteIndex {
                            deleteNote(at: index)
                        }
                    }

                    iconButton(
                        systemName: selectedLocked ? "lock.open.fill" : "lock.fill",
                        tint: theme.success,
                        foreground: theme.success,
                        label: selectedLocked ? "Unlock" : "Lock",
                        id: "lock-button",
                        disabled: selectedNoteIndex == nil
                    ) {
                        toggleSelectedNoteLock()
                    }

                    iconButton(
                        systemName: "scissors",
                        tint: theme.accentDim,
                        foreground: theme.accent.opacity(0.85),
                        label: "Split",
                        id: "split-button",
                        disabled: selectedNoteIndex == nil || selectedLocked
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
                        disabled: selectedNoteIndex == nil || selectedLocked
                    ) {
                        if let index = selectedNoteIndex {
                            mergeNote(at: index)
                        }
                    }
                } else {
                    iconButton(
                        systemName: allLocked ? "lock.open.fill" : "lock.fill",
                        tint: theme.success,
                        foreground: theme.success,
                        label: allLocked ? "Unlock all" : "Lock all",
                        id: "lock-all-button",
                        disabled: transcription.noteEvents.isEmpty,
                        prominent: true
                    ) {
                        if allLocked {
                            unlockAllNotes()
                        } else {
                            lockAllNotes()
                        }
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
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let labelView = Image(systemName: systemName)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundColor(foreground)

        if prominent {
            Button(action: action) { labelView }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(disabled)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        } else {
            Button(action: action) { labelView }
                .buttonStyle(.bordered)
                .tint(tint)
                .disabled(disabled)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    @ViewBuilder
    private func scoreSection(_ transcription: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let score = ScoreBuilder.build(from: transcription.noteEvents) {
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
                    Text("Lock notes to build a score")
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
    
    private func toggleSelectedNoteLock() {
        guard let index = selectedNoteIndex else { return }
        guard var trans = transcription, trans.noteEvents.indices.contains(index) else { return }
        trans.noteEvents[index].isLocked.toggle()
        transcription = trans
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
    }

    private func unlockNote(at index: Int) {
        guard var trans = transcription else { return }
        guard index < trans.noteEvents.count else { return }
        trans.noteEvents[index].isLocked = false
        transcription = trans
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

    private func unlockAllNotes() {
        guard var trans = transcription else { return }
        for index in trans.noteEvents.indices {
            trans.noteEvents[index].isLocked = false
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
