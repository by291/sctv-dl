import SCTVCore
import SwiftUI

public struct PlayerControlsView: View {
    let session: PlayerSession
    let snapshot: PlaybackSnapshot?
    let overlay: PlayerOverlayState
    let fullscreen: Bool
    let back: () -> Void
    @State private var scrubPosition = 0.0
    @State private var scrubbing = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    public init(
        session: PlayerSession, snapshot: PlaybackSnapshot?, overlay: PlayerOverlayState,
        fullscreen: Bool, back: @escaping () -> Void
    ) {
        self.session = session
        self.snapshot = snapshot
        self.overlay = overlay
        self.fullscreen = fullscreen
        self.back = back
    }

    private var playing: Bool { snapshot?.playIntent == .playing }
    private var position: Int64 {
        overlay.previewMilliseconds
            ?? (scrubbing
                ? Int64(scrubPosition)
                : session.playback.capture()?.positionMs ?? snapshot?.positionMs ?? 0)
    }
    private var duration: Int64 { max(1, snapshot?.durationMs ?? 1) }

    public var body: some View {
        ZStack {
            if overlay.controlsVisible || voiceOver {
                LinearGradient(
                    colors: [.black.opacity(0.6), .clear, .black.opacity(0.65)], startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        control(
                            fullscreen ? "退出全屏" : "返回", symbol: "chevron.left", id: "player-back"
                        ) {
                            if fullscreen { overlay.requestFullscreen(false) } else { back() }
                        }
                        Spacer(minLength: 0)
                        if !fullscreen { options }
                        #if os(iOS)
                            PlayerRoutePicker().frame(width: 44, height: 44)
                                .accessibilityLabel("投屏")
                                .accessibilityIdentifier("player-airplay")
                        #endif
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Text(timestamp(position)).font(.caption.monospacedDigit())
                        Slider(
                            value: Binding(
                                get: { scrubbing ? scrubPosition : Double(position) },
                                set: { scrubPosition = $0 }), in: 0...Double(duration)
                        ) { editing in
                            if editing {
                                scrubPosition = Double(snapshot?.positionMs ?? 0)
                                scrubbing = true
                                overlay.isInteracting = true
                                overlay.reveal()
                            } else {
                                let target = Int64(scrubPosition)
                                // Hold the released thumb until AVPlayer has accepted the seek.
                                let token = overlay.beginSeekPreview(at: target)
                                scrubbing = false
                                overlay.reveal()
                                Task {
                                    defer { overlay.finishSeekPreview(token) }
                                    do { try await session.playback.seek(to: target) } catch {
                                        session.warning = error.localizedDescription
                                    }
                                }
                            }
                        }
                        .disabled(
                            snapshot?.durationMs == nil || session.playback.state != .ready
                                || (!scrubbing && overlay.previewMilliseconds != nil)
                        )
                        .accessibilityLabel("播放进度")
                        .accessibilityValue("\(timestamp(position))，共 \(timestamp(duration))")
                        .accessibilityIdentifier("player-progress")
                        Text(timestamp(duration)).font(.caption.monospacedDigit())
                        if fullscreen { options }
                        control(
                            fullscreen ? "退出全屏" : "全屏",
                            symbol: fullscreen
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right", id: "player-fullscreen"
                        ) {
                            overlay.requestFullscreen(!fullscreen)
                        }
                    }
                }
                .padding(.horizontal, fullscreen ? 20 : 8)
                .padding(.vertical, 4)
                if session.playback.state == .ready, !overlay.isInteracting {
                    Button {
                        overlay.reveal()
                        if snapshot?.ended == true {
                            Task {
                                do {
                                    try await session.playback.seek(to: 0)
                                    session.playback.setPlaybackIntent(.playing)
                                } catch { session.warning = error.localizedDescription }
                            }
                        } else {
                            session.playback.setPlaybackIntent(playing ? .paused : .playing)
                        }
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .medium))
                            .frame(width: 64, height: 64)
                            .background(.black.opacity(0.3), in: Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(playing ? "暂停" : "播放")
                    .accessibilityIdentifier("player-toggle-play")
                }
            }
            if let hint = overlay.hint {
                Text(hint).font(.headline.monospacedDigit())
                    .padding(12).background(.black.opacity(0.7), in: Capsule())
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("player-gesture-hint")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white).tint(.white)
        .task(id: overlay.activity) {
            guard playing, !voiceOver else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            if !overlay.isInteracting { overlay.controlsVisible = false }
        }
        .onChange(of: playing) { _, _ in overlay.reveal() }
        .task(id: overlay.hint) {
            guard overlay.hint != nil, !overlay.isInteracting else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            overlay.hint = nil
        }
    }

