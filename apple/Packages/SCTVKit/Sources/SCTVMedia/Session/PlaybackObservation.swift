@preconcurrency import AVFoundation
import Foundation

@MainActor
final class PlaybackObservation {
    enum Event {
        case sample, ended
        case failed(String)
        case playbackChanged(Bool, Double)
    }

    private let player: AVPlayer
    private var periodic: Any?
    private var ended: NSObjectProtocol?
    private var status: NSKeyValueObservation?
    private var rate: NSKeyValueObservation?

    init(player: AVPlayer, item: AVPlayerItem, receive: @escaping @MainActor (Event) -> Void) {
        self.player = player
        periodic = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { _ in
            Task { @MainActor in receive(.sample) }
        }
        ended = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in
            Task { @MainActor in receive(.ended) }
        }
        status = item.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "播放失败"
            Task { @MainActor in receive(.failed(message)) }
        }
        rate = player.observe(\.rate, options: [.new]) { player, _ in
            let value = Double(player.rate)
            Task { @MainActor in receive(.playbackChanged(value > 0, value)) }
        }
    }

    func dispose() {
        if let periodic { player.removeTimeObserver(periodic) }
        if let ended { NotificationCenter.default.removeObserver(ended) }
        status?.invalidate()
        rate?.invalidate()
        periodic = nil
        ended = nil
        status = nil
        rate = nil
    }
}
