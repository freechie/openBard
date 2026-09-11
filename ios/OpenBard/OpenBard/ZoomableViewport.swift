import SwiftUI

enum ZoomMath {
    static let minimum: CGFloat = 0.75
    static let maximum: CGFloat = 6

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }

    static func contentSize(viewport: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: viewport.width * scale, height: viewport.height * scale)
    }

    static func clampOffset(_ offset: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        let extraX = max(0, (viewport.width * scale - viewport.width) / 2) + 24
        let extraY = max(0, (viewport.height * scale - viewport.height) / 2) + 24
        return CGSize(
            width: min(max(offset.width, -extraX), extraX),
            height: min(max(offset.height, -extraY), extraY)
        )
    }
}

struct ZoomableViewport<Content: View>: View {
    var allowsPan: Bool = true
    var theme: AbletonTheme
    @ViewBuilder var content: () -> Content

    @State private var scale: CGFloat = 1
    @State private var liveMagnification: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var liveOffset: CGSize = .zero
    @State private var viewportSize: CGSize = CGSize(width: 1, height: 1)

    private var currentScale: CGFloat {
        ZoomMath.clamp(scale * liveMagnification)
    }

    var body: some View {
        GeometryReader { geo in
            let contentSize = ZoomMath.contentSize(viewport: geo.size, scale: currentScale)
            content()
                .frame(width: contentSize.width, height: contentSize.height)
                .offset(
                    x: offset.width + liveOffset.width,
                    y: offset.height + liveOffset.height
                )
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .clipped()
                .contentShape(Rectangle())
                .onAppear { viewportSize = geo.size }
                .onChange(of: geo.size) { _, newSize in
                    viewportSize = newSize
                    offset = ZoomMath.clampOffset(offset, viewport: newSize, scale: currentScale)
                }
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(currentScale > 1.02 ? panGesture : nil)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { reset() }
                )
        }
        .background(theme.pianoRollBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                liveMagnification = value.magnification
            }
            .onEnded { value in
                scale = ZoomMath.clamp(scale * value.magnification)
                liveMagnification = 1
                offset = ZoomMath.clampOffset(offset, viewport: viewportSize, scale: scale)
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard allowsPan, currentScale > 1.02 else { return }
                liveOffset = value.translation
            }
            .onEnded { value in
                guard allowsPan, currentScale > 1.02 else {
                    liveOffset = .zero
                    return
                }
                let proposed = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                offset = ZoomMath.clampOffset(proposed, viewport: viewportSize, scale: currentScale)
                liveOffset = .zero
            }
    }

    private func reset() {
        scale = 1
        liveMagnification = 1
        offset = .zero
        liveOffset = .zero
    }
}
