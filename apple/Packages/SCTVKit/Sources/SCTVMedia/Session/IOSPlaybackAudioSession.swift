#if os(iOS)
    import AVFAudio
    import Foundation

    @MainActor
    final class IOSPlaybackAudioSession {
        private var observers: [NSObjectProtocol] = []

        init(pause: @escaping @MainActor () -> Void) throws {
            // AVPlayer activates on playback; preparing a paused source must not interrupt other audio.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
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

        func dispose() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            // Deactivation is best effort after pause; failure must not resurrect a disposed player.
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }
#endif
