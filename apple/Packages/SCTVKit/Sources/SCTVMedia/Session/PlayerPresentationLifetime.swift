import Foundation

/// A scene can disappear without popping its navigation path. Its owner releases
/// only its last presentation; a newer scene's session is protected by the token.
@MainActor
public final class PlayerPresentationLifetime {
    private let session: PlayerSession
    private var presentationID: UUID?

    public init(session: PlayerSession) { self.session = session }

    public func takeOwnership(of presentationID: UUID) { self.presentationID = presentationID }

    isolated deinit {
        guard let presentationID else { return }
        let session = session
        Task { await session.close(presentationID: presentationID) }
    }
}
