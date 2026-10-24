#if os(macOS)
    import AVKit
    import Observation
    import SwiftUI

    @MainActor @Observable
    public final class MacPlayerPresentation {
        public private(set) var fullscreen = false
        public private(set) var pictureInPicture = false
        public private(set) var pictureInPicturePossible = false
        public var error: String?
        var feedback: MacPlayerFeedback?
        func showFeedback(_ message: String, symbol: String) {
            feedback = MacPlayerFeedback(message: message, symbol: symbol)
        }
        fileprivate weak var surface: MacVideoSurface?
        public init() {}
        public func toggleFullscreen() {
            surface?.window?.toggleFullScreen(nil)
        }
        func togglePictureInPicture() { surface?.togglePictureInPicture() }
        fileprivate func updateFullscreen(_ value: Bool) { fullscreen = value }
        fileprivate func updatePictureInPicture(active: Bool, possible: Bool) {
            pictureInPicture = active
            pictureInPicturePossible = possible
        }
    }

    public struct MacPlayerView: NSViewRepresentable {
        private let playback: PlaybackCoordinator
        private let presentation: MacPlayerPresentation
        private let overlay: PlayerOverlayState

        public init(
            playback: PlaybackCoordinator,
            presentation: MacPlayerPresentation = MacPlayerPresentation(),
            overlay: PlayerOverlayState = PlayerOverlayState()
        ) {
            self.playback = playback
            self.presentation = presentation
            self.overlay = overlay
        }

        public func makeNSView(context: Context) -> MacVideoSurface {
            MacVideoSurface(playback: playback, presentation: presentation, overlay: overlay)
        }
        public func updateNSView(_ view: MacVideoSurface, context: Context) {}
        public static func dismantleNSView(_ view: MacVideoSurface, coordinator: ()) {
            view.dispose()
        }
    }

    @MainActor
    public final class MacVideoSurface: NSView, @preconcurrency AVPictureInPictureControllerDelegate
    {
        private let playback: PlaybackCoordinator
        private let presentation: MacPlayerPresentation
        private let overlay: PlayerOverlayState
        private var pip: AVPictureInPictureController?
        private var pipObservation: NSKeyValueObservation?
        private var notifications: [NSObjectProtocol] = []
        private var disposed = false
        private var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        init(
            playback: PlaybackCoordinator, presentation: MacPlayerPresentation,
            overlay: PlayerOverlayState
        ) {
            self.playback = playback
            self.presentation = presentation
            self.overlay = overlay
            super.init(frame: .zero)
            wantsLayer = true
            videoLayer.player = playback.player
            videoLayer.videoGravity = .resizeAspect
            presentation.surface = self
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
            setAccessibilityLabel("视频画面")
            setAccessibilityIdentifier("mac-video-surface")
            if AVPictureInPictureController.isPictureInPictureSupported() {
                pip = AVPictureInPictureController(playerLayer: videoLayer)
                pip?.delegate = self
                pipObservation = pip?.observe(
                    \.isPictureInPicturePossible, options: [.initial, .new]
                ) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.updatePictureInPicture() }
                }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        public override func makeBackingLayer() -> CALayer { AVPlayerLayer() }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            notifications.forEach(NotificationCenter.default.removeObserver)
            notifications.removeAll()
            guard let window, !disposed else { return }
            presentation.updateFullscreen(window.styleMask.contains(.fullScreen))
            for (name, fullscreen) in [
                (NSWindow.willEnterFullScreenNotification, true),
                (NSWindow.didExitFullScreenNotification, false),
            ] {
                notifications.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self, !disposed else { return }
                            presentation.updateFullscreen(fullscreen)
                            overlay.reveal()
                        }
                    })
            }
        }
        func togglePictureInPicture() {
            guard let pip, !disposed else { return }
            if pip.isPictureInPictureActive {
                pip.stopPictureInPicture()
            } else if pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
            }
        }
        private func updatePictureInPicture() {
            guard !disposed else { return }
            presentation.updatePictureInPicture(
                active: pip?.isPictureInPictureActive == true,
                possible: pip?.isPictureInPicturePossible == true)
        }
        func dispose() {
            guard !disposed else { return }
            disposed = true
            notifications.forEach(NotificationCenter.default.removeObserver)
            notifications.removeAll()
            pipObservation?.invalidate()
            pipObservation = nil
            pip?.stopPictureInPicture()
            pip?.delegate = nil
            pip = nil
            playback.setPictureInPictureActive(false)
            videoLayer.player = nil
            if presentation.surface === self {
                presentation.surface = nil
                presentation.updatePictureInPicture(active: false, possible: false)
            }
            // Closing the owning player window also ends its detached presentation.
            Task { await playback.finishDismissal() }
        }
        public func pictureInPictureControllerWillStartPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            guard !disposed else { return }
            playback.setPictureInPictureActive(true)
        }
        public func pictureInPictureControllerDidStartPictureInPicture(
            _ controller: AVPictureInPictureController
        ) { updatePictureInPicture() }
        public func pictureInPictureControllerDidStopPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            guard !disposed else { return }
            playback.setPictureInPictureActive(false)
            updatePictureInPicture()
            overlay.reveal()
            Task { await playback.finishDismissal() }
        }
        public func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            guard !disposed else { return }
            playback.setPictureInPictureActive(false)
            presentation.error = error.localizedDescription
            updatePictureInPicture()
        }
        public func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
                @escaping (Bool) -> Void
        ) {
            window?.makeKeyAndOrderFront(nil)
            overlay.reveal()
            completionHandler(!disposed && window != nil)
        }
    }
#endif
