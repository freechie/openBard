import AVFoundation
import Combine
import Foundation

@MainActor
final class DemoAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var sourceName = "Blank"

    private var player: AVAudioPlayer?
    private var lastURL: URL?
    private var lastName: String?
    private var notesTempURL: URL?

    var canReplay: Bool { lastURL != nil }

    func playDemo(from bundle: Bundle = .main) throws {
        try play(url: TranscriptionLoader.demoAudioURL(from: bundle), name: "c-major-chord.wav")
    }

    func play(url: URL, name: String) throws {
        stopKeepingSource()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)

        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        guard audioPlayer.play() else {
            throw PlaybackError.failedToStart
        }

        player = audioPlayer
        lastURL = url
        lastName = name
        sourceName = name
        isPlaying = true
    }

    /// Render and play the current piano-roll notes as synthesized audio.
    func playNotes(_ notes: [NoteEvent], name: String = "Notes") throws {
        let wav = try NoteAudioRenderer.makeWAVData(from: notes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openbard-notes-\(UUID().uuidString).wav")
        try wav.write(to: url)
        if let previous = notesTempURL {
            try? FileManager.default.removeItem(at: previous)
        }
        notesTempURL = url
        try play(url: url, name: name)
    }

    /// Replay the last loaded audio without changing note events.
    func replay() throws {
        guard let url = lastURL, let name = lastName else {
            throw PlaybackError.noSource
        }
        try play(url: url, name: name)
    }

    func stop() {
        stopKeepingSource()
    }

    /// Clear association so Play must pick a fixture/import again (blank roll).
    func clearSource(name: String = "Blank") {
        stopKeepingSource()
        lastURL = nil
        lastName = nil
        sourceName = name
        if let previous = notesTempURL {
            try? FileManager.default.removeItem(at: previous)
            notesTempURL = nil
        }
    }

    private func stopKeepingSource() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }

    enum PlaybackError: Error {
        case failedToStart
        case noSource
    }
}
