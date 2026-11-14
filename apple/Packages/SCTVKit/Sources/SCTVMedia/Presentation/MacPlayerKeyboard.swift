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
            private enum Key: UInt16 {
                case space = 49
                case leftArrow = 123
                case rightArrow = 124
                case downArrow = 125
                case upArrow = 126
            }

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
                switch Key(rawValue: event.keyCode) {
                case .space: command = .togglePlayback
                case .leftArrow: command = .backward
                case .rightArrow: command = .forward
                case .downArrow: command = .volumeDown
                case .upArrow: command = .volumeUp
                case nil:
                    guard event.charactersIgnoringModifiers?.lowercased() == "f" else {
                        return false
                    }
                    command = .fullscreen
                }
                // Repeat arrow adjustments, while Space and F react once per key press.
                if !event.isARepeat || (command != .togglePlayback && command != .fullscreen) {
                    action(command)
                }
                return true
            }
        }
    }
#endif
