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
                }
                
                drawGrid(context: context, size: size)
            }
            .background(theme.pianoRollBackground)
            .overlay {
                pitchLabels(in: geometry.size)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if editMode == .nudge, let index = selectedNoteIndex {
                            onNudge?(index, value.translation)
                        }
                    }
                    .onEnded { value in
                        if editMode == .nudge {
                            return
                        }
                        if value.translation.width < 5 && value.translation.height < 5 {
                            selectedNoteIndex = hitTestNote(at: value.location, in: geometry.size)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Piano roll with \(notes.count) notes")
            .accessibilityIdentifier("piano-roll")
        }
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        guard !notes.isEmpty else { return }
        
        let pitches = notes.map(\.pitchMidi)
        guard let minPitch = pitches.min(), let maxPitch = pitches.max() else { return }
        
        let pitchSpan = max(maxPitch - minPitch, 1)
        let rowHeight = size.height / CGFloat(pitchSpan + 1)
        let labelGutter: CGFloat = 36
        
        for i in 0...pitchSpan {
            let y = CGFloat(i) * rowHeight
            let path = Path { p in
                p.move(to: CGPoint(x: labelGutter, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(theme.gridLine), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func pitchLabels(in size: CGSize) -> some View {
        if let minPitch = notes.map(\.pitchMidi).min(),
           let maxPitch = notes.map(\.pitchMidi).max() {
            let pitchSpan = max(maxPitch - minPitch, 1)
            let rowHeight = size.height / CGFloat(pitchSpan + 1)
            
            let uniquePitches = Set(notes.map(\.pitchMidi)).sorted()
            
            ZStack {
                ForEach(uniquePitches, id: \.self) { pitch in
                    let y = CGFloat(maxPitch - pitch) * rowHeight + rowHeight / 2
                    Text(PianoRollLayout.pitchName(midi: pitch))
                        .font(.caption2)
                        .foregroundColor(theme.textSecondary)
                        .position(
                            x: 16,
                            y: y
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
    
    private func hitTestNote(at location: CGPoint, in size: CGSize) -> Int? {
        let frames = PianoRollLayout.frames(notes: notes, in: size)
        for (index, frame) in frames.enumerated() {
            if frame.contains(location) {
                return index
            }
        }
        return nil
    }
}

enum PianoRollLayout {
    static let minimumRowHeight: CGFloat = 14

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
        return max(floor, rows * minimumRowHeight)
    }

    static func frames(notes: [NoteEvent], in size: CGSize) -> [CGRect] {
        guard !notes.isEmpty else { return [] }

        let pitches = notes.map(\.pitchMidi)
        guard let minPitch = pitches.min(), let maxPitch = pitches.max() else {
            return []
        }

        let end = notes.map { $0.onsetSeconds + $0.durationSeconds }.max() ?? 1
        let duration = max(end, 0.001)
        let pitchSpan = max(maxPitch - minPitch, 1)
        let rowHeight = size.height / CGFloat(pitchSpan + 1)
        let labelGutter: CGFloat = 36
        let verticalInset = min(4, max(rowHeight * 0.15, 0))

        return notes.map { note in
            let x = labelGutter + CGFloat(note.onsetSeconds / duration) * (size.width - labelGutter)
            let rawWidth = CGFloat(note.durationSeconds / duration) * (size.width - labelGutter)
            let width = max(rawWidth, 4)
            let y = CGFloat(maxPitch - note.pitchMidi) * rowHeight + verticalInset / 2
            let height = max(rowHeight - verticalInset, 2)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
}
