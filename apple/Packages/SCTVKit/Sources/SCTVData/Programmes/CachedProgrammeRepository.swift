import Foundation
import GRDB
import SCTVCore

public actor CachedProgrammeRepository: ProgrammeRepository {
    public enum AcceptanceError: Error, Sendable {
        case revisionChanged
        case selectionActive
        case datesPending
    }

    private struct Entry {
        var accepted: ProgrammeSnapshot?
        var pending: ProgrammeSnapshot?
        var warning: ProgrammeWarning?
        var generation: UInt64 = 0
        var request: Task<ProgrammeItems, any Error>?
        var interestedOwners: Set<UUID> = []
        var observers: [UUID: AsyncStream<ProgrammeUpdate>.Continuation] = [:]

        var update: ProgrammeUpdate {
            ProgrammeUpdate(accepted: accepted, pending: pending, warning: warning)
        }
    }

    private let api: any ProgrammeAPI
    private let database: DatabaseQueue
    private var entries: [ProgrammeQuery: Entry] = [:]
    private var loaded: Set<ProgrammeQuery> = []
    private var activeSelections: [ProgrammeQuery: Set<UUID>] = [:]

    public init(api: any ProgrammeAPI, database: DatabaseQueue) {
        self.api = api
        self.database = database
    }

    public func observe(_ query: ProgrammeQuery) -> AsyncStream<ProgrammeUpdate> {
        loadIfNeeded(query)
        let observerID = UUID()
        return AsyncStream { continuation in
            var entry = entries[query, default: Entry()]
            entry.observers[observerID] = continuation
            entries[query] = entry
            continuation.yield(entry.update)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID, for: query) }
            }
        }
    }

    public func current(_ query: ProgrammeQuery) -> ProgrammeUpdate {
        loadIfNeeded(query)
        return entries[query, default: Entry()].update
    }

    public func refresh(_ query: ProgrammeQuery) async throws {
        try await refresh(query, owner: nil)
    }

    public func refresh(_ query: ProgrammeQuery, owner: UUID) async throws {
        try await refresh(query, owner: Optional(owner))
    }

    private func refresh(_ query: ProgrammeQuery, owner: UUID?) async throws {
        loadIfNeeded(query)
        var entry = entries[query, default: Entry()]
        if let owner { entry.interestedOwners.insert(owner) }
        entry.generation &+= 1
        let generation = entry.generation
        entry.request?.cancel()
        let request = Task { [api] in try await Self.fetch(query, from: api) }
        entry.request = request
        entry.warning = nil
        entries[query] = entry
        publish(query)

        do {
            let items = try await request.value
            guard entries[query]?.generation == generation else { return }
            entry = entries[query, default: Entry()]
            let revision = UUID()
            let snapshot = ProgrammeSnapshot(
                query: query, items: items, revision: revision, fetchedAt: Date())
            if let accepted = entry.accepted {
                if SnapshotComparison.hasMeaningfulChange(accepted.items, items) {
                    entry.pending = snapshot
                } else {
                    entry.pending = nil
                }
            } else {
                // A successful empty result is accepted data, distinct from never fetched.
                try persist(snapshot)
                entry.accepted = snapshot
                entry.pending = nil
            }
            entry.request = nil
            entry.warning = nil
            entries[query] = entry
            publish(query)
        } catch {
            guard entries[query]?.generation == generation else { return }
            entry = entries[query, default: Entry()]
            entry.request = nil
            entry.warning = .refreshFailed(String(describing: error))
            entries[query] = entry
            publish(query)
            throw error
        }
    }

    public func accept(_ query: ProgrammeQuery, revision: UUID) throws {
        loadIfNeeded(query)
        guard
            !activeSelections.contains(where: { selected, owners in
                !owners.isEmpty && Self.selection(selected, blocks: query)
            })
        else {
            throw AcceptanceError.selectionActive
        }
        guard let pending = entries[query]?.pending, pending.revision == revision else {
            throw AcceptanceError.revisionChanged
        }
        if case .contents(let programmeID, _) = query,
            entries[.dates(programmeID: programmeID)]?.pending != nil
        {
            throw AcceptanceError.datesPending
        }
        if case .contents(let programmeID, let dateID) = query,
            case .dates(let dates)? = entries[.dates(programmeID: programmeID)]?.accepted?.items,
            !dates.contains(where: { $0.id == dateID })
        {
            throw AcceptanceError.datesPending
        }
        try persist(pending)
        var entry = entries[query, default: Entry()]
        entry.accepted = pending
        entry.pending = nil
        entries[query] = entry
        publish(query)
    }

    public func cancel(_ query: ProgrammeQuery) {
        guard let entry = entries[query], entry.interestedOwners.isEmpty,
            entry.observers.isEmpty
        else { return }
        cancelInFlight(query)
    }

    public func cancel(_ query: ProgrammeQuery, owner: UUID) {
        entries[query]?.interestedOwners.remove(owner)
        guard let entry = entries[query], entry.interestedOwners.isEmpty,
            entry.observers.isEmpty
        else { return }
        cancelInFlight(query)
    }

    private func cancelInFlight(_ query: ProgrammeQuery) {
        var entry = entries[query, default: Entry()]
        entry.generation &+= 1
        entry.request?.cancel()
        entry.request = nil
        entries[query] = entry
    }

    public func setSelectionActive(_ active: Bool, for query: ProgrammeQuery, owner: UUID) {
        if active {
            activeSelections[query, default: []].insert(owner)
        } else {
            activeSelections[query]?.remove(owner)
            if activeSelections[query]?.isEmpty == true {
                activeSelections.removeValue(forKey: query)
            }
        }
    }

    private static func selection(_ selected: ProgrammeQuery, blocks acceptance: ProgrammeQuery)
        -> Bool
    {
        switch (selected, acceptance) {
        case (.contents(let selectedProgramme, _), .dates(let acceptedProgramme)),
            (.dates(let selectedProgramme), .dates(let acceptedProgramme)):
            return selectedProgramme == acceptedProgramme
        case (.contents(let selectedProgramme, _), .contents(let acceptedProgramme, _)),
            (.dates(let selectedProgramme), .contents(let acceptedProgramme, _)):
            return selectedProgramme == acceptedProgramme
        default:
            return selected == acceptance
        }
    }

    private static func fetch(_ query: ProgrammeQuery, from api: any ProgrammeAPI) async throws
        -> ProgrammeItems
    {
        switch query {
        case .catalogue: return .catalogue(try await api.catalogue())
        case .dates(let programmeID): return .dates(try await api.dates(programmeID: programmeID))
        case .contents(let programmeID, let dateID):
            return .contents(try await api.contents(programmeID: programmeID, dateID: dateID))
        }
    }

    private func loadIfNeeded(_ query: ProgrammeQuery) {
        guard loaded.insert(query).inserted else { return }
        do {
            let key = try resourceKey(query)
            let payload = try database.read { db in
                try Data.fetchOne(
                    db, sql: "SELECT payload FROM programme_snapshots WHERE resource_key = ?",
                    arguments: [key])
            }
            if let payload {
                let snapshot = try JSONDecoder().decode(ProgrammeSnapshot.self, from: payload)
                guard snapshot.query == query else { return }
                entries[query, default: Entry()].accepted = snapshot
            }
        } catch {
            entries[query, default: Entry()].warning = .refreshFailed(String(describing: error))
        }
    }

    private func persist(_ snapshot: ProgrammeSnapshot) throws {
        let key = try resourceKey(snapshot.query)
        let payload = try JSONEncoder().encode(snapshot)
        try database.write { db in
            try db.execute(
                sql:
                    "INSERT INTO programme_snapshots (resource_key, payload, revision, fetched_at) VALUES (?, ?, ?, ?) ON CONFLICT(resource_key) DO UPDATE SET payload=excluded.payload, revision=excluded.revision, fetched_at=excluded.fetched_at",
                arguments: [
                    key, payload, snapshot.revision.uuidString,
                    snapshot.fetchedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    private func resourceKey(_ query: ProgrammeQuery) throws -> String {
        try JSONEncoder().encode(query).base64EncodedString()
    }

    private func publish(_ query: ProgrammeQuery) {
        guard let entry = entries[query] else { return }
        for continuation in entry.observers.values { continuation.yield(entry.update) }
    }

    private func removeObserver(_ observerID: UUID, for query: ProgrammeQuery) {
        entries[query]?.observers.removeValue(forKey: observerID)
        if entries[query]?.observers.isEmpty == true,
            entries[query]?.interestedOwners.isEmpty == true
        {
            cancelInFlight(query)
        }
    }
}
