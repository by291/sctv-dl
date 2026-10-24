#if os(macOS)
    import SwiftUI

    /// Keeps AppKit tracking, keyboard and accessibility behavior with the transport's capsule thumb.
    struct MacPlayerSlider: NSViewRepresentable {
        @Binding var value: Double
        var range: ClosedRange<Double>
        var label: String
        var identifier: String
        var editingChanged: (Bool) -> Void
        @Environment(\.isEnabled) private var enabled

        func makeNSView(context: Context) -> TransportSlider {
            let slider = TransportSlider()
            slider.cell = TransportSliderCell()
            slider.isContinuous = true
            slider.target = context.coordinator
            slider.action = #selector(Delegate.changed(_:))
            slider.editingChanged = editingChanged
            return slider
        }

        func updateNSView(_ slider: TransportSlider, context: Context) {
            context.coordinator.owner = self
            slider.editingChanged = editingChanged
            slider.minValue = range.lowerBound
            slider.maxValue = range.upperBound
            slider.isEnabled = enabled
            if !slider.tracking { slider.doubleValue = value }
            slider.setAccessibilityLabel(label)
            slider.setAccessibilityIdentifier(identifier)
        }

        func makeCoordinator() -> Delegate { Delegate(self) }

        @MainActor final class Delegate: NSObject {
            var owner: MacPlayerSlider
            init(_ owner: MacPlayerSlider) { self.owner = owner }

            @objc func changed(_ slider: TransportSlider) {
                // Accessibility changes may arrive without mouse tracking callbacks.
                if !slider.tracking { owner.editingChanged(true) }
                owner.value = slider.doubleValue
                if !slider.tracking { owner.editingChanged(false) }
            }
        }
    }

    final class TransportSlider: NSSlider {
        var tracking = false
        var editingChanged: (Bool) -> Void = { _ in }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            tracking = true
            editingChanged(true)
            super.mouseDown(with: event)
            tracking = false
            editingChanged(false)
        }
    }

    private final class TransportSliderCell: NSSliderCell {
        override var knobThickness: CGFloat { 24 }

        override func knobRect(flipped: Bool) -> NSRect {
            let rect = super.knobRect(flipped: flipped)
            return NSRect(x: rect.midX - 12, y: rect.midY - 9, width: 24, height: 18)
        }

        override func drawBar(inside rect: NSRect, flipped: Bool) {
            let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
            NSColor.white.withAlphaComponent(isEnabled ? 0.24 : 0.12).setFill()
            NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
            let ratio = (doubleValue - minValue) / max(1, maxValue - minValue)
            let fill = NSRect(x: track.minX, y: track.minY, width: track.width * ratio, height: 6)
            NSColor(white: 0.95, alpha: isEnabled ? 1 : 0.4).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
        }

        override func drawKnob(_ rect: NSRect) {
            NSColor(white: 0.95, alpha: isEnabled ? 1 : 0.4).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        }
    }
#endif
