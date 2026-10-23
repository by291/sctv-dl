import Foundation

/// A scene can disappear without popping its navigation path. Its owner releases
/// only its last presentation; a newer scene's session is protected by the token.
@MainActor
public final class PlayerPresentationLifetime {
    private let session: PlayerSession
    private var token: UUID?

    public init(session: PlayerSession) { self.session = session }

    public func takeOwnership(of token: UUID) { self.token = token }

    isolated deinit {
        guard let token else { return }
        let session = session
        Task { await session.close(expected: token) }
    }
}
