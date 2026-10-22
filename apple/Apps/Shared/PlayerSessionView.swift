import SCTVCore
import SCTVMedia
import SwiftUI

struct PlayerSessionView: View {
    let session: PlayerSession
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 12) {
            #if os(iOS)
                IOSPlayerView(playback: session.playback).aspectRatio(16.0 / 9.0, contentMode: .fit)
            #else
                MacPlayerView(playback: session.playback)
            #endif
            if case .preparing = session.playback.state { ProgressView("正在准备播放") }
            if case .failed(let message) = session.playback.state {
                Text(message).foregroundStyle(.secondary)
                Button("重试播放") {
                    Task {
                        do { try await session.playback.retry() } catch {
                            session.warning = error.localizedDescription
                        }
                    }
                }
            }
            if let warning = session.recorder.warning ?? session.warning {
                Text(warning).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            session.playback.state == .ready ? "native-player-ready" : "native-player"
        )
        .navigationTitle(session.title)
        .toolbar {
            Menu("画质与速度", systemImage: "slider.horizontal.3") {
                Button("标准画质") { changeQuality(.standard) }
                Button("流畅画质") { changeQuality(.smooth) }
                Divider()
                ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                    Button("\(speed.formatted()) 倍速") { session.playback.setSpeed(speed) }
                }
            }
        }
        .onChange(of: phase) { _, value in
            if value == .background {
                session.playback.pauseForBackground()
                Task { await session.recorder.flush(session.playback) }
            }
        }
    }

    private func changeQuality(_ quality: VideoQuality) {
        Task {
            do { try await session.playback.switchQuality(quality) } catch {
                session.warning = error.localizedDescription
            }
        }
    }
}
