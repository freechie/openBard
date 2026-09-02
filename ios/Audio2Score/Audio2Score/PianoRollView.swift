import SwiftUI

struct PianoRollView: View {
    let notes: [NoteEvent]

    var body: some View {
        Canvas { context, size in
            let frames = PianoRollLayout.frames(notes: notes, in: size)
            for frame in frames {
                let path = Path(roundedRect: frame, cornerRadius: 3)
                context.fill(path, with: .color(.accentColor.opacity(0.85)))
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            pitchLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piano roll, C major chord, three overlapping notes")
        .accessibilityIdentifier("piano-roll")
    }

    @ViewBuilder
    private var pitchLabels: some View {
        let pitches = PianoRollLayout.pitchRange(notes: notes)
        if let minPitch = pitches.min, let maxPitch = pitches.max {
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
    struct PitchRange {
        var min: Int?
        var max: Int?
    }

    static func pitchRange(notes: [NoteEvent]) -> PitchRange {
        PitchRange(
            min: notes.map(\.pitchMidi).min(),
            max: notes.map(\.pitchMidi).max()
        )
    }

    static func pitchName(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[((midi % 12) + 12) % 12]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
    }

    static func frames(notes: [NoteEvent], in size: CGSize) -> [CGRect] {
        guard let minPitch = notes.map(\.pitchMidi).min(),
              let maxPitch = notes.map(\.pitchMidi).max()
        else {
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
