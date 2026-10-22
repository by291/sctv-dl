#if os(iOS)
    import AVKit
    import SwiftUI

    public struct IOSPlayerView: UIViewControllerRepresentable {
        private let playback: PlaybackCoordinator

        public init(playback: PlaybackCoordinator) { self.playback = playback }

        public func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = playback.player
            controller.delegate = context.coordinator
            controller.allowsPictureInPicturePlayback = true
            return controller
        }

        public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            controller.player = playback.player
        }

        public func makeCoordinator() -> Delegate { Delegate(playback: playback) }

        @MainActor
        public final class Delegate: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
            private let playback: PlaybackCoordinator

            init(playback: PlaybackCoordinator) { self.playback = playback }

            public func playerViewControllerDidStartPictureInPicture(
                _ playerViewController: AVPlayerViewController
            ) {
                playback.setPictureInPictureActive(true)
            }

            public func playerViewControllerDidStopPictureInPicture(
                _ playerViewController: AVPlayerViewController
            ) {
                playback.setPictureInPictureActive(false)
                Task { await playback.finishDismissal() }
            }
        }
    }
#endif
