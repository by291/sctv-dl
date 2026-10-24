#if os(iOS)
    import SwiftUI

    struct DownloadTabBarInsets: Equatable {
        var height: CGFloat = 0
        var bottom: CGFloat = 0
    }

    /// Keeps the native bar mounted while the page drives both surfaces with one progress value.
    struct DownloadTabBarVisibility: UIViewControllerRepresentable {
        static let travelDistance: CGFloat = 24
        let progress: CGFloat
        @Binding var insets: DownloadTabBarInsets

        func makeUIViewController(context: Context) -> Controller { Controller() }

        func updateUIViewController(_ controller: Controller, context: Context) {
            controller.reportInsets = { value in
                if insets != value { insets = value }
            }
            controller.update(progress: progress)
        }

        static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
            controller.restore()
        }

        final class Controller: UIViewController {
            private var progress: CGFloat = 0
            private var visible = false
            private weak var bar: UITabBar?
            private var originalTransform = CGAffineTransform.identity
            private var originalAlpha: CGFloat = 1
            private var originalInteraction = true
            private var originalAccessibilityHidden = false
            private var lastInsets: DownloadTabBarInsets?
            var reportInsets: ((DownloadTabBarInsets) -> Void)?

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

            func update(progress: CGFloat) {
                self.progress = min(1, max(0, progress))
                if visible { apply() }
            }

            private func apply() {
                guard let tabs = tabBarController else { return }
                let bottom = view.window?.safeAreaInsets.bottom ?? 0
                // Top tabs/sidebar do not compete with bottom actions. Keep their controls stationary.
                if tabs.traitCollection.horizontalSizeClass == .regular {
                    if bar != nil { restore() }
                    report(DownloadTabBarInsets(bottom: bottom))
                    return
                }
                if bar == nil && progress > 0 {
                    bar = tabs.tabBar
                    originalTransform = tabs.tabBar.transform
                    originalAlpha = tabs.tabBar.alpha
                    originalInteraction = tabs.tabBar.isUserInteractionEnabled
                    originalAccessibilityHidden = tabs.tabBar.accessibilityElementsHidden
                }
                let measuredBar = bar ?? tabs.tabBar
                let frame = measuredBar.convert(measuredBar.bounds, to: tabs.view)
                // Subtract our translation when measuring the native resting inset.
                let translation = bar.map { $0.transform.ty - originalTransform.ty } ?? 0
                let restingBottom = frame.minY - translation
                let height =
                    frame.midY > tabs.view.bounds.midY
                    ? max(0, tabs.view.bounds.maxY - restingBottom - bottom) : 0
                report(DownloadTabBarInsets(height: height.rounded(), bottom: bottom))
                guard let bar else { return }
                if progress == 0 {
                    restore()
                    return
                }
                UIView.performWithoutAnimation {
                    bar.alpha = originalAlpha * (1 - progress)
                    bar.transform = originalTransform.translatedBy(
                        x: 0, y: progress * DownloadTabBarVisibility.travelDistance)
                }
                bar.isUserInteractionEnabled = originalInteraction && progress == 0
                bar.accessibilityElementsHidden = originalAccessibilityHidden || progress > 0
            }

            private func report(_ insets: DownloadTabBarInsets) {
                if lastInsets != insets {
                    lastInsets = insets
                    DispatchQueue.main.async { [weak self] in
                        guard let self, visible, lastInsets == insets else { return }
                        reportInsets?(insets)
                    }
                }
            }

            func restore() {
                if let bar {
                    bar.transform = originalTransform
                    bar.alpha = originalAlpha
                    bar.isUserInteractionEnabled = originalInteraction
                    bar.accessibilityElementsHidden = originalAccessibilityHidden
                }
                bar = nil
                lastInsets = nil
            }
        }
    }

    /// Interpolates once; rows and native chrome consume the same presentation progress.
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
