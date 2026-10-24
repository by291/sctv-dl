#if os(macOS)
    import SCTVCore
    import SwiftUI

    public struct MacPlayerControlsView: View {
        let session: PlayerSession
        let snapshot: PlaybackSnapshot?
        let overlay: PlayerOverlayState
        let presentation: MacPlayerPresentation
        @State private var scrubbing = false
        @State private var scrubPosition = 0.0
        @State private var hovering = false
        @State private var volume = 1.0
        @State private var muted = false
        @State private var seekOwner = UUID()
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(
            session: PlayerSession, snapshot: PlaybackSnapshot?, overlay: PlayerOverlayState,
            presentation: MacPlayerPresentation
        ) {
            self.session = session
            self.snapshot = snapshot
            self.overlay = overlay
            self.presentation = presentation
        }
        private var playing: Bool { session.playback.capture()?.playIntent == .playing }
        private var duration: Int64 { max(1, snapshot?.durationMs ?? 1) }
        private var position: Int64 {
            overlay.previewMilliseconds
                ?? (scrubbing
                    ? Int64(scrubPosition)
                    : session.playback.capture()?.positionMs ?? snapshot?.positionMs ?? 0)
        }
        private var visible: Bool { overlay.controlsVisible || !playing || voiceOver }

        public var body: some View {
            VStack(spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        volumeControls.frame(maxWidth: .infinity, alignment: .leading)
                        transport
                        options.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    VStack(spacing: 8) {
                        HStack {
                            volumeControls
                            Spacer(minLength: 16)
                            transport
                        }
                        options.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                timeline
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .frame(maxWidth: 760)
            .background {
                MacPlayerMaterial()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .foregroundStyle(Color(white: 0.94)).tint(Color(white: 0.94))
            .buttonStyle(.plain)
            .onHover { value in
                hovering = value
                overlay.reveal()
            }
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: visible)
            .padding(24)
            .background {
                MacPlayerKeyboard(
                    enabled: session.playback.state == .ready && !scrubbing
                        && !overlay.hasPresentedOptions
                ) {
                    command in
                    switch command {
                    case .togglePlayback: togglePlayback()
                    case .backward: skip(by: -10_000)
                    case .forward: skip(by: 10_000)
                    case .volumeUp: adjustVolume(by: 0.05)
                    case .volumeDown: adjustVolume(by: -0.05)
                    case .fullscreen: presentation.toggleFullscreen()
                    }
                }
            }
            .task(id: overlay.activity) {
                let activity = overlay.activity
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                overlay.hideIfIdle(
                    activity: activity, playing: playing, pinned: hovering || voiceOver)
            }
            .onChange(of: playing) { _, _ in overlay.reveal() }
            .onChange(of: session.presentationID) { _, _ in
                session.playback.seekInteraction.cancel(owner: seekOwner)
                scrubbing = false
                overlay.setGestureInteraction(active: false)
                overlay.reveal()
            }
            .onAppear {
                volume = Double(session.playback.player.volume)
                muted = session.playback.player.isMuted
            }
            .onDisappear { session.playback.seekInteraction.cancel(owner: seekOwner) }
        }

        private var timeline: some View {
            HStack(spacing: 18) {
                Text(timestamp(position)).frame(minWidth: 40, alignment: .leading)
                MacPlayerSlider(
                    value: Binding(
                        get: { scrubbing ? scrubPosition : Double(position) },
                        set: { scrubPosition = $0 }), range: 0...Double(duration),
                    label: "播放进度", identifier: "player-progress"
                ) { editing in
                    if editing {
                        scrubPosition = Double(position)
                        scrubbing = true
                        overlay.setGestureInteraction(active: true)
                        overlay.reveal()
                    } else {
                        let target = Int64(scrubPosition)
                        scrubbing = false
                        overlay.setGestureInteraction(active: false)
                        seek(to: target)
                    }
                }
                .frame(height: 24)
                .disabled(
                    snapshot?.durationMs == nil || session.playback.state != .ready
                        || (!scrubbing && overlay.previewMilliseconds != nil)
                )
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(timestamp(position))，共 \(timestamp(duration))")
                .accessibilityIdentifier("player-progress")
                Text(timestamp(duration)).frame(minWidth: 40, alignment: .trailing)
            }.font(.system(size: 13).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
        }

        private var transport: some View {
            HStack(spacing: 8) {
                button("后退 10 秒", symbol: "backward.fill", id: "player-skip-backward", size: 23) {
                    skip(by: -10_000)
                }
                button(
                    playing ? "暂停" : "播放", symbol: playing ? "pause.fill" : "play.fill",
                    id: "player-toggle-play", size: 34, width: 48
                ) {
                    togglePlayback()
                }
                button("前进 10 秒", symbol: "forward.fill", id: "player-skip-forward", size: 23) {
                    skip(by: 10_000)
                }
            }
            .disabled(session.playback.state != .ready)
        }

        private var volumeControls: some View {
            HStack(spacing: 4) {
                button(
                    muted ? "取消静音" : "静音",
                    symbol: muted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    id: "player-mute"
                ) {
                    muted.toggle()
                    session.playback.player.isMuted = muted
                }
                MacPlayerSlider(
                    value: $volume, range: 0...1, label: "音量", identifier: "player-volume"
                ) { editing in
                    overlay.setGestureInteraction(active: editing)
                    overlay.reveal()
                }
                .frame(width: 92, height: 24)
                .onChange(of: volume) { _, value in
                    session.playback.player.volume = Float(value)
                    muted = false
                    session.playback.player.isMuted = false
                }
            }
            .disabled(session.playback.state != .ready)
        }

        private var options: some View {
            HStack(spacing: 4) {
                PlayerSpeedMenu(
                    playback: session.playback, speed: snapshot?.speed ?? 1, overlay: overlay)
                if session.details?.isLocal == false {
                    PlayerQualityMenu(
                        session: session, quality: snapshot?.quality, overlay: overlay)
                }
                MacPlayerRoutePicker(playback: session.playback, overlay: overlay)
                    .frame(width: 36, height: 36).help("投屏")
                button(
                    presentation.pictureInPicture ? "退出画中画" : "画中画",
                    symbol: presentation.pictureInPicture ? "pip.exit" : "pip.enter",
                    id: "player-pip"
                ) {
                    presentation.togglePictureInPicture()
                }.disabled(!presentation.pictureInPicturePossible && !presentation.pictureInPicture)
                button(
                    presentation.fullscreen ? "退出全屏" : "全屏",
                    symbol: presentation.fullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right", id: "player-fullscreen"
                ) {
                    presentation.toggleFullscreen()
                }
            }.font(.system(size: 14, weight: .medium))
        }

        private func button(
            _ title: String, symbol: String, id: String, size: CGFloat = 20, width: CGFloat = 36,
            action: @escaping () -> Void
        ) -> some View {
            Button {
                overlay.reveal()
                action()
            } label: {
                Image(systemName: symbol).font(.system(size: size, weight: .medium))
                    .frame(width: width, height: 44).contentShape(Rectangle())
            }
            .help(title).accessibilityLabel(title).accessibilityIdentifier(id)
        }

        private func togglePlayback() {
            guard let current = session.playback.capture() else { return }
            overlay.reveal()
            if current.ended {
                seek(to: 0, resume: true)
                presentation.showFeedback("播放", symbol: "play.fill")
            } else {
                let pause = current.playIntent == .playing
                session.playback.setPlaybackIntent(pause ? .paused : .playing)
                presentation.showFeedback(
                    pause ? "暂停" : "播放", symbol: pause ? "pause.fill" : "play.fill")
            }
        }

        private func skip(by delta: Int64) {
            guard let current = session.playback.capture(), let duration = current.durationMs else {
                return
            }
            let target = min(
                duration, max(0, (overlay.previewMilliseconds ?? current.positionMs) + delta))
            seek(to: target)
            presentation.showFeedback(
                "\(delta > 0 ? "快进" : "快退") 10 秒",
                symbol: delta > 0 ? "goforward.10" : "gobackward.10")
        }

        private func adjustVolume(by delta: Double) {
            let player = session.playback.player
            volume = min(1, max(0, (player.isMuted ? 0 : Double(player.volume)) + delta))
            player.volume = Float(volume)
            player.isMuted = false
            muted = false
            overlay.reveal()
            presentation.showFeedback(
                "音量 \(Int((volume * 100).rounded()))%",
                symbol: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }

        private func seek(to target: Int64, resume: Bool = false) {
            // Record the explicit play action now; a later pause must win while seeking.
            if resume { session.playback.setPlaybackIntent(.playing) }
            session.playback.seekInteraction.seek(to: target, owner: seekOwner, overlay: overlay) {
                try await session.playback.seek(to: target)
            } onFailure: { error in
                session.warning = error.localizedDescription
            }
        }

        private func timestamp(_ milliseconds: Int64) -> String {
            let seconds = max(0, milliseconds / 1000)
            if seconds >= 3600 {
                return String(
                    format: "%lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
            }
            return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
        }
    }
#endif
