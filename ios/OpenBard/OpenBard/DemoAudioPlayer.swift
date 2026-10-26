import AVFoundation
import Combine
import Foundation

@MainActor
final class DemoAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var sourceName = "Blank"

    private let session: any PlaybackAudioSession
    private var playbackGeneration: UInt64 = 0
    private var pendingDeactivation: Task<Void, Never>?
    private(set) var player: AVAudioPlayer?
    private var lastURL: URL?
    private var lastName: String?
    private var notesTempURL: URL?

    var canReplay: Bool { lastURL != nil }

    init(session: (any PlaybackAudioSession)? = nil) {
        self.session = session ?? SystemPlaybackAudioSession()
        super.init()
    }

    func playDemo(from bundle: Bundle = .main) async throws {
        try await play(url: TranscriptionLoader.demoAudioURL(from: bundle), name: "c-major-chord.wav")
    }

    func play(url: URL, name: String) async throws {
        playbackGeneration += 1
        let generation = playbackGeneration
        stopKeepingSource()

        try await session.setPlaybackCategory()
        try await session.activate()
        guard generation == playbackGeneration else { return }

        let audioPlayer: AVAudioPlayer
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
        } catch {
            await deactivateIfCurrent(generation)
            guard generation == playbackGeneration else { return }
            throw error
        }
        audioPlayer.delegate = self
        let started = await Self.prepareAndStart(audioPlayer)
        guard started else {
            await deactivateIfCurrent(generation)
            guard generation == playbackGeneration else { return }
            throw PlaybackError.failedToStart
        }
        guard generation == playbackGeneration else {
            audioPlayer.stop()
            return
        }

        player = audioPlayer
        lastURL = url
        lastName = name
        sourceName = name
        isPlaying = true
    }

    func playNotes(_ notes: [NoteEvent], name: String = "Notes") async throws {
        let wav = try await Self.renderWAV(notes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openbard-notes-\(UUID().uuidString).wav")
        try await Self.writeWAV(wav, to: url)
        if let previous = notesTempURL {
            try? FileManager.default.removeItem(at: previous)
        }
        notesTempURL = url
        try await play(url: url, name: name)
    }

    /// Replay the last loaded audio without changing note events.
    func replay() async throws {
        guard let url = lastURL, let name = lastName else {
            throw PlaybackError.noSource
        }
        try await play(url: url, name: name)
    }

    func stop() {
        playbackGeneration += 1
        stopKeepingSource()
        let generation = playbackGeneration
        pendingDeactivation = Task { @MainActor in
            await self.deactivateIfCurrent(generation)
        }
    }

    /// Clear association so Play must pick a fixture/import again (blank roll).
    func clearSource(name: String = "Blank") {
        stop()
        lastURL = nil
        lastName = nil
        sourceName = name
        if let previous = notesTempURL {
            try? FileManager.default.removeItem(at: previous)
            notesTempURL = nil
        }
    }

    func awaitPendingDeactivation() async {
        await pendingDeactivation?.value
    }

    func handlePlaybackFinished(_ finished: AVAudioPlayer) {
        guard player === finished else { return }
        playbackGeneration += 1
        player = nil
        isPlaying = false
        let generation = playbackGeneration
        pendingDeactivation = Task { @MainActor in
            await self.deactivateIfCurrent(generation)
        }
    }

    nonisolated private static func renderWAV(_ notes: [NoteEvent]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try NoteAudioRenderer.makeWAVData(from: notes)
        }.value
    }

    nonisolated private static func writeWAV(_ wav: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try wav.write(to: url)
        }.value
    }

    nonisolated private static func prepareAndStart(_ audioPlayer: AVAudioPlayer) async -> Bool {
        await withCheckedContinuation { continuation in
            PlaybackAudioWork.queue.async {
                audioPlayer.prepareToPlay()
                continuation.resume(returning: audioPlayer.play())
            }
        }
    }

    private func stopKeepingSource() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func deactivateIfCurrent(_ generation: UInt64) async {
        guard generation == playbackGeneration, player == nil, !isPlaying else { return }
        await session.deactivate()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.handlePlaybackFinished(finished)
        }
    }

    enum PlaybackError: Error {
        case failedToStart
        case noSource
    }
}
