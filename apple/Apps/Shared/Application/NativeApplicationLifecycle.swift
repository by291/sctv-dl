import Foundation
import OSLog
import SCTVCore
import SCTVDownloads

actor BackgroundEventsBridge {
    static let shared = BackgroundEventsBridge()

    private typealias Callback = (identifier: String, complete: @MainActor @Sendable () -> Void)
    private enum State {
        case preparing
        case installed(BackgroundSessionDriver)
        case unavailable
    }

    private var state = State.preparing
    private var waiting: [Callback] = []

    func install(_ driver: BackgroundSessionDriver) async {
        state = .installed(driver)

        let callbacks = waiting
        waiting = []
        for (identifier, completion) in callbacks {
            await driver.registerBackgroundCompletion(
                identifier: identifier, completion: completion)
        }
    }

    func failStartup() async {
        guard case .preparing = state else { return }
        state = .unavailable

        // Bootstrap cannot produce a driver to deliver a drain. Return the
        // OS completion now; durable records remain available for a future launch.
        let callbacks = waiting
        waiting = []
        for callback in callbacks {
            await callback.complete()
        }
    }

    func retryStartup() {
        if case .unavailable = state {
            state = .preparing
        }
    }

    func receive(_ identifier: String, completion: @escaping @MainActor @Sendable () -> Void) async
    {
        switch state {
        case .installed(let driver):
            await driver.registerBackgroundCompletion(
                identifier: identifier, completion: completion)
        case .preparing:
            waiting.append((identifier, completion))
        case .unavailable:
            await completion()
        }
    }
}

#if os(iOS)
    import UIKit

    @MainActor final class NativeApplicationDelegate: NSObject, UIApplicationDelegate {
        private final class CompletionReceipt {
            let callback: () -> Void

            init(_ callback: @escaping () -> Void) { self.callback = callback }
        }

        func application(
            _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
            completionHandler: @escaping () -> Void
        ) {
            let receipt = CompletionReceipt(completionHandler)
            Task { await BackgroundEventsBridge.shared.receive(identifier) { receipt.callback() } }
        }
    }
#else
    import AppKit

    @MainActor final class NativeApplicationDelegate: NSObject, NSApplicationDelegate {
        static weak var dependencies: AppDependencies?

        private let shutdown = ShutdownDrain()
        private let logger = Logger(subsystem: "dev.sctvdl.apple", category: "lifecycle")

        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            guard let dependencies = Self.dependencies else { return .terminateNow }

            shutdown.start(timeout: .seconds(3)) {
                await dependencies.settings.flush()
                await dependencies.player.recorder.flush(dependencies.player.playback)
                do {
                    try await dependencies.downloads.service.reconcile()
                } catch {
                    self.logger.error(
                        "Download reconciliation at quit failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            } completion: { timedOut in
                if timedOut {
                    self.logger.warning(
                        "Quit persistence deadline elapsed; durable attempts will reconcile at next launch."
                    )
                }
                sender.reply(toApplicationShouldTerminate: true)
            }

            return .terminateLater
        }
    }
#endif
