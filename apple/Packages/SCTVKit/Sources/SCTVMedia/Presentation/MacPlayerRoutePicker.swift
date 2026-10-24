#if os(macOS)
    import AVKit
    import SwiftUI

    struct MacPlayerRoutePicker: NSViewRepresentable {
        let playback: PlaybackCoordinator
        let overlay: PlayerOverlayState

        func makeNSView(context: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.player = playback.player
            view.isRoutePickerButtonBordered = false
            view.setRoutePickerButtonColor(.white, for: .normal)
            view.setRoutePickerButtonColor(.white, for: .normalHighlighted)
            view.delegate = context.coordinator
            view.setAccessibilityLabel("投屏")
            view.setAccessibilityIdentifier("player-airplay")
            return view
        }
        func updateNSView(_ view: AVRoutePickerView, context: Context) {}
        func makeCoordinator() -> Delegate { Delegate(overlay: overlay) }
        static func dismantleNSView(_ view: AVRoutePickerView, coordinator: Delegate) {
            view.delegate = nil
            view.player = nil
            coordinator.overlay.setOptionsPresented(false, id: "airplay")
        }
        @MainActor final class Delegate: NSObject, @preconcurrency AVRoutePickerViewDelegate {
            let overlay: PlayerOverlayState
            init(overlay: PlayerOverlayState) { self.overlay = overlay }
            func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
                overlay.setOptionsPresented(true, id: "airplay")
            }
            func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
                overlay.setOptionsPresented(false, id: "airplay")
            }
        }
    }
#endif
