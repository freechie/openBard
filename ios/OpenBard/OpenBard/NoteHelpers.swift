import CoreGraphics
import Foundation

enum NoteHelpers {
    /// Split a note at its midpoint into two equal-duration notes
    static func splitNote(_ note: NoteEvent) -> (NoteEvent, NoteEvent)? {
        guard note.durationSeconds > 0.1 else { return nil }

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
        return (firstNote, secondNote)
    }

    /// Find an adjacent note that can be merged with the given note
    static func findMergeCandidate(for note: NoteEvent, in notes: [NoteEvent], currentIndex: Int) -> Int? {
        return notes.enumerated().first { otherIndex, otherNote in
            otherIndex != currentIndex &&
            otherNote.pitchMidi == note.pitchMidi &&
            abs(otherNote.onsetSeconds - (note.onsetSeconds + note.durationSeconds)) < 0.05
        }?.offset
    }

    /// Merge two notes into one
    static func mergeNotes(_ note1: NoteEvent, _ note2: NoteEvent) -> NoteEvent? {
        guard note1.pitchMidi == note2.pitchMidi else { return nil }

        let earlierNote = note1.onsetSeconds < note2.onsetSeconds ? note1 : note2
        let laterNote = note1.onsetSeconds < note2.onsetSeconds ? note2 : note1

        return NoteEvent(
            pitchMidi: earlierNote.pitchMidi,
            onsetSeconds: earlierNote.onsetSeconds,
            durationSeconds: (laterNote.onsetSeconds + laterNote.durationSeconds) - earlierNote.onsetSeconds,
            velocity: max(earlierNote.velocity, laterNote.velocity),
            confidence: max(earlierNote.confidence, laterNote.confidence),
            onsetUncertaintySeconds: earlierNote.onsetUncertaintySeconds,
            staffHint: earlierNote.staffHint,
            isLocked: false
        )
    }

    /// Adjust note timing and/or pitch
    static func nudgeNote(_ note: NoteEvent, timeOffset: Double, pitchOffset: Int) -> NoteEvent? {
        let newOnset = max(0, note.onsetSeconds + timeOffset)
        let newPitch = note.pitchMidi + pitchOffset

        guard newPitch >= 0 && newPitch <= 127 else { return nil }

        var result = note
        result.onsetSeconds = newOnset
        result.pitchMidi = newPitch
        return result
    }

    static let minimumNoteDurationSeconds = 0.05
    static let defaultDrawVelocity = 0.8
    static let defaultTempoBpm = 120.0

    static func staffHint(forPitch midi: Int) -> StaffHint {
        midi < 60 ? .bass : .treble
    }

    static func defaultDurationSeconds(tempoBpm: Double?) -> Double {
        let tempo = tempoBpm ?? defaultTempoBpm
        return max(minimumNoteDurationSeconds, (60.0 / tempo) / 4.0)
    }

    static func beatSeconds(tempoBpm: Double?) -> Double {
        60.0 / (tempoBpm ?? defaultTempoBpm)
    }

    static func barsToSeconds(_ bars: Double, tempoBpm: Double?) -> Double {
        bars * 4.0 * beatSeconds(tempoBpm: tempoBpm)
    }
}

/// Visible time window inside a longer content timeline (Ableton clip overview).
struct PianoRollTimeWindow: Equatable {
    var contentSeconds: Double
    var visibleStart: Double
    var visibleDuration: Double

    static let minimumVisibleSeconds = 0.5

    var visibleEnd: Double { visibleStart + visibleDuration }

    static func blank(tempoBpm: Double = NoteHelpers.defaultTempoBpm) -> PianoRollTimeWindow {
        let content = NoteHelpers.barsToSeconds(16, tempoBpm: tempoBpm)
        let visible = NoteHelpers.barsToSeconds(4, tempoBpm: tempoBpm)
        return PianoRollTimeWindow(
            contentSeconds: content,
            visibleStart: 0,
            visibleDuration: visible
        )
    }

    static func from(contentSeconds: Double, tempoBpm: Double?) -> PianoRollTimeWindow {
        let content = max(contentSeconds, NoteHelpers.barsToSeconds(4, tempoBpm: tempoBpm))
        let visible = min(content, NoteHelpers.barsToSeconds(4, tempoBpm: tempoBpm))
        return PianoRollTimeWindow(
            contentSeconds: content,
            visibleStart: 0,
            visibleDuration: visible
        )
    }

    mutating func syncContentSeconds(_ content: Double) {
        contentSeconds = max(content, Self.minimumVisibleSeconds)
        visibleDuration = min(visibleDuration, contentSeconds)
        visibleDuration = max(visibleDuration, min(Self.minimumVisibleSeconds, contentSeconds))
        visibleStart = min(max(0, visibleStart), max(0, contentSeconds - visibleDuration))
    }

