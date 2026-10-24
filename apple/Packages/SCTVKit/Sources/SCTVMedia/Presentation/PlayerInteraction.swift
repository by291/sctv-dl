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
    public var previewMilliseconds: Int64?
    public var isInteracting: Bool {
        get { interactionActive || !presentedOptions.isEmpty }
        set { interactionActive = newValue }
    }
    var hasPresentedOptions: Bool { !presentedOptions.isEmpty }
    private var interactionActive = false
    private var presentedOptions: Set<String> = []
    public private(set) var activity = 0
    public private(set) var fullscreen = false
    public private(set) var orientationRequest = 0
    private var seekPreviewToken: UUID?
    public init() {}

    func beginSeekPreview(at position: Int64) -> UUID {
        let token = UUID()
        seekPreviewToken = token
        previewMilliseconds = position
        isInteracting = true
        return token
    }

    func finishSeekPreview(_ token: UUID) {
        guard seekPreviewToken == token else { return }
        seekPreviewToken = nil
        previewMilliseconds = nil
        isInteracting = false
        reveal()
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
