#if os(macOS)
    import SwiftUI

    struct MacPlayerFeedback: Identifiable {
        let id = UUID()
        let message: String
        let symbol: String
    }

    public struct MacPlayerFeedbackView: View {
        let presentation: MacPlayerPresentation
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(presentation: MacPlayerPresentation) { self.presentation = presentation }

        public var body: some View {
            Group {
                if let feedback = presentation.feedback {
                    VStack(spacing: 6) {
                        Image(systemName: feedback.symbol).font(.system(size: 24, weight: .medium))
                            .frame(width: 28, height: 28)
                        Text(feedback.message).font(
                            .system(size: 13, weight: .medium).monospacedDigit()
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: 18)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.white)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .environment(\.colorScheme, .dark)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(feedback.message)
                    .accessibilityIdentifier("player-action-feedback")
                    .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15), value: presentation.feedback != nil
            )
            .task(id: presentation.feedback?.id) {
                guard let id = presentation.feedback?.id else { return }
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                if presentation.feedback?.id == id { presentation.feedback = nil }
            }
            .onDisappear { presentation.feedback = nil }
        }
    }
#endif
