import SwiftUI

struct PianoRollView: View {
    let notes: [NoteEvent]
    @Binding var selectedNoteIndex: Int?
    var editMode: ContentView.EditMode = .inactive
    var theme: AbletonTheme
    var onNudge: ((Int, CGSize) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let frames = PianoRollLayout.frames(notes: notes, in: size)
                for (index, frame) in frames.enumerated() {
                    let note = notes[index]
                    let path = Path(roundedRect: frame, cornerRadius: 3)
                    let opacity = min(max(0.3, note.confidence * 0.85), 0.95)

                    var color = theme.noteFill
                    if note.isLocked {
                        color = theme.noteLocked
                    } else if selectedNoteIndex == index {
                        color = theme.noteSelected
                    }

                    context.fill(path, with: .color(color.opacity(opacity)))

                    if note.isLocked, selectedNoteIndex == index {
                        context.stroke(
                            path,
                            with: .color(theme.noteSelected),
                            lineWidth: 2
                        )
                    }
                }

                drawGrid(context: context, size: size)
            }
            .id(canvasIdentity)
            .background(theme.pianoRollBackground)
            .overlay {
                pitchLabels(in: geometry.size)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(interactionGesture(in: geometry.size))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Piano roll with \(notes.count) notes")
            .accessibilityIdentifier("piano-roll")
        }
    }

    private var canvasIdentity: String {
        notes.map { note in
            "\(note.pitchMidi)-\(note.onsetSeconds)-\(note.durationSeconds)-\(note.isLocked)"
        }
        .joined(separator: "|")
        + "|sel:\(selectedNoteIndex.map(String.init) ?? "nil")"
    }

    private func interactionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard editMode == .nudge else { return }
                let index = selectedNoteIndex
                    ?? PianoRollLayout.hitTest(notes: notes, at: value.startLocation, in: size)
                guard let index else { return }
                if selectedNoteIndex != index {
                    selectedNoteIndex = index
                }
                onNudge?(index, value.translation)
            }
            .onEnded { value in
                guard editMode != .nudge else { return }
                let isTap = abs(value.translation.width) < 8 && abs(value.translation.height) < 8
                guard isTap else { return }

                if let hit = PianoRollLayout.hitTest(notes: notes, at: value.startLocation, in: size) {
                    selectedNoteIndex = selectedNoteIndex == hit ? nil : hit
                } else {
                    selectedNoteIndex = nil
                }
            }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        guard !notes.isEmpty else { return }

        let pitches = notes.map(\.pitchMidi)
        guard let minPitch = pitches.min(), let maxPitch = pitches.max() else { return }

        let metrics = PianoRollLayout.metrics(notes: notes, in: size)
        for i in 0...max(maxPitch - minPitch, 1) {
            let y = metrics.contentMinY + CGFloat(i) * metrics.rowHeight
            let path = Path { p in
                p.move(to: CGPoint(x: metrics.labelGutter, y: y))
                p.addLine(to: CGPoint(x: size.width - metrics.trailingInset, y: y))
            }
            context.stroke(path, with: .color(theme.gridLine), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func pitchLabels(in size: CGSize) -> some View {
        if notes.map(\.pitchMidi).min() != nil,
           let maxPitch = notes.map(\.pitchMidi).max() {
            let metrics = PianoRollLayout.metrics(notes: notes, in: size)
            let uniquePitches = Set(notes.map(\.pitchMidi)).sorted()

            ZStack {
                ForEach(uniquePitches, id: \.self) { pitch in
                    let y = metrics.contentMinY
                        + CGFloat(maxPitch - pitch) * metrics.rowHeight
                        + metrics.rowHeight / 2
                    Text(PianoRollLayout.pitchName(midi: pitch))
                        .font(.caption2)
                        .foregroundColor(theme.textSecondary)
                        .position(x: metrics.labelGutter / 2, y: y)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

enum PianoRollLayout {
    static let minimumRowHeight: CGFloat = 14
    static let labelGutter: CGFloat = 40
    static let trailingInset: CGFloat = 8
    static let verticalInset: CGFloat = 10

    struct Metrics {
        var labelGutter: CGFloat
        var trailingInset: CGFloat
        var contentMinY: CGFloat
        var rowHeight: CGFloat
        var drawableWidth: CGFloat
    }

    static func pitchName(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
    }

    static func recommendedHeight(for notes: [NoteEvent], floor: CGFloat = 200) -> CGFloat {
        guard let minPitch = notes.map(\.pitchMidi).min(),
              let maxPitch = notes.map(\.pitchMidi).max() else {
            return floor
        }
        let rows = CGFloat(max(maxPitch - minPitch, 1) + 1)
        return max(floor, rows * minimumRowHeight + verticalInset * 2)
    }

    static func metrics(notes: [NoteEvent], in size: CGSize) -> Metrics {
        let pitches = notes.map(\.pitchMidi)
        let minPitch = pitches.min() ?? 60
        let maxPitch = pitches.max() ?? 60
        let pitchSpan = max(maxPitch - minPitch, 1)
        let rows = CGFloat(pitchSpan + 1)
        let availableHeight = max(size.height - verticalInset * 2, rows)
        return Metrics(
            labelGutter: labelGutter,
            trailingInset: trailingInset,
            contentMinY: verticalInset,
            rowHeight: availableHeight / rows,
            drawableWidth: max(size.width - labelGutter - trailingInset, 1)
        )
    }

    static func frames(notes: [NoteEvent], in size: CGSize) -> [CGRect] {
        guard !notes.isEmpty else { return [] }

        let pitches = notes.map(\.pitchMidi)
        guard let maxPitch = pitches.max() else {
            return []
        }

        let end = notes.map { $0.onsetSeconds + $0.durationSeconds }.max() ?? 1
        let duration = max(end, 0.001)
        let metrics = metrics(notes: notes, in: size)
        let rowInset = min(4, max(metrics.rowHeight * 0.15, 0))

        return notes.map { note in
            let x = metrics.labelGutter
                + CGFloat(note.onsetSeconds / duration) * metrics.drawableWidth
            let rawWidth = CGFloat(note.durationSeconds / duration) * metrics.drawableWidth
            let width = min(max(rawWidth, 4), metrics.drawableWidth)
            let y = metrics.contentMinY
                + CGFloat(maxPitch - note.pitchMidi) * metrics.rowHeight
                + rowInset / 2
            let height = max(metrics.rowHeight - rowInset, 2)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Returns the note under `point`, preferring later (visually topmost) overlaps.
    static func hitTest(notes: [NoteEvent], at point: CGPoint, in size: CGSize) -> Int? {
        let frames = frames(notes: notes, in: size)
        for (index, frame) in frames.enumerated().reversed() {
            if frame.contains(point) {
                return index
            }
        }
        return nil
    }
}
