#if os(macOS)
    import SwiftUI

    /// One window-scoped keyboard owner, independent of alternative control-bar layouts.
    struct MacPlayerKeyboard: NSViewRepresentable {
        var enabled: Bool
        var action: (Command) -> Void

        enum Command {
            case togglePlayback, backward, forward, volumeUp, volumeDown, fullscreen
        }

        func makeNSView(context: Context) -> KeyboardView { KeyboardView() }
        func updateNSView(_ view: KeyboardView, context: Context) {
            view.enabled = enabled
            view.action = action
        }
        static func dismantleNSView(_ view: KeyboardView, coordinator: ()) { view.stopMonitoring() }

        final class KeyboardView: NSView {
            var enabled = false
            var action: (Command) -> Void = { _ in }
            private var monitor: Any?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stopMonitoring()
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    [weak self] event in
                    let handled = MainActor.assumeIsolated { self?.handle(event) == true }
                    return handled ? nil : event
                }
            }

            func stopMonitoring() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            private func handle(_ event: NSEvent) -> Bool {
                guard enabled, let window, window.isKeyWindow, event.window === window,
                    event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                    !(window.firstResponder is NSTextView)
                else { return false }
                let command: Command
                switch event.keyCode {
                case 49: command = .togglePlayback
                case 123: command = .backward
                case 124: command = .forward
                case 125: command = .volumeDown
                case 126: command = .volumeUp
                default:
                    guard event.charactersIgnoringModifiers?.lowercased() == "f" else {
                        return false
                    }
                    command = .fullscreen
                }
                // Holding an arrow repeats its adjustment; holding Space must not oscillate playback.
                if !event.isARepeat || (command != .togglePlayback && command != .fullscreen) {
                    action(command)
                }
                return true
            }
        }
    }
#endif
