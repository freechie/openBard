import AVFoundation
import Combine
import Foundation

@MainActor
final class DemoAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var sourceName = "c-major-chord.wav"

    private var player: AVAudioPlayer?

    func playDemo(from bundle: Bundle = .main) throws {
        try play(url: TranscriptionLoader.demoAudioURL(from: bundle), name: "c-major-chord.wav")
    }

    func play(url: URL, name: String) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        guard audioPlayer.play() else {
            throw PlaybackError.failedToStart
        }
        player = audioPlayer
        sourceName = name
        isPlaying = true
    }

    func stop() {
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
    }
}
