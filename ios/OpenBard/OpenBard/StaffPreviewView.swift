import SwiftUI

enum StaffLayout {
    static func lineSpacing(in size: CGSize) -> CGFloat {
        max(8, size.height / 8)
    }

    static func padding(in size: CGSize) -> CGFloat {
        max(12, min(size.width, size.height) * 0.04)
    }

    static func summary(for score: Score) -> String {
        let noteCount = score.measures.reduce(0) { total, measure in
            total + measure.items.reduce(0) { count, item in
                switch item {
                case .note:
                    return count + 1
                case .rest:
                    return count
                }
            }
        }
        let clefName: String
        switch score.clef {
        case .treble:
            clefName = "treble"
        case .bass:
            clefName = "bass"
        case .unknown:
            clefName = "treble"
        }
        return "Tempo: \(Int(score.tempoBpm.rounded())) BPM, \(clefName), \(noteCount) notes"
    }
}

struct StaffPreviewView: View {
    let score: Score
    var theme: AbletonTheme

    var body: some View {
        Canvas { context, size in
            drawStaff(context: context, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StaffLayout.summary(for: score))
        .accessibilityIdentifier("staff-preview")
    }

    private func drawStaff(context: GraphicsContext, size: CGSize) {
        let padding = StaffLayout.padding(in: size)
        let lineSpacing = StaffLayout.lineSpacing(in: size)
        let staffHeight = lineSpacing * 4
        let originY = (size.height - staffHeight) / 2
        let staffWidth = max(size.width - padding * 2, 1)
        let noteHeadWidth = max(8, lineSpacing)
        let noteHeadHeight = max(6, lineSpacing * 0.8)

        for i in 0..<5 {
            var path = Path()
            let y = originY + CGFloat(i) * lineSpacing
            path.move(to: CGPoint(x: padding, y: y))
            path.addLine(to: CGPoint(x: padding + staffWidth, y: y))
            context.stroke(path, with: .color(theme.gridLine), lineWidth: 1)
        }

        let measureCount = max(score.measures.count, 1)
        let measureWidth = staffWidth / CGFloat(measureCount)
        for index in 0...measureCount {
            var bar = Path()
            let x = padding + CGFloat(index) * measureWidth
            bar.move(to: CGPoint(x: x, y: originY))
            bar.addLine(to: CGPoint(x: x, y: originY + staffHeight))
            context.stroke(bar, with: .color(theme.border), lineWidth: index == 0 || index == measureCount ? 1.5 : 1)
        }

        let bottomLineY = originY + staffHeight
        for (measureIndex, measure) in score.measures.enumerated() {
            let measureX = padding + CGFloat(measureIndex) * measureWidth
            for item in measure.items {
                switch item {
                case .note(let note):
                    let relBeat = note.startBeat - Double(measureIndex) * ScoreBuilder.beatsPerMeasure
                    let x = measureX + noteHeadWidth + CGFloat(relBeat / ScoreBuilder.beatsPerMeasure) * (measureWidth - noteHeadWidth * 2)
                    let y = staffY(midi: note.pitchMidi, bottomLineY: bottomLineY, lineSpacing: lineSpacing)
                    let rect = CGRect(
                        x: x - noteHeadWidth / 2,
                        y: y - noteHeadHeight / 2,
                        width: noteHeadWidth,
                        height: noteHeadHeight
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(theme.noteFill))
                    if note.tiedToNext {
                        var tie = Path()
                        let tieStart = noteHeadWidth / 2
                        tie.move(to: CGPoint(x: x + tieStart, y: y + noteHeadHeight * 0.75))
                        tie.addQuadCurve(
                            to: CGPoint(x: x + noteHeadWidth * 1.8, y: y + noteHeadHeight * 0.75),
                            control: CGPoint(x: x + noteHeadWidth, y: y + noteHeadHeight * 1.5)
                        )
                        context.stroke(tie, with: .color(theme.textSecondary), lineWidth: max(1, lineSpacing / 10))
                    }
                case .rest:
                    break
                }
            }
        }
    }

    private func staffY(midi: Int, bottomLineY: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let stepsFromE4 = diatonicSteps(midi) - diatonicSteps(64)
        return bottomLineY - CGFloat(stepsFromE4) * (lineSpacing / 2)
    }

    private func diatonicSteps(_ midi: Int) -> Int {
        let names = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        let pitchClass = ((midi % 12) + 12) % 12
        let octave = midi / 12
        return octave * 7 + names[pitchClass]
    }
}
