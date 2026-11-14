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

/// Persists preference edits in revision order and reports the current save status.
public protocol PreferenceRepository: Sendable {
    /// Emits the current snapshot, including load failures, followed by state changes.
    func updates() async -> AsyncStream<PreferenceSnapshot>

    /// Accepts a new revision or retries the same value; stale revisions throw.
    func save(_ preferences: Preferences, editRevision: UInt64) async throws

    /// Retries the current unpersisted value and throws if it still cannot be saved.
    func flush() async throws
}
