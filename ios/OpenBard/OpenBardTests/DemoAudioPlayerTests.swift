import Foundation
import Testing
@testable import OpenBard

nonisolated final class RecordingPlaybackAudioSession: PlaybackAudioSession {
    enum Call: Equatable {
        case setPlaybackCategory
        case activate
        case deactivate
    }

    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func setPlaybackCategory() async throws {
        record(.setPlaybackCategory)
    }

    func activate() async throws {
        record(.activate)
    }

    func deactivate() async {
        record(.deactivate)
    }

    private func record(_ call: Call) {
        lock.withLock { recorded.append(call) }
    }
}

@MainActor
struct DemoAudioPlayerTests {
    @Test func playActivatesSessionWithoutDeactivating() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "held")

        #expect(session.calls == [.setPlaybackCategory, .activate])
        #expect(player.isPlaying)
        #expect(player.sourceName == "held")

        await stop(player)
    }

    @Test func stopDeactivatesAfterPlaybackEnds() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "held")

        player.stop()
        await player.awaitPendingDeactivation()

        #expect(!player.isPlaying)
        #expect(session.calls == [.setPlaybackCategory, .activate, .deactivate])
    }

    @Test func clearSourceDeactivates() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "held")

        player.clearSource()
        await player.awaitPendingDeactivation()

        #expect(!player.isPlaying)
        #expect(player.sourceName == "Blank")
        #expect(!player.canReplay)
        #expect(session.calls.last == .deactivate)
    }

    @Test func replacingPlayDoesNotDeactivate() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "first")
        try await player.play(url: try writeHeldWav(), name: "second")
        await player.awaitPendingDeactivation()

        #expect(player.sourceName == "second")
        #expect(player.isPlaying)
        #expect(session.calls == [
            .setPlaybackCategory,
            .activate,
            .setPlaybackCategory,
            .activate,
        ])

        await stop(player)
    }

    @Test func replayDoesNotDeactivate() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "held")
        try await player.replay()
        await player.awaitPendingDeactivation()

        #expect(player.isPlaying)
        #expect(session.calls == [
            .setPlaybackCategory,
            .activate,
            .setPlaybackCategory,
            .activate,
        ])

        await stop(player)
    }

    @Test func finishDelegateDeactivatesCurrentPlayerOnly() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "held")
        let finished = try #require(player.player)

        player.handlePlaybackFinished(finished)
        await player.awaitPendingDeactivation()

        #expect(!player.isPlaying)
        #expect(session.calls.last == .deactivate)
    }

    @Test func finishDelegateIgnoresSupersededPlayer() async throws {
        let session = RecordingPlaybackAudioSession()
        let player = DemoAudioPlayer(session: session)
        try await player.play(url: try writeHeldWav(), name: "first")
        let first = try #require(player.player)
        try await player.play(url: try writeHeldWav(), name: "second")

        player.handlePlaybackFinished(first)
        await player.awaitPendingDeactivation()

        #expect(player.isPlaying)
        #expect(player.sourceName == "second")
        #expect(!session.calls.contains(.deactivate))

        await stop(player)
    }

    private func stop(_ player: DemoAudioPlayer) async {
        player.stop()
        await player.awaitPendingDeactivation()
    }

    private func writeHeldWav() throws -> URL {
        let notes = [
            NoteEvent(
                pitchMidi: 60,
                onsetSeconds: 0,
                durationSeconds: 3,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            )
        ]
        let wav = try NoteAudioRenderer.makeWAVData(from: notes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openbard-session-test-\(UUID().uuidString).wav")
        try wav.write(to: url)
        return url
    }
}
