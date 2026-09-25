import SwiftUI

/// Ableton-style clip overview: full timeline with a draggable/resizable visible hotspot.
struct PianoRollOverview: View {
    let notes: [NoteEvent]
    @Binding var timeWindow: PianoRollTimeWindow
    var tempoBpm: Double
    var theme: AbletonTheme

    @State private var dragKind: DragKind?
    @State private var dragStartWindow: PianoRollTimeWindow?

    private enum DragKind {
        case move
        case resizeLeft
        case resizeRight
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = geo.size.height
            let content = max(timeWindow.contentSeconds, 0.001)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.surface)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.border, lineWidth: 1)

                Canvas { context, size in
                    drawBars(context: context, size: size, content: content, tempo: tempoBpm)
                    drawNotes(context: context, size: size, content: content)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

                hotspot(width: width, height: height, content: content)
                    .highPriorityGesture(hotspotGesture(width: width, content: content))
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { event in
                    let t = Double(event.location.x / width) * content
                    var next = timeWindow
                    next.setHotspot(
                        start: t - timeWindow.visibleDuration / 2,
                        duration: timeWindow.visibleDuration
                    )
                    timeWindow = next
                }
            )
        }
        .frame(height: 36)
        .accessibilityIdentifier("piano-roll-overview")
        .accessibilityLabel("Clip overview")
    }

    private func hotspot(width: CGFloat, height: CGFloat, content: Double) -> some View {
        let x = CGFloat(timeWindow.visibleStart / content) * width
        let w = max(CGFloat(timeWindow.visibleDuration / content) * width, 18)
        return RoundedRectangle(cornerRadius: 3)
            .stroke(theme.textPrimary.opacity(0.85), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.textPrimary.opacity(0.08))
            )
            .frame(width: w, height: height - 4)
            .offset(x: x, y: 2)
    }

    private func hotspotGesture(width: CGFloat, content: Double) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragKind == nil {
                    let x = CGFloat(timeWindow.visibleStart / content) * width
                    let w = max(CGFloat(timeWindow.visibleDuration / content) * width, 18)
                    let localX = value.startLocation.x - x
                    switch PianoRollEdit.edgeHit(
                        width: w,
                        localX: localX,
                        edgeWidth: PianoRollEdit.overviewResizeEdgeWidth
                    ) {
                    case .left:
                        dragKind = .resizeLeft
                    case .right:
                        dragKind = .resizeRight
                    case .body:
                        dragKind = .move
                    }
                    dragStartWindow = timeWindow
                }
                guard let start = dragStartWindow, let kind = dragKind else { return }
                let deltaSeconds = Double(value.translation.width / width) * content
                var next = start
                switch kind {
                case .move:
                    next.setHotspot(start: start.visibleStart + deltaSeconds, duration: start.visibleDuration)
                case .resizeLeft:
                    let newStart = start.visibleStart + deltaSeconds
                    let newDuration = start.visibleEnd - newStart
                    next.setHotspot(start: newStart, duration: newDuration)
                case .resizeRight:
                    next.setHotspot(start: start.visibleStart, duration: start.visibleDuration + deltaSeconds)
                }
                timeWindow = next
            }
            .onEnded { _ in
                dragKind = nil
                dragStartWindow = nil
            }
    }

    private func drawBars(context: GraphicsContext, size: CGSize, content: Double, tempo: Double) {
        let beat = 60.0 / tempo
        let bar = beat * 4
        var barIndex = 0
        while Double(barIndex) * bar <= content + 0.0001 {
            let t = Double(barIndex) * bar
            let x = CGFloat(t / content) * size.width
            let isMajor = barIndex % 4 == 0
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                },
                with: .color(theme.gridLine.opacity(isMajor ? 0.9 : 0.35)),
                lineWidth: isMajor ? 1 : 0.5
            )
            if isMajor || barIndex == 0 {
                context.draw(
                    Text("\(barIndex + 1)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textSecondary),
                    at: CGPoint(x: x + 3, y: 2),
                    anchor: .topLeading
                )
            }
            barIndex += 1
            if barIndex > 512 { break }
        }
    }

    private func drawNotes(context: GraphicsContext, size: CGSize, content: Double) {
        guard !notes.isEmpty else { return }
        let pitches = notes.map(\.pitchMidi)
        let minP = pitches.min() ?? 48
        let maxP = max(pitches.max() ?? 72, minP + 1)
        let span = CGFloat(maxP - minP)

        for note in notes {
            let x = CGFloat(note.onsetSeconds / content) * size.width
            let w = max(CGFloat(note.durationSeconds / content) * size.width, 2)
            let yNorm = CGFloat(maxP - note.pitchMidi) / span
            let y = 4 + yNorm * (size.height - 10)
            let rect = CGRect(x: x, y: y, width: w, height: 3)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(theme.accent.opacity(0.85)))
        }
    }
}
