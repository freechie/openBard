import SwiftUI

struct PianoRollView: View {
    let notes: [NoteEvent]
    var viewport: PianoRollViewport
    @Binding var timeWindow: PianoRollTimeWindow
    var tempoBpm: Double? = nil
    var isDrawMode: Bool = false
    @Binding var selectedNoteIndex: Int?
    @Binding var isDraggingNote: Bool
    var theme: AbletonTheme
    var onEditNote: ((Int, NoteEvent) -> Void)?
    var onCreateNote: ((NoteEvent) -> Void)?

    @State private var dragSession: DragSession?
    @State private var dragTouchActive = false
    @State private var pinchBaseWindow: PianoRollTimeWindow?

    private enum DragKind {
        case move
        case resizeLeft
        case resizeRight
        case draw
        case panTimeline
    }

    private struct DragSession {
        var index: Int?
        var kind: DragKind
        var snapshot: PianoRollEdit.Snapshot?
        var scales: PianoRollEdit.Scales
        var didMove: Bool
        var wasAlreadySelected: Bool
        var drawPitch: Int?
        var drawOnset: Double?
        var panStartWindow: PianoRollTimeWindow?
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)
                drawBackground(context: context, size: size, metrics: metrics)
                drawPianoKeys(context: context, size: size, metrics: metrics)
                drawTimeRuler(context: context, size: size, metrics: metrics)
                drawGrid(context: context, size: size, metrics: metrics)
                drawNotes(context: context, size: size)
                drawVelocityLane(context: context, size: size, metrics: metrics)
            }
            .id(canvasIdentity)
            .background(theme.pianoRollBackground)
            .contentShape(Rectangle())
            .highPriorityGesture(interactionGesture(in: geometry.size))
            .gesture(magnifyGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Piano roll with \(notes.count) notes")
            .accessibilityIdentifier("piano-roll")
        }
    }

    private var canvasIdentity: String {
        notes.map { note in
            "\(note.pitchMidi)-\(note.onsetSeconds)-\(note.durationSeconds)-\(note.velocity)"
        }
        .joined(separator: "|")
        + "|sel:\(selectedNoteIndex.map(String.init) ?? "nil")"
        + "|vp:\(viewport.minPitch)-\(viewport.maxPitch)-\(viewport.timelineSeconds)"
        + "|tw:\(timeWindow.visibleStart)-\(timeWindow.visibleDuration)-\(timeWindow.contentSeconds)"
        + "|draw:\(isDrawMode)"
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBaseWindow == nil {
                    pinchBaseWindow = timeWindow
                }
                guard var base = pinchBaseWindow else { return }
                base.zoom(factor: value.magnification, anchorNormalized: 0.5)
                timeWindow = base
            }
            .onEnded { _ in
                pinchBaseWindow = nil
            }
    }

    private func drawBackground(context: GraphicsContext, size: CGSize, metrics: PianoRollLayout.Metrics) {
        let noteArea = CGRect(
            x: metrics.labelGutter,
            y: metrics.contentMinY,
            width: metrics.drawableWidth,
            height: metrics.noteAreaHeight
        )
        context.fill(Path(noteArea), with: .color(theme.pianoRollBackground))

        let velocityArea = CGRect(
            x: metrics.labelGutter,
            y: metrics.velocityMinY,
            width: metrics.drawableWidth,
            height: metrics.velocityHeight
        )
        context.fill(Path(velocityArea), with: .color(theme.surface))
    }

    private func drawPianoKeys(context: GraphicsContext, size: CGSize, metrics: PianoRollLayout.Metrics) {
        for pitch in viewport.minPitch...viewport.maxPitch {
            let row = viewport.maxPitch - pitch
            let y = metrics.contentMinY + CGFloat(row) * metrics.rowHeight
            let rect = CGRect(x: 0, y: y, width: metrics.labelGutter, height: metrics.rowHeight)
            let isBlack = PianoRollLayout.isBlackKey(midi: pitch)
            context.fill(
                Path(rect),
                with: .color(isBlack ? theme.border : theme.surfaceElevated)
            )
            context.stroke(Path(rect), with: .color(theme.gridLine), lineWidth: 0.5)

            if pitch % 12 == 0 || selectedNoteIndex.map({ notes.indices.contains($0) && notes[$0].pitchMidi == pitch }) == true {
                let name = PianoRollLayout.pitchName(midi: pitch)
                context.draw(
                    Text(name)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textSecondary),
                    at: CGPoint(x: metrics.labelGutter / 2, y: y + metrics.rowHeight / 2),
                    anchor: .center
                )
            }
        }
    }

    private func drawTimeRuler(context: GraphicsContext, size: CGSize, metrics: PianoRollLayout.Metrics) {
        let ruler = CGRect(x: 0, y: 0, width: size.width, height: metrics.rulerHeight)
        context.fill(Path(ruler), with: .color(theme.surfaceElevated))
        context.stroke(
            Path(CGRect(x: 0, y: metrics.rulerHeight - 0.5, width: size.width, height: 0.5)),
            with: .color(theme.border),
            lineWidth: 0.5
        )

        let tempo = tempoBpm ?? NoteHelpers.defaultTempoBpm
        let beatSeconds = 60.0 / tempo
        let startBeat = Int(floor(timeWindow.visibleStart / beatSeconds))
        let endBeat = Int(ceil(timeWindow.visibleEnd / beatSeconds))
        for beat in startBeat...endBeat {
            let t = Double(beat) * beatSeconds
            guard t >= timeWindow.visibleStart - 0.0001, t <= timeWindow.visibleEnd + 0.0001 else { continue }
            let x = metrics.labelGutter
                + CGFloat((t - timeWindow.visibleStart) / timeWindow.visibleDuration) * metrics.drawableWidth
            let isBar = beat % 4 == 0
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: isBar ? 2 : metrics.rulerHeight * 0.45))
                    path.addLine(to: CGPoint(x: x, y: metrics.rulerHeight))
                },
                with: .color(theme.textSecondary.opacity(isBar ? 0.9 : 0.5)),
                lineWidth: isBar ? 1 : 0.5
            )
            if isBar {
                let barNumber = beat / 4 + 1
                context.draw(
                    Text("\(barNumber)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.textSecondary),
                    at: CGPoint(x: x + 4, y: 4),
                    anchor: .topLeading
                )
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, metrics: PianoRollLayout.Metrics) {
        for i in 0...viewport.pitchSpan {
            let y = metrics.contentMinY + CGFloat(i) * metrics.rowHeight
            let path = Path { p in
                p.move(to: CGPoint(x: metrics.labelGutter, y: y))
                p.addLine(to: CGPoint(x: size.width - metrics.trailingInset, y: y))
            }
            context.stroke(path, with: .color(theme.gridLine), lineWidth: 0.5)
        }

        let tempo = tempoBpm ?? NoteHelpers.defaultTempoBpm
        let stepSeconds = (60.0 / tempo) / 4.0
        let startStep = Int(floor(timeWindow.visibleStart / stepSeconds))
        let endStep = Int(ceil(timeWindow.visibleEnd / stepSeconds))
        for step in startStep...endStep {
            let t = Double(step) * stepSeconds
            guard t >= timeWindow.visibleStart - 0.0001, t <= timeWindow.visibleEnd + 0.0001 else { continue }
            let x = metrics.labelGutter
                + CGFloat((t - timeWindow.visibleStart) / timeWindow.visibleDuration) * metrics.drawableWidth
            let isBeat = step % 4 == 0
            let path = Path { p in
                p.move(to: CGPoint(x: x, y: metrics.contentMinY))
                p.addLine(to: CGPoint(x: x, y: metrics.velocityMinY))
            }
            context.stroke(
                path,
                with: .color(theme.gridLine.opacity(isBeat ? 1 : 0.45)),
                lineWidth: isBeat ? 0.8 : 0.4
            )
        }
    }

    private func drawNotes(context: GraphicsContext, size: CGSize) {
        let frames = PianoRollLayout.frames(
            notes: notes,
            viewport: viewport,
            timeWindow: timeWindow,
            in: size
        )
        for (index, frame) in frames.enumerated() {
            guard frame.width > 0.5 else { continue }
            let note = notes[index]
            let path = Path(roundedRect: frame, cornerRadius: 2)
            let opacity = min(max(0.45, note.confidence * 0.9), 0.98)
            let color = selectedNoteIndex == index ? theme.noteSelected : theme.accent

            context.fill(path, with: .color(color.opacity(opacity)))

            if selectedNoteIndex == index {
                context.stroke(path, with: .color(theme.textPrimary.opacity(0.85)), lineWidth: 1.5)
                let handleHeight = max(frame.height - 4, 2)
                let left = CGRect(x: frame.minX + 1, y: frame.minY + 2, width: 3, height: handleHeight)
                let right = CGRect(x: frame.maxX - 4, y: frame.minY + 2, width: 3, height: handleHeight)
                context.fill(Path(roundedRect: left, cornerRadius: 1), with: .color(theme.textPrimary))
                context.fill(Path(roundedRect: right, cornerRadius: 1), with: .color(theme.textPrimary))
            }
        }
    }

    private func drawVelocityLane(context: GraphicsContext, size: CGSize, metrics: PianoRollLayout.Metrics) {
        context.stroke(
            Path(CGRect(x: 0, y: metrics.velocityMinY, width: size.width, height: 0.5)),
            with: .color(theme.border),
            lineWidth: 0.5
        )
        context.draw(
            Text("Vel")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textSecondary),
            at: CGPoint(x: metrics.labelGutter / 2, y: metrics.velocityMinY + metrics.velocityHeight / 2),
            anchor: .center
        )

        let frames = PianoRollLayout.frames(
            notes: notes,
            viewport: viewport,
            timeWindow: timeWindow,
            in: size
        )
        for (index, frame) in frames.enumerated() {
            guard frame.width > 0.5 else { continue }
            let note = notes[index]
            let height = max(4, CGFloat(note.velocity) * (metrics.velocityHeight - 8))
            let pinWidth = max(3, min(frame.width, 8))
            let x = frame.minX + (frame.width - pinWidth) / 2
            let rect = CGRect(
                x: x,
                y: metrics.velocityMinY + metrics.velocityHeight - 4 - height,
                width: pinWidth,
                height: height
            )
            let color = selectedNoteIndex == index ? theme.noteSelected : theme.accent
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.9)))
        }
    }

    private func interactionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragTouchActive {
                    dragTouchActive = true
                    beginDrag(at: value.startLocation, in: size)
                }
                guard var session = dragSession else { return }

                let distance = hypot(value.translation.width, value.translation.height)
                if !session.didMove {
                    guard distance >= 4 else { return }
                    session.didMove = true
                    dragSession = session
                    if session.kind == .panTimeline {
                        isDraggingNote = false
                    } else {
                        isDraggingNote = true
                        if let index = session.index {
                            selectedNoteIndex = index
                        }
                    }
                }

                switch session.kind {
                case .move:
                    guard let index = session.index,
                          let snapshot = session.snapshot,
                          notes.indices.contains(index) else { return }
                    if let edited = PianoRollEdit.movedNote(
                        from: snapshot,
                        translation: value.translation,
                        scales: session.scales,
                        base: notes[index]
                    ) {
                        onEditNote?(index, edited)
                    }
                case .resizeRight:
                    guard let index = session.index,
                          let snapshot = session.snapshot,
                          notes.indices.contains(index) else { return }
                    if let edited = PianoRollEdit.resizedNote(
                        from: snapshot,
                        translation: value.translation,
                        scales: session.scales,
                        base: notes[index]
                    ) {
                        onEditNote?(index, edited)
                    }
                case .resizeLeft:
                    guard let index = session.index,
                          let snapshot = session.snapshot,
                          notes.indices.contains(index) else { return }
                    if let edited = PianoRollEdit.resizedNoteFromLeft(
                        from: snapshot,
                        translation: value.translation,
                        scales: session.scales,
                        base: notes[index]
                    ) {
                        onEditNote?(index, edited)
                    }
                case .draw:
                    break
                case .panTimeline:
                    guard var start = session.panStartWindow else { return }
                    let delta = -Double(value.translation.width) * session.scales.secondsPerPoint
                    start.pan(deltaSeconds: delta)
                    timeWindow = start
                }
            }
            .onEnded { value in
                let session = dragSession
                defer {
                    dragSession = nil
                    dragTouchActive = false
                    isDraggingNote = false
                }

                if session?.kind == .draw,
                   let pitch = session?.drawPitch,
                   let onset = session?.drawOnset {
                    let durationDelta = Double(value.translation.width) * (session?.scales.secondsPerPoint ?? 0)
                    let duration = max(
                        NoteHelpers.defaultDurationSeconds(tempoBpm: tempoBpm),
                        durationDelta
                    )
                    let note = PianoRollEdit.makeDrawnNote(pitch: pitch, onset: onset, duration: duration)
                    onCreateNote?(note)
                    return
                }

                guard session?.didMove != true else { return }

                if let hit = PianoRollLayout.hitTest(
                    notes: notes,
                    viewport: viewport,
                    timeWindow: timeWindow,
                    at: value.startLocation,
                    in: size
                ) {
                    if session?.index == hit, session?.wasAlreadySelected == true {
                        selectedNoteIndex = nil
                    } else {
                        selectedNoteIndex = hit
                    }
                } else if session?.kind != .panTimeline {
                    selectedNoteIndex = nil
                }
            }
    }

    private func beginDrag(at point: CGPoint, in size: CGSize) {
        let scales = PianoRollEdit.Scales.from(viewport: viewport, timeWindow: timeWindow, size: size)

        if let index = PianoRollLayout.hitTest(
            notes: notes,
            viewport: viewport,
            timeWindow: timeWindow,
            at: point,
            in: size
        ), notes.indices.contains(index) {
            let note = notes[index]
            let wasAlreadySelected = selectedNoteIndex == index
            selectedNoteIndex = index
            let frames = PianoRollLayout.frames(
                notes: notes,
                viewport: viewport,
                timeWindow: timeWindow,
                in: size
            )
            let frame = frames[index]
            let edge = PianoRollEdit.edgeHit(frame: frame, point: point)
            let kind: DragKind
            switch edge {
            case .left: kind = .resizeLeft
            case .right: kind = .resizeRight
            case .body: kind = .move
            }
            dragSession = DragSession(
                index: index,
                kind: kind,
                snapshot: PianoRollEdit.snapshot(of: note),
                scales: scales,
                didMove: false,
                wasAlreadySelected: wasAlreadySelected,
                drawPitch: nil,
                drawOnset: nil,
                panStartWindow: nil
            )
            return
        }

        if isDrawMode,
           let mapped = PianoRollEdit.pitchAndOnset(
            at: point,
            viewport: viewport,
            timeWindow: timeWindow,
            size: size
           ) {
            dragSession = DragSession(
                index: nil,
                kind: .draw,
                snapshot: nil,
                scales: scales,
                didMove: false,
                wasAlreadySelected: false,
                drawPitch: mapped.pitch,
                drawOnset: mapped.onset,
                panStartWindow: nil
            )
            return
        }

        // Empty drag pans the timeline (Ableton hand/scroll feel when not drawing).
        dragSession = DragSession(
            index: nil,
            kind: .panTimeline,
            snapshot: nil,
            scales: scales,
            didMove: false,
            wasAlreadySelected: false,
            drawPitch: nil,
            drawOnset: nil,
            panStartWindow: timeWindow
        )
    }
}

