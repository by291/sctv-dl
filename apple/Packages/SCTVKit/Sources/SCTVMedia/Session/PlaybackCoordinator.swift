@preconcurrency import AVFoundation
import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class PlaybackCoordinator: PlaybackService {
    public enum State: Equatable {
        case idle, preparing, ready
        case failed(String)
    }
    public let player = AVPlayer()
    public private(set) var state = State.idle

    private let transport: any MediaRangeTransport
    private var request: PlaybackRequest?
    private var sessionID: UUID?
    private var generation: UInt64 = 0
    private var loader: AssetResourceLoader?
    private var observation: PlaybackObservation?
    #if os(iOS)
        private var audioSession: IOSPlaybackAudioSession?
    #endif
    private var quality = VideoQuality.standard
    private var speed = 1.0
    private var intent = PlaybackIntent.paused
    private var settled = false
    private var ended = false
    private var dismissing = false
    private var pictureInPicture = false
    private var lastSnapshot: PlaybackSnapshot?
    private var subscribers: [UUID: AsyncStream<PlaybackSnapshot>.Continuation] = [:]

    public init(transport: any MediaRangeTransport = URLSessionRangeTransport()) {
        self.transport = transport
    }

    isolated deinit {
        observation?.dispose()
        loader?.cancelAll()
        #if os(iOS)
            audioSession?.dispose()
        #endif
        for continuation in subscribers.values { continuation.finish() }
    }

    public func open(_ request: PlaybackRequest) async throws -> UUID {
        #if os(iOS)
            if audioSession == nil {
                audioSession = IOSPlaybackAudioSession { [weak self] in
                    self?.pauseForInterruption()
                }
            }
        #endif
        if self.request?.content == request.content, let sessionID, !dismissing { return sessionID }
        disposeItem()
        self.request = request
        let id = UUID()
        sessionID = id
        lastSnapshot = nil
        dismissing = false
        pictureInPicture = false
        intent = .paused
        speed = request.speed
        try await replaceSource(request.quality, positionMs: request.resumeMilliseconds)
        return id
    }

    public func setPlaybackIntent(_ intent: PlaybackIntent) {
        guard request != nil, !dismissing else { return }
        // Preparation delays playback, but must never discard a newer pause request.
        self.intent = intent
        if intent == .playing, settled {
            player.playImmediately(atRate: Float(speed))
        } else {
            player.pause()
        }
        emitSnapshot()
    }

    public func setSpeed(_ speed: Double) {
        guard speed.isFinite, speed > 0, speed <= 4 else { return }
        self.speed = speed
        if intent == .playing, settled, !dismissing { player.rate = Float(speed) }
        emitSnapshot()
    }

    public func seek(to milliseconds: Int64) async throws {
        guard settled, let item = player.currentItem else { return }
        let token = generation
        settled = false
        let target = min(
            max(0, Double(milliseconds) / 1000), validDuration(item) ?? .greatestFiniteMagnitude)
        let completed = await player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
            toleranceAfter: .zero)
        guard generation == token else { throw CancellationError() }
        // A native scrub can interrupt this seek without replacing the usable item.
        settled = item.status == .readyToPlay
        guard completed, !dismissing else {
            emitSnapshot()
            throw CancellationError()
        }
        ended = false
        emitSnapshot(.seek)
    }

    public func switchQuality(_ quality: VideoQuality) async throws {
        let position = capture()?.positionMs ?? lastSnapshot?.positionMs ?? 0
        try await replaceSource(quality, positionMs: position)
    }

    public func retry() async throws {
        try await replaceSource(quality, positionMs: lastSnapshot?.positionMs ?? 0)
    }

    public func capture() -> PlaybackSnapshot? {
        guard let sessionID else { return nil }
        guard settled else { return lastUsableSnapshot() }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int64.max) / 1000 else {
            return lastUsableSnapshot()
        }
        let duration = player.currentItem.flatMap(validDuration)
        return PlaybackSnapshot(
            sessionID: sessionID, positionMs: Int64(seconds * 1000),
            durationMs: duration.map { Int64($0 * 1000) }, quality: quality, speed: speed,
            playIntent: intent, settled: true, ended: ended)
    }

    public func beginDismissal() {
        dismissing = true
        if !pictureInPicture {
            intent = .paused
            player.pause()
            emitSnapshot()
        }
    }

    public func cancelDismissal() { dismissing = false }

    public func setPictureInPictureActive(_ active: Bool) { pictureInPicture = active }

    public func pauseForInterruption() {
        intent = .paused
        player.pause()
        emitSnapshot()
    }

    public func pauseForBackground() {
        guard !pictureInPicture else { return }
        pauseForInterruption()
    }

    public func finishDismissal() async {
        guard dismissing, !pictureInPicture else { return }
        disposeItem()
        #if os(iOS)
            let audioDisposal = audioSession?.dispose()
            audioSession = nil
        #endif
        request = nil
        sessionID = nil
        lastSnapshot = nil
        state = .idle
        #if os(iOS)
            // Commit cleanup before suspension: a replacement may open while audio drains.
            // Deactivation is best effort and cannot restore an already disposed player.
            _ = try? await audioDisposal?.value
        #endif
    }

    public func snapshots() -> AsyncStream<PlaybackSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            subscribers[id] = continuation
            if let snapshot = capture() { continuation.yield(snapshot) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.subscribers.removeValue(forKey: id) }
            }
        }
    }

    private func replaceSource(_ desiredQuality: VideoQuality, positionMs: Int64) async throws {
        guard let request, !dismissing else { throw QualityResolver.ResolutionError.unavailable }
        let source =
            request.sources.first(where: { $0.quality == desiredQuality })
            ?? request.sources.first
        guard request.localFile != nil || source != nil else {
            throw QualityResolver.ResolutionError.unavailable
        }
        lastSnapshot = capture()
        disposeItem()
        let token = generation
        quality = request.localFile == nil ? (source?.quality ?? request.quality) : request.quality
        state = .preparing

        do {
            #if os(iOS)
                try await audioSession?.prepare()
                guard generation == token, !dismissing else { throw CancellationError() }
            #endif
            let asset: AVURLAsset
            if let lease = request.localFile {
                // A local intent remains local even when an online source is available.
                guard FileManager.default.isReadableFile(atPath: lease.url.path) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                asset = AVURLAsset(url: lease.url)
            } else if let source {
                let loader = AssetResourceLoader(transport: transport)
                self.loader = loader
                asset = try loader.makeAsset(source: source)
            } else {
                throw QualityResolver.ResolutionError.unavailable
            }
            let item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while item.status != .readyToPlay {
                try Task.checkCancellation()
                guard generation == token, !dismissing else { throw CancellationError() }
                if item.status == .failed {
                    throw item.error ?? MediaTransportError.invalidResponse
                }
                guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard generation == token, !dismissing else { throw CancellationError() }
            let target = min(Double(positionMs) / 1000, validDuration(item) ?? 0)
            let completed = await player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
                toleranceAfter: .zero)
            guard completed, generation == token, !dismissing else { throw CancellationError() }

            settled = true
            ended = false
            state = .ready
            observation = PlaybackObservation(player: player, item: item) { [weak self] event in
                guard let self, generation == token else { return }
                switch event {
                case .playbackChanged(let isPlaying, let actualSpeed):
                    if dismissing && !pictureInPicture {
                        player.pause()
                        intent = .paused
                    } else {
                        intent = isPlaying ? .playing : .paused
                        if isPlaying { speed = actualSpeed }
                    }
                    emitSnapshot()
                case .sample: emitSnapshot()
                case .ended:
                    ended = true
                    intent = .paused
                    emitSnapshot()
                case .failed(let message):
                    lastSnapshot = capture()
                    disposeItem()
                    state = .failed(message)
                }
            }
            if intent == .playing { player.playImmediately(atRate: Float(speed)) }
            emitSnapshot()
        } catch {
            if generation == token {
                // Preparation owns its loader even when the calling task is cancelled.
                disposeItem()
                state = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    private func validDuration(_ item: AVPlayerItem) -> Double? {
        let duration = item.duration.seconds
        return duration.isFinite && duration > 0 && duration < Double(Int64.max) / 1000
            ? duration : nil
    }

    private func lastUsableSnapshot() -> PlaybackSnapshot? {
        guard let previous = lastSnapshot else { return nil }
        // Position stays frozen during source replacement, but revoked playback intent is current.
        return PlaybackSnapshot(
            sessionID: previous.sessionID, positionMs: previous.positionMs,
            durationMs: previous.durationMs, quality: previous.quality, speed: speed,
            playIntent: intent, settled: previous.settled, ended: previous.ended)
    }

    private func emitSnapshot(_ reason: PlaybackSampleReason = .progress) {
        guard let current = capture() else { return }
        let snapshot = PlaybackSnapshot(
            sessionID: current.sessionID, positionMs: current.positionMs,
            durationMs: current.durationMs,
            quality: current.quality, speed: current.speed, playIntent: current.playIntent,
            settled: current.settled, ended: current.ended, reason: reason)
        lastSnapshot = snapshot
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    private func disposeItem() {
        generation &+= 1
        settled = false
        observation?.dispose()
        observation = nil
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        loader?.cancelAll()
        loader = nil
    }
}
