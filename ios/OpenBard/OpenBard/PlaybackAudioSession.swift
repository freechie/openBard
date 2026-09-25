import AVFoundation
import Foundation

/// Session calls used by demo playback. Injected so tests can record activate/deactivate
/// without touching `AVAudioSession`.
nonisolated protocol PlaybackAudioSession: AnyObject {
    func setPlaybackCategory() async throws
    func activate() async throws
    func deactivate() async
}

nonisolated enum PlaybackAudioSessionError: Error {
    case activationFailed
    case deactivationFailed
}

/// Serial queue for session and player I/O so `setCategory`, `setActive`, and
/// `prepareToPlay` never run on the main actor.
nonisolated enum PlaybackAudioWork {
    static let queue = DispatchQueue(label: "openbard.playback-audio", qos: .userInitiated)

    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// Live `AVAudioSession` wrapper. Uses the asynchronous activate/deactivate API when
/// the running OS implements it; otherwise hops synchronous `setActive` off the main actor.
nonisolated final class SystemPlaybackAudioSession: PlaybackAudioSession {
    private static let activateSelector = NSSelectorFromString("activateWithOptions:completionHandler:")
    private static let deactivateSelector = NSSelectorFromString("deactivateWithOptions:completionHandler:")

    func setPlaybackCategory() async throws {
        try await PlaybackAudioWork.run {
            try AVAudioSession.sharedInstance().setCategory(.playback)
        }
    }

    func activate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PlaybackAudioWork.queue.async {
                let session = AVAudioSession.sharedInstance()
                if session.responds(to: Self.activateSelector) {
                    let trampoline = unsafeBitCast(session, to: AVAudioSessionAsyncActivation.self)
                    trampoline.activateWithOptions(0) { success, error in
                        if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error ?? PlaybackAudioSessionError.activationFailed)
                        }
                    }
                    return
                }
                do {
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deactivate() async {
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PlaybackAudioWork.queue.async {
                let session = AVAudioSession.sharedInstance()
                if session.responds(to: Self.deactivateSelector) {
                    let trampoline = unsafeBitCast(session, to: AVAudioSessionAsyncActivation.self)
                    trampoline.deactivateWithOptions(0) { success, error in
                        if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error ?? PlaybackAudioSessionError.deactivationFailed)
                        }
                    }
                    return
                }
                do {
                    try session.setActive(false)
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
@objc nonisolated private protocol AVAudioSessionAsyncActivation: NSObjectProtocol {
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