enum PianoRollLayout {
    static let minimumRowHeight: CGFloat = 14
    static let labelGutter: CGFloat = 52
    static let trailingInset: CGFloat = 8
    static let verticalInset: CGFloat = 4
    static let rulerHeight: CGFloat = 20
    static let velocityHeight: CGFloat = 44

    struct Metrics {
        var labelGutter: CGFloat
        var trailingInset: CGFloat
        var rulerHeight: CGFloat
        var contentMinY: CGFloat
        var noteAreaHeight: CGFloat
        var rowHeight: CGFloat
        var drawableWidth: CGFloat
        var velocityMinY: CGFloat
        var velocityHeight: CGFloat
    }

    static func pitchName(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
    }

    static func isBlackKey(midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12)
    }

    static func recommendedHeight(for viewport: PianoRollViewport, floor: CGFloat = 200) -> CGFloat {
        let rows = CGFloat(viewport.pitchSpan + 1)
        return max(floor, rows * minimumRowHeight + rulerHeight + velocityHeight + verticalInset * 2)
    }

    static func metrics(viewport: PianoRollViewport, in size: CGSize) -> Metrics {
        let rows = CGFloat(viewport.pitchSpan + 1)
        let contentMinY = rulerHeight + verticalInset
        let velocityMinY = size.height - velocityHeight
        let noteAreaHeight = max(velocityMinY - contentMinY - verticalInset, rows)
        return Metrics(
            labelGutter: labelGutter,
            trailingInset: trailingInset,
            rulerHeight: rulerHeight,
            contentMinY: contentMinY,
            noteAreaHeight: noteAreaHeight,
            rowHeight: noteAreaHeight / rows,
            drawableWidth: max(size.width - labelGutter - trailingInset, 1),
            velocityMinY: velocityMinY,
            velocityHeight: velocityHeight
        )
    }

    static func metrics(notes: [NoteEvent], in size: CGSize) -> Metrics {
        metrics(viewport: PianoRollViewport.seeded(from: notes, tempoBpm: 120), in: size)
    }

    static func timelineDuration(notes: [NoteEvent]) -> Double {
        PianoRollViewport.seeded(from: notes, tempoBpm: 120).timelineSeconds
    }

    static func frames(
        notes: [NoteEvent],
        viewport: PianoRollViewport,
        timeWindow: PianoRollTimeWindow,
        in size: CGSize
    ) -> [CGRect] {
        guard !notes.isEmpty else { return [] }

        let duration = max(timeWindow.visibleDuration, 0.001)
        let metrics = metrics(viewport: viewport, in: size)
        let rowInset = min(4, max(metrics.rowHeight * 0.15, 0))

        return notes.map { note in
            let relStart = note.onsetSeconds - timeWindow.visibleStart
            let relEnd = relStart + note.durationSeconds
            // Clip notes outside the visible window to zero-width (still keep index alignment).
            if relEnd < 0 || relStart > duration {
                return .zero
            }
            let clippedStart = max(0, relStart)
            let clippedEnd = min(duration, relEnd)
            let x = metrics.labelGutter + CGFloat(clippedStart / duration) * metrics.drawableWidth
            let rawWidth = CGFloat((clippedEnd - clippedStart) / duration) * metrics.drawableWidth
            let width = min(max(rawWidth, 4), metrics.drawableWidth)
            let y = metrics.contentMinY
                + CGFloat(viewport.maxPitch - note.pitchMidi) * metrics.rowHeight
                + rowInset / 2
            let height = max(metrics.rowHeight - rowInset, 2)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    static func frames(notes: [NoteEvent], viewport: PianoRollViewport, in size: CGSize) -> [CGRect] {
        frames(
            notes: notes,
            viewport: viewport,
            timeWindow: PianoRollTimeWindow(
                contentSeconds: viewport.timelineSeconds,
                visibleStart: 0,
                visibleDuration: viewport.timelineSeconds
            ),
            in: size
        )
    }

    static func frames(notes: [NoteEvent], in size: CGSize) -> [CGRect] {
        frames(notes: notes, viewport: PianoRollViewport.seeded(from: notes, tempoBpm: 120), in: size)
    }

    static func hitTest(
        notes: [NoteEvent],
        viewport: PianoRollViewport,
        timeWindow: PianoRollTimeWindow,
        at point: CGPoint,
        in size: CGSize
    ) -> Int? {
        let frames = frames(notes: notes, viewport: viewport, timeWindow: timeWindow, in: size)
        for (index, frame) in frames.enumerated().reversed() {
            if frame.width > 0.5, frame.contains(point) {
                return index
            }
        }
        return nil
    }

    static func hitTest(notes: [NoteEvent], viewport: PianoRollViewport, at point: CGPoint, in size: CGSize) -> Int? {
        hitTest(
            notes: notes,
            viewport: viewport,
            timeWindow: PianoRollTimeWindow(
                contentSeconds: viewport.timelineSeconds,
                visibleStart: 0,
                visibleDuration: viewport.timelineSeconds
            ),
            at: point,
            in: size
        )
    }

    static func hitTest(notes: [NoteEvent], at point: CGPoint, in size: CGSize) -> Int? {
        hitTest(
            notes: notes,
            viewport: PianoRollViewport.seeded(from: notes, tempoBpm: 120),
            at: point,
            in: size
        )
    }
}
