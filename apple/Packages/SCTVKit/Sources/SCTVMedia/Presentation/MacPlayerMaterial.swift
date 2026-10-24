#if os(macOS)
    import SwiftUI

    /// Samples the video in this window rather than the desktop behind the player.
    struct MacPlayerMaterial: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .hudWindow
            view.appearance = NSAppearance(named: .vibrantDark)
            view.blendingMode = .withinWindow
            view.state = .active
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
#endif
