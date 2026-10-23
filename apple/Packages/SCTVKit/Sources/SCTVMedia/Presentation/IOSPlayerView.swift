#if os(iOS)
    import AVKit
    import SwiftUI

    public struct IOSPlayerView: UIViewRepresentable {
        private let playback: PlaybackCoordinator
        private let overlay: PlayerOverlayState

        public init(
            playback: PlaybackCoordinator, overlay: PlayerOverlayState = PlayerOverlayState()
        ) {
            self.playback = playback
            self.overlay = overlay
        }

        public func makeUIView(context: Context) -> IOSVideoSurface {
            IOSVideoSurface(playback: playback, overlay: overlay)
        }

        public func updateUIView(_ view: IOSVideoSurface, context: Context) {
            view.updateOrientation()
        }

        public static func dismantleUIView(_ view: IOSVideoSurface, coordinator: ()) {
            view.dispose()
        }
    }

    @MainActor
    public final class IOSVideoSurface: UIView,
        @preconcurrency AVPictureInPictureControllerDelegate, UIGestureRecognizerDelegate
    {
        public override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private let playback: PlaybackCoordinator
        private let overlay: PlayerOverlayState
        private var pip: AVPictureInPictureController?
        private var notifications: [NSObjectProtocol] = []
        private var backgroundPause: Task<Void, Never>?
        private var seekTask: Task<Void, Never>?
        private var brightnessBeforeGesture: CGFloat?
        private weak var adjustedScreen: UIScreen?
        private var boostToken: UUID?
        private var orientationRequest = 0
        private var disposed = false
        private enum Drag {
            case seek(position: Int64, duration: Int64)
            case brightness(Double)
            case volume(Double)
        }
        private var drag: Drag?

        init(playback: PlaybackCoordinator, overlay: PlayerOverlayState) {
            self.playback = playback
            self.overlay = overlay
            super.init(frame: .zero)
            backgroundColor = .black
            videoLayer.player = playback.player
            videoLayer.videoGravity = .resizeAspect
            isAccessibilityElement = true
            accessibilityLabel = "视频画面"
            accessibilityHint = "左右滑动调整进度，左侧上下滑动调整亮度，右侧上下滑动调整视频音量，长按临时二倍速"
            accessibilityIdentifier = "player-gesture-surface"
            if AVPictureInPictureController.isPictureInPictureSupported() {
                pip = AVPictureInPictureController(playerLayer: videoLayer)
                pip?.delegate = self
                pip?.canStartPictureInPictureAutomaticallyFromInline = true
            }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
            press.minimumPressDuration = 0.35
            press.allowableMovement = 12
            press.delegate = self
            pan.require(toFail: press)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.require(toFail: pan)
            tap.require(toFail: press)
            [pan, press, tap].forEach(addGestureRecognizer)
            observe(UIApplication.didEnterBackgroundNotification) { $0.enteredBackground() }
            observe(UIApplication.willEnterForegroundNotification) { surface in
                surface.backgroundPause?.cancel()
                surface.backgroundPause = nil
                surface.overlay.reveal()
            }
            observe(UIApplication.willResignActiveNotification) { $0.endBoost() }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            // Leave the leading screen edge to interactive navigation outside fullscreen.
            guard !overlay.fullscreen, let window else { return true }
            if traitCollection.userInterfaceIdiom == .phone,
                window.bounds.width > window.bounds.height
            {
                return true
            }
            return touch.location(in: window).x > 24
        }

        public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer)
            -> Bool
        {
            super.gestureRecognizerShouldBegin(gestureRecognizer)
                && overlay.previewMilliseconds == nil
        }

        private func observe(
            _ name: Notification.Name, action: @escaping @MainActor (IOSVideoSurface) -> Void
        ) {
            notifications.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, !disposed else { return }
                        action(self)
                    }
                })
        }

        func updateOrientation() {
            guard orientationRequest != overlay.orientationRequest else { return }
            orientationRequest = overlay.orientationRequest
            guard traitCollection.userInterfaceIdiom == .phone, let scene = window?.windowScene
            else { return }
            scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: overlay.fullscreen ? .landscapeRight : .portrait)
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.overlay.hint = "可旋转设备调整横竖屏" }
            }
        }

        @objc private func tapped() {
            if overlay.controlsVisible { overlay.controlsVisible = false } else { overlay.reveal() }
        }

        @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                boostToken = playback.beginTemporarySpeed()
                if boostToken != nil {
                    overlay.isInteracting = true
                    overlay.hint = "2 倍速播放中"
                }
            case .ended, .cancelled, .failed: endBoost()
            default: break
            }
        }

        private func endBoost() {
            guard let token = boostToken else { return }
            boostToken = nil
            playback.endTemporarySpeed(token)
            overlay.hint = nil
            overlay.isInteracting = false
            overlay.reveal()
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            let delta = recognizer.translation(in: self)
            switch recognizer.state {
            case .began:
                let velocity = recognizer.velocity(in: self)
                if abs(velocity.x) >= abs(velocity.y) {
                    guard let snapshot = playback.capture(), let duration = snapshot.durationMs,
                        duration > 0
                    else { return }
                    drag = .seek(position: snapshot.positionMs, duration: duration)
                } else if recognizer.location(in: self).x < bounds.midX {
                    guard let screen = window?.windowScene?.screen else { return }
                    if brightnessBeforeGesture == nil {
                        brightnessBeforeGesture = screen.brightness
                        adjustedScreen = screen
                    }
                    drag = .brightness(Double(screen.brightness))
                } else {
                    drag = .volume(Double(playback.player.volume))
                }
                overlay.isInteracting = true
                overlay.reveal()
                updateDrag(delta)
            case .changed: updateDrag(delta)
            case .ended:
                if case .seek = drag, let target = overlay.previewMilliseconds {
                    seekTask?.cancel()
                    let token = overlay.beginSeekPreview(at: target)
                    drag = nil
                    overlay.hint = nil
                    seekTask = Task { [weak self] in
                        guard let self else { return }
                        defer { overlay.finishSeekPreview(token) }
                        do { try await playback.seek(to: target) } catch {
                            if !Task.isCancelled, !disposed { overlay.hint = "跳转未完成，请重试" }
                        }
                    }
                    return
                }
                finishDrag()
            case .cancelled, .failed: finishDrag()
            default: break
            }
        }

        private func updateDrag(_ delta: CGPoint) {
            switch drag {
            case .seek(let position, let duration):
                let target = PlayerInteraction.seek(
                    position: position, duration: duration, delta: delta.x, width: bounds.width)
                overlay.previewMilliseconds = target
                let difference = (target - position) / 1000
                overlay.hint = "\(difference >= 0 ? "+" : "")\(difference) 秒"
            case .brightness(let initial):
                let value = PlayerInteraction.level(
                    initial: initial, delta: delta.y, height: bounds.height)
                adjustedScreen?.brightness = value
                overlay.hint = "亮度 \(Int(value * 100))%"
            case .volume(let initial):
                let value = PlayerInteraction.level(
                    initial: initial, delta: delta.y, height: bounds.height)
                playback.player.volume = Float(value)
                overlay.hint = "视频音量 \(Int(value * 100))%"
            case nil: break
            }
        }

        private func finishDrag() {
            drag = nil
            overlay.previewMilliseconds = nil
            overlay.isInteracting = false
            overlay.hint = nil
            overlay.reveal()
        }

        private func restoreBrightness() {
            if let value = brightnessBeforeGesture { adjustedScreen?.brightness = value }
            brightnessBeforeGesture = nil
            adjustedScreen = nil
        }

        private func enteredBackground() {
            endBoost()
            finishDrag()
            restoreBrightness()
            backgroundPause?.cancel()
            // Automatic PiP gets a brief opportunity to claim playback before fallback pause.
            backgroundPause = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                guard let self, !disposed else { return }
                playback.pauseForBackground()
            }
        }

        func dispose() {
            guard !disposed else { return }
            disposed = true
            endBoost()
            finishDrag()
            restoreBrightness()
            backgroundPause?.cancel()
            seekTask?.cancel()
            notifications.forEach(NotificationCenter.default.removeObserver)
            notifications.removeAll()
            pip?.stopPictureInPicture()
            pip?.delegate = nil
            pip = nil
            playback.setPictureInPictureActive(false)
            videoLayer.player = nil
            Task { await playback.finishDismissal() }
        }

        public func pictureInPictureControllerWillStartPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            guard !disposed else { return }
            playback.setPictureInPictureActive(true)
            endBoost()
        }

        public func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            playback.setPictureInPictureActive(false)
            if UIApplication.shared.applicationState == .background {
                playback.pauseForBackground()
            }
        }

        public func pictureInPictureControllerDidStopPictureInPicture(
            _ controller: AVPictureInPictureController
        ) {
            playback.setPictureInPictureActive(false)
            if UIApplication.shared.applicationState == .background {
                playback.pauseForBackground()
            }
            Task { await playback.finishDismissal() }
        }

        public func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
                @escaping (Bool) -> Void
        ) {
            overlay.reveal()
            completionHandler(!disposed && window != nil)
        }
    }

    public struct PlayerRoutePicker: UIViewRepresentable {
        public init() {}
        public func makeUIView(context: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.tintColor = .white
            view.activeTintColor = .systemOrange
            view.prioritizesVideoDevices = true
            return view
        }
        public func updateUIView(_ view: AVRoutePickerView, context: Context) {}
    }
#endif
