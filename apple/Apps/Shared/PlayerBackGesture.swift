#if os(iOS)
    import SwiftUI

    /// Keeps the navigation controller's interactive transition when video hides its bar.
    struct PlayerBackGesture: UIViewControllerRepresentable {
        let enabled: Bool

        func makeUIViewController(context: Context) -> Controller { Controller() }

        func updateUIViewController(_ controller: Controller, context: Context) {
            controller.allowsBack = enabled
        }

        static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
            controller.restore()
        }

        final class Controller: UIViewController, UIGestureRecognizerDelegate {
            var allowsBack = true
            private weak var recognizer: UIGestureRecognizer?
            private weak var previousDelegate: (any UIGestureRecognizerDelegate)?
            private var wasEnabled = false
            private weak var tabController: UITabBarController?
            private var previousTabMode: UITabBarController.Mode?
            private var previousSidebarHidden = true

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                // The adaptive iPad sidebar otherwise captures the edge before navigation can begin.
                // Playback already hides tab chrome; restore the browsing mode when leaving.
                if traitCollection.userInterfaceIdiom == .pad,
                    previousTabMode == nil, let tabs = tabBarController
                {
                    tabController = tabs
                    previousTabMode = tabs.mode
                    previousSidebarHidden = tabs.sidebar.isHidden
                    tabs.mode = .tabBar
                }
                guard let gesture = navigationController?.interactivePopGestureRecognizer else {
                    return
                }
                guard gesture.delegate !== self else { return }
                recognizer = gesture
                previousDelegate = gesture.delegate
                wasEnabled = gesture.isEnabled
                gesture.delegate = self
                gesture.isEnabled = true
            }

            override func viewDidDisappear(_ animated: Bool) {
                super.viewDidDisappear(animated)
                restore()
            }

            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                guard allowsBack, let navigationController else { return false }
                return navigationController.viewControllers.count > 1
                    && navigationController.transitionCoordinator == nil
            }

            func restore() {
                // Only restore the delegate this page replaced, never another destination's owner.
                if let recognizer, recognizer.delegate === self {
                    recognizer.delegate = previousDelegate
                    recognizer.isEnabled = wasEnabled
                }
                recognizer = nil
                previousDelegate = nil
                if let tabController, let previousTabMode, tabController.mode == .tabBar {
                    tabController.mode = previousTabMode
                    tabController.sidebar.isHidden = previousSidebarHidden
                }
                tabController = nil
                previousTabMode = nil
            }
        }
    }
#endif
