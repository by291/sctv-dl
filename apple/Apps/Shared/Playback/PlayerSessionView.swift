import SCTVCore
import SCTVFeatures
import SCTVMedia
import SwiftUI

struct PlayerSessionView: View {
    let session: PlayerSession
    let presentationID: UUID
    var download: (() async -> String)? = nil

    @State private var snapshot: PlaybackSnapshot?
    @State private var downloadMessage: String?
    @State private var downloading = false
    @State private var overlay = PlayerOverlayState()
    @State private var titleExpanded = false
    #if os(macOS)
        @State private var macPresentation = MacPlayerPresentation()
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var videoOnly: Bool {
        #if os(iOS)
            overlay.fullscreen || verticalSizeClass == .compact
        #else
            macPresentation.fullscreen
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900 && !typeSize.isAccessibilitySize && !videoOnly
            let layout =
                wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                video
                    .frame(width: wide ? geometry.size.width * 0.66 : geometry.size.width)
                    .frame(
                        height: wide || videoOnly
                            ? geometry.size.height
                            : min(geometry.size.width * 9 / 16, geometry.size.height * 0.58)
                    )
                    .background(.black)
                if !videoOnly {
                    ScrollView {
                        details.padding(24).frame(maxWidth: 760, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(videoOnly ? Color.black : PresentationStyle.canvas(scheme))
        .tint(PresentationStyle.accent(scheme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            session.playback.state == .ready ? "native-player-ready" : "native-player"
        )
        .navigationTitle("")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(videoOnly)
            .background(PlayerBackGesture(enabled: !videoOnly))
        #endif
        #if os(macOS)
            .ignoresSafeArea(.container, edges: macPresentation.fullscreen ? .top : [])
            .onChange(of: macPresentation.error) { _, value in
                if let value {
                    session.reportWarning(value, forPresentation: presentationID)
                }
            }
        #endif
        .task(id: session.presentationID) {
            downloadMessage = nil
            titleExpanded = false
            overlay.reveal()
            snapshot = session.playback.capture()
            for await value in session.playback.snapshots() {
                guard !Task.isCancelled else { break }
                snapshot = value
            }
        }
        .onChange(of: phase) { _, value in
            if value == .background {
                #if os(macOS)
                    session.playback.pauseForBackground()
                #endif
                Task { await session.recorder.flush(session.playback) }
            }
        }
    }

    private var video: some View {
        ZStack {
            #if os(iOS)
                IOSPlayerView(
                    playback: session.playback, overlay: overlay, presentationID: presentationID)
                PlayerControlsView(
                    session: session, snapshot: snapshot, overlay: overlay, fullscreen: videoOnly,
                    presentationID: presentationID
                ) {
                    session.playback.pauseForInterruption()
                    dismiss()
                }
            #else
                MacPlayerView(
                    playback: session.playback, presentation: macPresentation, overlay: overlay,
                    presentationID: presentationID
                )
                .id(presentationID)
                .onTapGesture(count: 2) {
                    overlay.reveal()
                    macPresentation.toggleFullscreen()
                }
                .onContinuousHover { phase in
                    if case .active = phase { overlay.reveal() }
                }
                .overlay { MacPlayerFeedbackView(presentation: macPresentation) }
                .overlay(alignment: .bottom) {
                    MacPlayerControlsView(
                        session: session, snapshot: snapshot, overlay: overlay,
                        presentation: macPresentation, presentationID: presentationID)
                }
            #endif
            if case .preparing = session.playback.state {
                ProgressView("正在准备播放")
                    .tint(.white).foregroundStyle(.white)
                    .padding(18).background(
                        .black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            }
            if case .failed(let message) = session.playback.state {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle").font(.title)
                    Text(message).font(.callout).multilineTextAlignment(.center)
                    Button("重试播放") {
                        Task {
                            await session.retry(forPresentation: presentationID)
                        }
                    }.buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white).padding(24)
                .frame(maxWidth: 420).background(
                    .black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let metadata = session.details {
                Label(
                    metadata.isLocal ? "本地视频" : "正在观看",
                    systemImage: metadata.isLocal ? "internaldrive" : "play.rectangle"
                )
                .font(.caption.weight(.semibold)).foregroundStyle(PresentationStyle.accent(scheme))
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        titleExpanded.toggle()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metadata.title)
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .lineLimit(titleExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(titleExpanded ? "收起标题" : "展开标题")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(metadata.title)
                .accessibilityValue(titleExpanded ? "已展开" : "已收起")
                .accessibilityHint(titleExpanded ? "点击收起标题" : "点击展开完整标题")
                .accessibilityIdentifier("player-title-disclosure")
                Text(
                    [metadata.programmeName, metadata.broadcastDate].filter { !$0.isEmpty }.joined(
                        separator: " · ")
                )
                .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                if metadata.resumeMilliseconds > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("上次看到 \(PlaybackTimeText.format(metadata.resumeMilliseconds))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("从头播放", systemImage: "arrow.counterclockwise") {
                            Task {
                                await session.rewind(forPresentation: presentationID)
                            }
                        }.buttonStyle(.bordered)
                    }
                }
                if !metadata.isLocal, let download {
                    Button {
                        let token = session.presentationID
                        downloading = true
                        Task {
                            let result = await download()
                            downloading = false
                            if session.presentationID == token { downloadMessage = result }
                        }
                    } label: {
                        Label(downloading ? "正在添加下载" : "下载节目", systemImage: "arrow.down.to.line")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(
                        .roundedRectangle(radius: 14)
                    )
                    .disabled(downloading)
                }
                if let downloadMessage {
                    Text(downloadMessage).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("正在载入节目信息")
            }
            if let warning = session.recorder.warning ?? session.warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

}