    mutating func pan(deltaSeconds: Double) {
        visibleStart = min(
            max(0, visibleStart + deltaSeconds),
            max(0, contentSeconds - visibleDuration)
        )
    }

    /// Zoom around an anchor in [0, 1] within the visible window.
    mutating func zoom(factor: Double, anchorNormalized: Double = 0.5) {
        guard factor > 0, contentSeconds > 0 else { return }
        let clampedAnchor = min(max(anchorNormalized, 0), 1)
        let anchor = visibleStart + visibleDuration * clampedAnchor
        let newDuration = min(
            contentSeconds,
            max(Self.minimumVisibleSeconds, visibleDuration / factor)
        )
        visibleDuration = newDuration
        visibleStart = min(
            max(0, anchor - newDuration * clampedAnchor),
            max(0, contentSeconds - visibleDuration)
        )
    }

    mutating func setHotspot(start: Double, duration: Double) {
        let dur = min(contentSeconds, max(Self.minimumVisibleSeconds, duration))
        visibleDuration = dur
        visibleStart = min(max(0, start), max(0, contentSeconds - dur))
    }
}

/// Frozen pitch bounds so dragging does not reflow the grid under the finger.
struct PianoRollViewport: Equatable {
    var minPitch: Int
    var maxPitch: Int
    var timelineSeconds: Double

    static let blank = PianoRollViewport(
        minPitch: 48,
        maxPitch: 72,
        timelineSeconds: NoteHelpers.barsToSeconds(16, tempoBpm: NoteHelpers.defaultTempoBpm)
    )

    static let pitchPadding = 8
    static let minTimelinePaddingBeats = 8.0

    var pitchSpan: Int { max(maxPitch - minPitch, 1) }

    static func seeded(
        from notes: [NoteEvent],
        tempoBpm: Double?,
        pitchPadding: Int = pitchPadding
    ) -> PianoRollViewport {
        guard !notes.isEmpty else { return .blank }

        let pitches = notes.map(\.pitchMidi)
        let minP = max(0, (pitches.min() ?? 60) - pitchPadding)
        let maxP = min(127, (pitches.max() ?? 60) + pitchPadding)
        let contentEnd = notes.map { $0.onsetSeconds + $0.durationSeconds }.max() ?? 1
        let tempo = tempoBpm ?? NoteHelpers.defaultTempoBpm
        let beat = 60.0 / tempo
        let padded = contentEnd + minTimelinePaddingBeats * beat
        let minContent = NoteHelpers.barsToSeconds(16, tempoBpm: tempo)
        return PianoRollViewport(
            minPitch: minP,
            maxPitch: max(minP + 1, maxP),
            timelineSeconds: max(padded, minContent)
        )
    }

    /// Expand to fit a note without shrinking.
    func expanding(toFit note: NoteEvent) -> PianoRollViewport {
        var next = self
        next.minPitch = min(next.minPitch, max(0, note.pitchMidi - 1))
        next.maxPitch = max(next.maxPitch, min(127, note.pitchMidi + 1))
        let end = note.onsetSeconds + note.durationSeconds
        if end > next.timelineSeconds {
            next.timelineSeconds = end + 0.5
        }
        return next
    }
}

/// Snapshot-based piano-roll edits (Ableton-style drag from finger start).
enum PianoRollEdit {
    struct Snapshot: Equatable {
        var pitchMidi: Int
        var onsetSeconds: Double
        var durationSeconds: Double
    }

    struct Scales: Equatable {
        var secondsPerPoint: Double
        var rowHeight: Double

        static func from(
            viewport: PianoRollViewport,
            timeWindow: PianoRollTimeWindow,
            size: CGSize
        ) -> Scales {
            let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)
            return Scales(
                secondsPerPoint: timeWindow.visibleDuration / Double(max(metrics.drawableWidth, 1)),
                rowHeight: Double(max(metrics.rowHeight, 1))
            )
        }

