import Foundation

public enum PreferenceWarning: Equatable, Sendable {
    case loadFailed(String)
    case saveFailed(String)
}

public struct PreferenceSnapshot: Equatable, Sendable {
    public let value: Preferences
    public let acceptedRevision: UInt64
    public let isPersisted: Bool
    public let warning: PreferenceWarning?

    public init(
        value: Preferences, acceptedRevision: UInt64, isPersisted: Bool, warning: PreferenceWarning?
    ) {
        self.value = value
        self.acceptedRevision = acceptedRevision
        self.isPersisted = isPersisted
        self.warning = warning
    }
}

public protocol PreferenceRepository: Sendable {
    func updates() async -> AsyncStream<PreferenceSnapshot>
    func save(_ preferences: Preferences, editRevision: UInt64) async throws
    func flush() async throws
}
