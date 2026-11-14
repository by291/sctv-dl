import Foundation

/// Gives persistence a bounded opportunity to settle without letting a stalled writer block quit.
@MainActor public final class ShutdownDrain {
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var completion: (@MainActor (Bool) -> Void)?
    private var drainID: UUID?

    public init() {}

    /// Starts a drain if idle and reports whether its deadline elapsed.
    public func start(
        timeout: Duration,
        operation: @escaping @MainActor @Sendable () async -> Void,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard self.completion == nil else { return }

        let drainID = UUID()
        self.drainID = drainID
        self.completion = completion
        self.operation = Task { [weak self] in
            await operation()
            self?.finish(drainID, timedOut: false)
        }
        deadline = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                // Settled work cancels its deadline.
                return
            }

            self?.finish(drainID, timedOut: true)
        }
    }

    private func finish(_ drainID: UUID, timedOut: Bool) {
        // A writer that ignores cancellation may finish during a later drain.
        guard self.drainID == drainID, let completion else { return }

        self.drainID = nil
        self.completion = nil
        deadline?.cancel()
        operation?.cancel()
        deadline = nil
        operation = nil
        // Cancellation is advisory: do not await a writer that may ignore it.
        completion(timedOut)
    }
}
