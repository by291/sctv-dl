import SwiftUI

struct BatchActionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
            #if os(macOS)
                .background(.regularMaterial)
            #endif
            .overlay(alignment: .top) { Divider() }
    }
}

extension View {
    func batchSelectionBar<Bar: View>(
        selecting: Bool, progress: CGFloat, @ViewBuilder bar: () -> Bar
    ) -> some View {
        modifier(BatchSelectionBar(selecting: selecting, progress: progress, bar: bar()))
    }
}

private struct BatchSelectionBar<Bar: View>: ViewModifier {
    let selecting: Bool
    let progress: CGFloat
    let bar: Bar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
        @State private var barHeight: CGFloat = 0
        @State private var bottomSafeArea: CGFloat = 0
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: barHeight * progress)
                }
                .overlay(alignment: .bottom) {
                    bar
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            barHeight = $0
                        }
                        .padding(.bottom, bottomSafeArea)
                        .background { Rectangle().fill(.regularMaterial) }
                        // Anchor the entire footer while native tab visibility changes the safe area.
                        .offset(y: (1 - progress) * SelectionTabBarVisibility.travelDistance)
                        .opacity(progress)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .allowsHitTesting(selecting)
                        .accessibilityHidden(!selecting)
                }
                .background(
                    SelectionTabBarVisibility(
                        hidden: selecting, animated: !reduceMotion, bottomSafeArea: $bottomSafeArea)
                )
        #else
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting { bar }
            }
        #endif
    }
}
