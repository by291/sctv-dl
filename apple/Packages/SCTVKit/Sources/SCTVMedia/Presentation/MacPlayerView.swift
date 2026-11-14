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
        fileprivate weak var surface: MacVideoSurface?

        public init() {}

        func showFeedback(_ message: String, symbol: String) {
            feedback = MacPlayerFeedback(message: message, symbol: symbol)
        }

        /// Toggles the native fullscreen state of this presentation's window.
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
        private let presentationID: UUID?

        /// Shows one playback presentation on an AppKit video surface.
        public init(
            playback: PlaybackCoordinator,
            presentation: MacPlayerPresentation = MacPlayerPresentation(),
            overlay: PlayerOverlayState = PlayerOverlayState(),
            presentationID: UUID? = nil
        ) {
            self.playback = playback
            self.presentation = presentation
            self.overlay = overlay
            self.presentationID = presentationID
        }

        public func makeNSView(context: Context) -> MacVideoSurface {
            MacVideoSurface(
                playback: playback, presentation: presentation, overlay: overlay,
                presentationID: presentationID)
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
        private let presentationID: UUID?
        private let pictureInPictureOwner = UUID()
        private var pip: AVPictureInPictureController?
        private var pipObservation: NSKeyValueObservation?
        private var notifications: [NSObjectProtocol] = []
        private var disposed = false

        // makeBackingLayer supplies this view's AVPlayerLayer.
        private var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        init(
            playback: PlaybackCoordinator, presentation: MacPlayerPresentation,
            overlay: PlayerOverlayState, presentationID: UUID?
        ) {
            self.playback = playback
            self.presentation = presentation
            self.overlay = overlay
            self.presentationID = presentationID
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
                            guard let self, !disposed, playback.ownsPresentation(presentationID),
                                presentation.surface === self
                            else { return }

                            presentation.updateFullscreen(fullscreen)
                            overlay.reveal()
                        }
                    })
            }
        }

        func togglePictureInPicture() {
            guard let pip, !disposed, playback.ownsPresentation(presentationID) else { return }

            if pip.isPictureInPictureActive {
                pip.stopPictureInPicture()
            } else if pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
            }
        }

        private func updatePictureInPicture() {
            guard !disposed, playback.ownsPresentation(presentationID),
                presentation.surface === self
            else { return }

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
            videoLayer.player = nil
            if presentation.surface === self {
                presentation.surface = nil
                presentation.updatePictureInPicture(active: false, possible: false)
            }

            // Closing the owning player window also ends its detached presentation.
            finishPictureInPicture()
        }

        public func pictureInPictureControllerWillStartPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            guard !disposed, controller === pip, presentation.surface === self else { return }
            playback.beginPictureInPicture(
                owner: pictureInPictureOwner, presentationID: presentationID)
        }

        public func pictureInPictureControllerDidStartPictureInPicture(
            _ controller: AVPictureInPictureController
        ) { updatePictureInPicture() }

        public func pictureInPictureControllerDidStopPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            guard !disposed, controller === pip, playback.ownsPresentation(presentationID) else {
                return
            }
            finishPictureInPicture()
            updatePictureInPicture()
            overlay.reveal()
        }

        public func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            guard !disposed, controller === pip, playback.ownsPresentation(presentationID) else {
                return
            }
            finishPictureInPicture()
            presentation.error = error.localizedDescription
            updatePictureInPicture()
        }

        private func finishPictureInPicture() {
            guard playback.endPictureInPicture(owner: pictureInPictureOwner) else { return }
            let session = playback.currentSessionID
            Task { await playback.finishDismissal(of: session) }
        }

        public func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
                @escaping (Bool) -> Void
        ) {
            let canRestore = !disposed && window != nil && playback.ownsPresentation(presentationID)
            if canRestore {
                window?.makeKeyAndOrderFront(nil)
                overlay.reveal()
            }
            completionHandler(canRestore)
        }
    }
#endif
