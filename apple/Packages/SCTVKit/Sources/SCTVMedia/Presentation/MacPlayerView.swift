#if os(macOS)
    import AVKit
    import SwiftUI

    public struct MacPlayerView: NSViewRepresentable {
        private let playback: PlaybackCoordinator

        public init(playback: PlaybackCoordinator) { self.playback = playback }

        public func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = playback.player
            view.controlsStyle = .floating
            view.showsFullScreenToggleButton = true
            view.allowsPictureInPicturePlayback = true
            view.pictureInPictureDelegate = context.coordinator
            return view
        }

        public func updateNSView(_ view: AVPlayerView, context: Context) {
            view.player = playback.player
        }

        public func makeCoordinator() -> Delegate { Delegate(playback: playback) }

        @MainActor
        public final class Delegate: NSObject, @preconcurrency AVPlayerViewPictureInPictureDelegate
        {
            private let playback: PlaybackCoordinator

            init(playback: PlaybackCoordinator) { self.playback = playback }

            public func playerViewDidStartPicture(inPicture playerView: AVPlayerView) {
                playback.setPictureInPictureActive(true)
            }

            public func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
                playback.setPictureInPictureActive(false)
                Task { await playback.finishDismissal() }
            }
        }
    }
#endif