    private var options: some View {
        Group {
            PlayerSpeedMenu(
                playback: session.playback, speed: snapshot?.speed ?? 1, overlay: overlay)
            if let details = session.details, !details.isLocal {
                PlayerQualityMenu(session: session, quality: snapshot?.quality, overlay: overlay)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func control(_ title: String, symbol: String, id: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel(title).accessibilityIdentifier(id)
    }

    private func timestamp(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1000)
        if seconds >= 3600 {
            return String(
                format: "%lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%lld:%02lld", seconds / 60, seconds % 60)
    }
}

public struct PlayerSpeedMenu: View {
    let playback: PlaybackCoordinator
    let speed: Double
    let overlay: PlayerOverlayState?
    public init(playback: PlaybackCoordinator, speed: Double, overlay: PlayerOverlayState? = nil) {
        self.playback = playback
        self.speed = speed
        self.overlay = overlay
    }
    public var body: some View {
        PlayerOptionsPopover(
            title: "倍速", value: "\(speed.formatted())×", identifier: "player-speed",
            options: [0.75, 1, 1.25, 1.5, 2], selected: speed, name: { "\($0.formatted()) 倍速" },
            overlay: overlay
        ) { playback.setSpeed($0) }
        .accessibilityValue("\(speed.formatted()) 倍")
    }
}

public struct PlayerQualityMenu: View {
    let session: PlayerSession
    let quality: VideoQuality?
    let overlay: PlayerOverlayState?
    public init(session: PlayerSession, quality: VideoQuality?, overlay: PlayerOverlayState? = nil)
    {
        self.session = session
        self.quality = quality
        self.overlay = overlay
    }
    public var body: some View {
        PlayerOptionsPopover(
            title: "清晰度", value: name(quality ?? .standard), identifier: "player-quality",
            options: session.details?.sources.map(\.quality) ?? [], selected: quality ?? .standard,
            name: name, overlay: overlay
        ) { next in
            guard quality != next else { return }
            Task {
                do { try await session.playback.switchQuality(next) } catch {
                    session.warning = error.localizedDescription
                }
            }
        }
        .accessibilityValue(name(quality ?? .standard))
    }
    private func name(_ quality: VideoQuality) -> String { quality == .standard ? "标准" : "流畅" }
}

private struct PlayerOptionsPopover<Option: Hashable>: View {
    let title: String
    let value: String
    let identifier: String
    let options: [Option]
    let selected: Option
    let name: (Option) -> String
    let overlay: PlayerOverlayState?
    let select: (Option) -> Void
    @State private var presented = false

    var body: some View {
        Button {
            presented = true
        } label: {
            Text(value).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(title).accessibilityIdentifier(identifier)
        .popover(isPresented: $presented) {
            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        select(option)
                        presented = false
                    } label: {
                        HStack(spacing: 20) {
                            Text(name(option))
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                                .opacity(selected == option ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name(option))
                    .accessibilityAddTraits(selected == option ? .isSelected : [])
                }
            }
            .font(.body).foregroundStyle(Color.primary)
            .padding(8).frame(minWidth: 190)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: presented) { _, value in
            overlay?.isInteracting = value
            overlay?.reveal()
        }
        .onDisappear {
            if presented { overlay?.isInteracting = false }
        }
    }
}
