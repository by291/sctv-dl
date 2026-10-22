import Foundation

/// Gives persistence a bounded opportunity to settle without letting a stalled writer block quit.
@MainActor public final class ShutdownDrain {
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var completion: (@MainActor (Bool) -> Void)?

    public init() {}

    public func start(
        timeout: Duration,
        operation: @escaping @MainActor @Sendable () async -> Void,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard self.completion == nil else { return }
        self.completion = completion
        self.operation = Task { [weak self] in
            await operation()
            self?.finish(timedOut: false)
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(timedOut: true)
        }
    }

    private func finish(timedOut: Bool) {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel()
        operation?.cancel()
        deadline = nil
        operation = nil
        // Cancellation is advisory: do not await a writer that may ignore it.
        completion(timedOut)
    }
}
