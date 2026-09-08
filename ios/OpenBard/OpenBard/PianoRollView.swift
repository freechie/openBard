import SwiftUI

struct PianoRollView: View {
    let notes: [NoteEvent]
    @Binding var selectedNoteIndex: Int?
    var editMode: ContentView.EditMode = .inactive

    var body: some View {
        Canvas { context, size in
            let frames = PianoRollLayout.frames(notes: notes, in: size)
            for (index, frame) in frames.enumerated() {
                let note = notes[index]
                let path = Path(roundedRect: frame, cornerRadius: 3)
                let opacity = min(max(0.3, note.confidence * 0.85), 0.95)
                
                var color = Color.accentColor
                if note.isLocked {
                    color = .green
                } else if selectedNoteIndex == index {
                    color = .orange
                }
                
                context.fill(path, with: .color(color.opacity(opacity)))
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            pitchLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piano roll with \(notes.count) notes")
        .accessibilityIdentifier("piano-roll")
    }

    @ViewBuilder
    private var pitchLabels: some View {
        if let minPitch = notes.map(\.pitchMidi).min(),
           let maxPitch = notes.map(\.pitchMidi).max() {
            let span = max(CGFloat(maxPitch - minPitch), 1)
            GeometryReader { geometry in
                ForEach(notes) { note in
                    let row = CGFloat(maxPitch - note.pitchMidi) / span
                    Text(PianoRollLayout.pitchName(midi: note.pitchMidi))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(
                            x: 16,
                            y: row * geometry.size.height + geometry.size.height / (span * 2)
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

enum PianoRollLayout {
    static func pitchName(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
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

        return notes.map { note in
            let x = labelGutter + CGFloat(note.onsetSeconds / duration) * (size.width - labelGutter)
            let width = max(CGFloat(note.durationSeconds / duration) * (size.width - labelGutter), 4)
            let y = CGFloat(maxPitch - note.pitchMidi) * rowHeight + 4
            return CGRect(x: x, y: y, width: width - 4, height: rowHeight - 8)
        }
    }
}
