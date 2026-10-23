import Foundation

@MainActor
final class AudioSessionOperations {
    private var pending: Task<Void, Never>?

    func perform(_ operation: @escaping @Sendable () async throws -> Void) -> Task<Void, Error> {
        let previous = pending
        let work = Task {
            await previous?.value
            try await operation()
        }
        // Failure is returned to the caller, but must not poison the next operation.
        pending = Task { _ = try? await work.value }
        return work
    }
}
