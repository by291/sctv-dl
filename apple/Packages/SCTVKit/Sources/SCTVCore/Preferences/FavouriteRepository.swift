import Foundation

public struct FavouriteSnapshot: Equatable, Sendable {
    public let confirmedIDs: Set<String>
    public let desiredIDs: Set<String>
    public let warning: String?

    public init(confirmedIDs: Set<String>, desiredIDs: Set<String>, warning: String?) {
        self.confirmedIDs = confirmedIDs
        self.desiredIDs = desiredIDs
        self.warning = warning
    }
}

public protocol FavouriteRepository: Sendable {
    func ids() async throws -> Set<String>
    func set(_ programmeID: String, isFavourite: Bool) async throws
    func updates() async -> AsyncStream<Set<String>>
    func stateUpdates() async -> AsyncStream<FavouriteSnapshot>
}

extension FavouriteRepository {
    public func stateUpdates() async -> AsyncStream<FavouriteSnapshot> {
        let source = await updates()
        return AsyncStream { continuation in
            let task = Task {
                for await ids in source {
                    continuation.yield(
                        FavouriteSnapshot(confirmedIDs: ids, desiredIDs: ids, warning: nil))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
