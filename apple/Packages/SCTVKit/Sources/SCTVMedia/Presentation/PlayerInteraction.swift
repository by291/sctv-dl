import Foundation
import Observation

enum PlayerInteraction {
    static func seek(position: Int64, duration: Int64, delta: Double, width: Double) -> Int64 {
        guard width > 0, delta.isFinite, duration > 0 else { return position }
        let span = min(Double(duration), 120_000)
        return Int64(min(Double(duration), max(0, Double(position) + delta / width * span)))
    }

    static func level(initial: Double, delta: Double, height: Double) -> Double {
        guard height > 0, delta.isFinite else { return initial }
        return min(1, max(0, initial - delta / height))
    }
}

@MainActor @Observable
public final class PlayerOverlayState {
    public var controlsVisible = true
    public var hint: String?
    public private(set) var previewMilliseconds: Int64?
    public private(set) var activity = 0
    public private(set) var fullscreen = false
    public private(set) var orientationRequest = 0

    private var gestureActive = false
    private var presentedOptions: Set<String> = []
    private var seekPreviewToken: UUID?

    /// Options, gestures and pending seeks independently keep controls visible.
    public var isInteracting: Bool {
        gestureActive || seekPreviewToken != nil || !presentedOptions.isEmpty
    }

    var hasPresentedOptions: Bool { !presentedOptions.isEmpty }

    public init() {}

    func beginSeekPreview(at position: Int64) -> UUID {
        let token = UUID()
        seekPreviewToken = token
        previewMilliseconds = position
        return token
    }

    func updateSeekPreview(at position: Int64, token: UUID) {
        guard seekPreviewToken == token else { return }
        previewMilliseconds = position
    }

    func finishSeekPreview(_ token: UUID) {
        guard seekPreviewToken == token else { return }
        seekPreviewToken = nil
        previewMilliseconds = nil
        reveal()
    }

    public func setGestureInteraction(active: Bool) {
        gestureActive = active
    }

    public func reveal() {
        controlsVisible = true
        activity &+= 1
    }

    func setOptionsPresented(_ presented: Bool, id: String) {
        if presented { presentedOptions.insert(id) } else { presentedOptions.remove(id) }
        reveal()
    }

    func hideIfIdle(activity expected: Int, playing: Bool, pinned: Bool) {
        guard activity == expected, playing, !isInteracting, !pinned else { return }
        controlsVisible = false
    }

    public func requestFullscreen(_ value: Bool) {
        fullscreen = value
        orientationRequest &+= 1
        reveal()
    }
}
