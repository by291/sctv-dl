import SCTVCore
import SCTVMedia
import SwiftUI

struct MediaProbeView: View {
    @State private var playback: PlaybackCoordinator = {
        #if DEBUG
            PlaybackCoordinator(transport: FixtureMediaTransport())
        #else
            PlaybackCoordinator()
        #endif
    }()
    @State private var message = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("媒体验证").font(.title2.bold())
                #if os(iOS)
                    IOSPlayerView(playback: playback)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                #else
                    MacPlayerView(playback: playback)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                #endif

                switch playback.state {
                case .idle: Text("使用本地合成视频验证原生播放")
                case .preparing: ProgressView("准备中")
                case .ready: Text("准备就绪").accessibilityIdentifier("player-ready")
                case .failed(let error): Text(error).foregroundStyle(.red)
                }
                #if DEBUG
                    HStack {
                        Button("载入测试视频") { Task { await openFixture() } }
                        Button("跳至 8 秒") { Task { await seekFixture() } }
                            .disabled(playback.state != .ready)
                    }
                #endif
                if !message.isEmpty { Text(message).accessibilityIdentifier("probe-message") }
            }
            .padding()
            .navigationTitle("SCTV")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { playback.pauseForBackground() }
        }
        .onDisappear {
            playback.beginDismissal()
            Task { await playback.finishDismissal() }
        }
    }

    private func openFixture() async {
        do {
            let content = try ContentRef(programmeID: "1", dateID: "2", contentID: "3")
            let source = try MediaSource(
                url: URL(string: "https://fscgc.scgchc.com/probe.mp4")!, quality: .standard,
                productVersion: "0.1.0")
            _ = try await playback.open(
                PlaybackRequest(
                    content: content, title: "合成视频", sources: [source], quality: .standard,
                    resumeMilliseconds: 3000))
        } catch { message = error.localizedDescription }
    }

    private func seekFixture() async {
        do {
            try await playback.seek(to: 8000)
            message = "已定位至 8 秒"
        } catch { message = error.localizedDescription }
    }
}
