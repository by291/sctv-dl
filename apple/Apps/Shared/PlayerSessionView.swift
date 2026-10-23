import SCTVCore
import SCTVFeatures
import SCTVMedia
import SwiftUI

struct PlayerSessionView: View {
    let session: PlayerSession
    var download: (() async -> String)? = nil
    @State private var snapshot: PlaybackSnapshot?
    @State private var downloadMessage: String?
    @State private var downloading = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var videoOnly: Bool {
        #if os(iOS)
            verticalSizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let wide =
                geometry.size.width >= 900 && !typeSize.isAccessibilitySize && !videoOnly
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
        .background(PresentationStyle.canvas(scheme))
        .tint(PresentationStyle.accent(scheme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            session.playback.state == .ready ? "native-player-ready" : "native-player"
        )
        .navigationTitle("播放")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(videoOnly ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(PresentationStyle.canvas(scheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .task(id: session.presentationID) {
            downloadMessage = nil
            snapshot = session.playback.capture()
            for await value in session.playback.snapshots() {
                guard !Task.isCancelled else { break }
                snapshot = value
            }
        }
        .onChange(of: phase) { _, value in
            if value == .background {
                session.playback.pauseForBackground()
                Task { await session.recorder.flush(session.playback) }
            }
        }
    }

    private var video: some View {
        ZStack {
            #if os(iOS)
                IOSPlayerView(playback: session.playback)
            #else
                MacPlayerView(playback: session.playback)
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
                            do { try await session.playback.retry() } catch {
                                session.warning = error.localizedDescription
                            }
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
                Text(metadata.title)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    [metadata.programmeName, metadata.broadcastDate].filter { !$0.isEmpty }.joined(
                        separator: " · ")
                )
                .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { playbackOptions(metadata) }
                    VStack(alignment: .leading, spacing: 12) { playbackOptions(metadata) }
                }
                if metadata.resumeMilliseconds > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("上次看到 \(timestamp(metadata.resumeMilliseconds))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("从头播放", systemImage: "arrow.counterclockwise") {
                            Task {
                                do { try await session.playback.seek(to: 0) } catch {
                                    session.warning = error.localizedDescription
                                }
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

    @ViewBuilder private func playbackOptions(_ metadata: PlayerDetails) -> some View {
        if !metadata.isLocal {
            Menu {
                ForEach(metadata.sources, id: \.quality) { source in
                    Button {
                        changeQuality(source.quality)
                    } label: {
                        if snapshot?.quality == source.quality {
                            Label(qualityName(source.quality), systemImage: "checkmark")
                        } else {
                            Text(qualityName(source.quality))
                        }
                    }
                }
            } label: {
                Label(
                    snapshot.map { qualityName($0.quality) } ?? "选择画质",
                    systemImage: "slider.horizontal.3")
            }.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        Menu {
            ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                Button("\(speed.formatted()) 倍速") { session.playback.setSpeed(speed) }
            }
        } label: {
            Label("\((snapshot?.speed ?? 1).formatted()) 倍速", systemImage: "speedometer")
        }.buttonStyle(.bordered).buttonBorderShape(.capsule)
    }

    private func qualityName(_ quality: VideoQuality) -> String {
        quality == .standard ? "标准画质" : "流畅画质"
    }

    private func timestamp(_ milliseconds: Int64) -> String {
        let seconds = milliseconds / 1000
        if seconds >= 3600 {
            return String(
                format: "%lld:%02lld:%02lld", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%lld:%02lld", seconds / 60, seconds % 60)
    }

    private func changeQuality(_ quality: VideoQuality) {
        guard snapshot?.quality != quality else { return }
        Task {
            do { try await session.playback.switchQuality(quality) } catch {
                session.warning = error.localizedDescription
            }
        }
    }
}
