import Foundation

/// Serializes seeks across input adapters and retains only the latest preview.
/// Cancellation revokes UI ownership immediately; AVPlayer may still finish its seek.
@MainActor
final class PlayerSeekInteraction {
    private struct Preview {
        let owner: UUID
        let token: UUID
        let overlay: PlayerOverlayState
    }

    private var task: Task<Void, Never>?
    private var preview: Preview?

    @discardableResult
    func seek(
        to position: Int64, owner: UUID, overlay: PlayerOverlayState,
        operation: @escaping @MainActor () async throws -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        let previous = task
        cancel()
        let token = overlay.beginSeekPreview(at: position)
        preview = Preview(owner: owner, token: token, overlay: overlay)
        overlay.reveal()

        let next = Task { [weak self] in
            // A cancelled native seek can still be settling. Start only the latest queued target.
            await previous?.value
            do {
                try Task.checkCancellation()
                try await operation()
                try Task.checkCancellation()
            } catch is CancellationError {
                // Cancellation belongs to a newer input, source or presentation.
            } catch {
                if !Task.isCancelled { onFailure(error) }
            }
            self?.finish(token: token)
        }
        task = next
        return next
    }

    /// A disappearing adapter may revoke only its own latest request.
    func cancel(owner: UUID) {
        guard preview?.owner == owner else { return }
        cancel()
    }

    /// Source replacement revokes all input work before disposing the native item.
    func cancel() {
        task?.cancel()
        if let preview { finish(token: preview.token) }
        // Keep the task until it settles so a replacement request still waits for it.
    }

    private func finish(token: UUID) {
        guard let preview, preview.token == token else { return }
        preview.overlay.finishSeekPreview(token)
        self.preview = nil
    }
}
