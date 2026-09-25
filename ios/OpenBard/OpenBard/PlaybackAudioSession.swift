import AVFoundation
import Foundation

/// Session calls used by demo playback. Injected so tests can record activate/deactivate
/// without touching `AVAudioSession`.
protocol PlaybackAudioSession: AnyObject {
    func setPlaybackCategory() throws
    func activate() async throws
    func deactivate() async
}

enum PlaybackAudioSessionError: Error {
    case activationFailed
    case deactivationFailed
}

/// Live `AVAudioSession` wrapper. Uses the asynchronous activate/deactivate API when
/// the running OS implements it; otherwise hops synchronous `setActive` off the main actor.
final class SystemPlaybackAudioSession: PlaybackAudioSession {
    func setPlaybackCategory() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback)
    }

    func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        if session.responds(to: AVAudioSessionAsyncActivation.activateSelector) {
            try await Self.activateAsynchronously(session)
            return
        }
        try await Self.setActiveOffMainActor(true)
    }

    func deactivate() async {
        let session = AVAudioSession.sharedInstance()
        if session.responds(to: AVAudioSessionAsyncActivation.deactivateSelector) {
            try? await Self.deactivateAsynchronously(session)
            return
        }
        try? await Self.setActiveOffMainActor(false)
    }

    private static func activateAsynchronously(_ session: AVAudioSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let trampoline = unsafeBitCast(session, to: AVAudioSessionAsyncActivation.self)
            trampoline.activateWithOptions(0) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PlaybackAudioSessionError.activationFailed)
                }
            }
        }
    }

    private static func deactivateAsynchronously(_ session: AVAudioSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let trampoline = unsafeBitCast(session, to: AVAudioSessionAsyncActivation.self)
            trampoline.deactivateWithOptions(0) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PlaybackAudioSessionError.deactivationFailed)
                }
            }
        }
    }

    private static func setActiveOffMainActor(_ active: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try AVAudioSession.sharedInstance().setActive(active)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// ObjC surface for `activateWithOptions:completionHandler:` and
/// `deactivateWithOptions:completionHandler:`. Declared locally so this still compiles
/// if the iOS SDK overlays those methods as watchOS-only.
@objc private protocol AVAudioSessionAsyncActivation: NSObjectProtocol {
    @objc(activateWithOptions:completionHandler:)
    func activateWithOptions(
        _ options: UInt,
        completionHandler: @escaping (Bool, NSError?) -> Void
    )

    @objc(deactivateWithOptions:completionHandler:)
    func deactivateWithOptions(
        _ options: UInt,
        completionHandler: @escaping (Bool, NSError?) -> Void
    )
}

private extension AVAudioSessionAsyncActivation {
    static var activateSelector: Selector {
        #selector(activateWithOptions(_:completionHandler:))
    }

    static var deactivateSelector: Selector {
        #selector(deactivateWithOptions(_:completionHandler:))
    }
}
