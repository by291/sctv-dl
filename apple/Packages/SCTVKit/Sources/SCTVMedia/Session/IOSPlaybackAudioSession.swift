#if os(iOS)
    import AVFAudio
    import Foundation

    @MainActor
    final class IOSPlaybackAudioSession {
        private static let operations = AudioSessionOperations()
        private nonisolated static let audioQueue = DispatchQueue(label: "dev.sctvdl.audio-session")
        private var observers: [NSObjectProtocol] = []
        private var prepared = false
        private var disposal: Task<Void, Error>?

        init(pause: @escaping @MainActor () -> Void) {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
                ) { notification in
                    guard
                        (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                            == AVAudioSession.InterruptionType.began.rawValue
                    else { return }
                    Task { @MainActor in pause() }
                })
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
                ) { notification in
                    guard
                        (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                            == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                    else { return }
                    Task { @MainActor in pause() }
                })
        }

        func prepare() async throws {
            guard disposal == nil else { throw CancellationError() }
            guard !prepared else { return }
            try await Self.operations.perform {
                // AVPlayer activates on playback; paused preparation must not interrupt other audio.
                try await Self.onAudioQueue {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                }
            }.value
            guard disposal == nil else { throw CancellationError() }
            prepared = true
        }

        @discardableResult
        func dispose() -> Task<Void, Error> {
            if let disposal { return disposal }
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            let work = Self.operations.perform { try await Self.deactivate() }
            disposal = work
            return work
        }

        private nonisolated static func deactivate() async throws {
            // Xcode 26 builds retain the off-main fallback without referencing newer SDK symbols.
            #if compiler(>=6.4)
                if #available(iOS 27.0, *) {
                    _ = try await AVAudioSession.sharedInstance().deactivate(
                        options: .notifyOthersOnDeactivation)
                    return
                }
            #endif
            try await onAudioQueue {
                try AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
            }
        }

        private nonisolated static func onAudioQueue(
            _ operation: @escaping @Sendable () throws -> Void
        ) async throws {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                audioQueue.async {
                    do {
                        try operation()
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
#endif
