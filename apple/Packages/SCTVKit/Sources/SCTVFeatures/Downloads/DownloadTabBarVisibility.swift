#if os(iOS)
    import SwiftUI

    /// Gives the system ownership of tab visibility while selection owns the page's controls.
    struct DownloadTabBarVisibility: UIViewControllerRepresentable {
        static let travelDistance: CGFloat = 24
        let hidden: Bool
        let animated: Bool
        @Binding var bottomSafeArea: CGFloat

        func makeUIViewController(context: Context) -> Controller { Controller() }

        func updateUIViewController(_ controller: Controller, context: Context) {
            controller.bottomSafeArea = $bottomSafeArea
            controller.update(hidden: hidden, animated: animated)
        }

        static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
            controller.restore()
        }

        final class Controller: UIViewController {
            var bottomSafeArea: Binding<CGFloat>?
            private var hidden = false
            private var animated = false
            private var visible = false
            private weak var controlledTabs: UITabBarController?
            private var originalHidden = false
            private var requestedHidden: Bool?

            override func loadView() {
                view = UIView()
                view.isUserInteractionEnabled = false
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                visible = true
                apply()
            }

            override func viewDidLayoutSubviews() {
                super.viewDidLayoutSubviews()
                if visible { apply() }
            }

            override func viewWillDisappear(_ animated: Bool) {
                super.viewWillDisappear(animated)
                visible = false
                restore()
            }

            func update(hidden: Bool, animated: Bool) {
                self.hidden = hidden
                self.animated = animated
                if visible { apply() }
            }

            private func apply() {
                if let inset = view.window?.safeAreaInsets.bottom,
                    let bottomSafeArea, bottomSafeArea.wrappedValue != inset
                {
                    // Report the window inset, excluding the tab bar's changing safe area.
                    Task { @MainActor in bottomSafeArea.wrappedValue = inset }
                }
                guard let tabs = tabBarController else { return }
                // Top tabs/sidebar do not compete with bottom actions.
                guard tabs.traitCollection.horizontalSizeClass != .regular else {
                    restore()
                    return
                }
                if controlledTabs == nil {
                    guard hidden else { return }
                    controlledTabs = tabs
                    originalHidden = tabs.isTabBarHidden
                }
                let target = hidden || originalHidden
                // Layout callbacks must not restart an in-flight system transition.
                guard requestedHidden != target else { return }
                requestedHidden = target
                tabs.setTabBarHidden(target, animated: animated)
            }

            func restore() {
                if let controlledTabs {
                    controlledTabs.setTabBarHidden(originalHidden, animated: false)
                }
                controlledTabs = nil
                requestedHidden = nil
            }
        }
    }

    /// Interpolates once so every row and the batch action area reverse together.
    struct DownloadSelectionTransition<Content: View>: View, Animatable {
        nonisolated var progress: CGFloat
        @ViewBuilder var content: (CGFloat) -> Content
        nonisolated var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }
        var body: some View {
            content(progress).transaction { $0.animation = nil }
        }
    }
#endif