        static func from(viewport: PianoRollViewport, size: CGSize) -> Scales {
            from(
                viewport: viewport,
                timeWindow: PianoRollTimeWindow(
                    contentSeconds: viewport.timelineSeconds,
                    visibleStart: 0,
                    visibleDuration: viewport.timelineSeconds
                ),
                size: size
            )
        }
    }

    static func snapshot(of note: NoteEvent) -> Snapshot {
        Snapshot(
            pitchMidi: note.pitchMidi,
            onsetSeconds: note.onsetSeconds,
            durationSeconds: note.durationSeconds
        )
    }

    static func movedNote(
        from snapshot: Snapshot,
        translation: CGSize,
        scales: Scales,
        base: NoteEvent
    ) -> NoteEvent? {
        let timeOffset = Double(translation.width) * scales.secondsPerPoint
        let pitchOffset = Int((-Double(translation.height) / scales.rowHeight).rounded())
        let newPitch = snapshot.pitchMidi + pitchOffset
        guard newPitch >= 0 && newPitch <= 127 else { return nil }

        var result = base
        result.onsetSeconds = max(0, snapshot.onsetSeconds + timeOffset)
        result.pitchMidi = newPitch
        result.staffHint = NoteHelpers.staffHint(forPitch: newPitch)
        return result
    }

    static func resizedNote(
        from snapshot: Snapshot,
        translation: CGSize,
        scales: Scales,
        base: NoteEvent
    ) -> NoteEvent? {
        let durationOffset = Double(translation.width) * scales.secondsPerPoint
        var result = base
        result.onsetSeconds = snapshot.onsetSeconds
        result.pitchMidi = snapshot.pitchMidi
        result.durationSeconds = max(
            NoteHelpers.minimumNoteDurationSeconds,
            snapshot.durationSeconds + durationOffset
        )
        return result
    }

    static func resizedNoteFromLeft(
        from snapshot: Snapshot,
        translation: CGSize,
        scales: Scales,
        base: NoteEvent
    ) -> NoteEvent? {
        let delta = Double(translation.width) * scales.secondsPerPoint
        let end = snapshot.onsetSeconds + snapshot.durationSeconds
        let newOnset = min(
            max(0, snapshot.onsetSeconds + delta),
            end - NoteHelpers.minimumNoteDurationSeconds
        )
        var result = base
        result.pitchMidi = snapshot.pitchMidi
        result.onsetSeconds = newOnset
        result.durationSeconds = max(NoteHelpers.minimumNoteDurationSeconds, end - newOnset)
        return result
    }

    enum EdgeHit {
        case left
        case right
        case body
    }

    static func edgeHit(frame: CGRect, point: CGPoint, edgeWidth: CGFloat = 18) -> EdgeHit {
        let half = min(edgeWidth, frame.width / 2)
        let left = CGRect(x: frame.minX, y: frame.minY, width: half, height: frame.height)
        let right = CGRect(x: frame.maxX - half, y: frame.minY, width: half, height: frame.height)
        if right.contains(point) { return .right }
        if left.contains(point) { return .left }
        return .body
    }

    static func isRightEdgeHit(frame: CGRect, point: CGPoint, edgeWidth: CGFloat = 18) -> Bool {
        edgeHit(frame: frame, point: point, edgeWidth: edgeWidth) == .right
    }

    static func pitchAndOnset(
        at point: CGPoint,
        viewport: PianoRollViewport,
        timeWindow: PianoRollTimeWindow,
        size: CGSize
    ) -> (pitch: Int, onset: Double)? {
        let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)
        guard point.x >= metrics.labelGutter,
              point.x <= size.width - metrics.trailingInset,
              point.y >= metrics.contentMinY,
              point.y < metrics.velocityMinY else {
            return nil
        }

        let row = Int(((point.y - metrics.contentMinY) / metrics.rowHeight).rounded(.down))
        let pitch = viewport.maxPitch - row
        guard pitch >= viewport.minPitch && pitch <= viewport.maxPitch else { return nil }

        let relX = Double(point.x - metrics.labelGutter)
        let onset = timeWindow.visibleStart
            + max(0, relX * timeWindow.visibleDuration / Double(max(metrics.drawableWidth, 1)))
        return (pitch, onset)
    }

    static func pitchAndOnset(
        at point: CGPoint,
        viewport: PianoRollViewport,
        size: CGSize
    ) -> (pitch: Int, onset: Double)? {
        pitchAndOnset(
            at: point,
            viewport: viewport,
            timeWindow: PianoRollTimeWindow(
                contentSeconds: viewport.timelineSeconds,
                visibleStart: 0,
                visibleDuration: viewport.timelineSeconds
            ),
            size: size
        )
    }

    static func makeDrawnNote(
        pitch: Int,
        onset: Double,
        duration: Double,
        velocity: Double = NoteHelpers.defaultDrawVelocity
    ) -> NoteEvent {
        NoteEvent(
            pitchMidi: pitch,
            onsetSeconds: max(0, onset),
            durationSeconds: max(NoteHelpers.minimumNoteDurationSeconds, duration),
            velocity: velocity,
            confidence: 1,
            staffHint: NoteHelpers.staffHint(forPitch: pitch),
            isLocked: false
        )
    }
}
