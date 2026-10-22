import Foundation
import SCTVCore
import Testing

@testable import SCTVFeatures

private actor SuspendedBrowseRepository: ProgrammeRepository {
    var observing = false
    var requests = 0
    var gate: CheckedContinuation<Void, Never>?
    func observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate> {
        observing = true
        await withCheckedContinuation { gate = $0 }
        return AsyncStream { $0.finish() }
    }
    func resume() {
        gate?.resume()
        gate = nil
    }
    func refresh(_ query: ProgrammeQuery) async throws { requests += 1 }
    func accept(_ query: ProgrammeQuery, revision: UUID) async throws {}
    func cancel(_ query: ProgrammeQuery) async {}
}

@MainActor struct BrowseLifecycleTests {
    @Test func closingArchiveDuringSubscriptionDoesNotStartRequest() async throws {
        let repository = SuspendedBrowseRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        let loading = Task { await model.load() }
        for _ in 0..<100 where !(await repository.observing) {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await repository.observing)
        model.stop()
        await repository.resume()
        await loading.value
        #expect(await repository.requests == 0)
    }

    @Test func stoppedDatesRefreshReleasesOnlyItsOwnRegistration() async throws {
        let repository = OwnedBrowseRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        await model.load()
        await repository.blockNext(.dates(programmeID: "1"))

        let stale = Task { await model.refresh() }
        await repository.waitUntilBlocked()
        model.stop()
        await model.load()
        await repository.resumeBlocked()
        await stale.value

        let dates = ProgrammeQuery.dates(programmeID: "1")
        let owners = await repository.ownerHistory(for: dates)
        #expect(owners.count == 3)
        #expect(Set(owners).count == 2)
        #expect(await repository.ownerCount(dates) == 1)
        #expect(await repository.isOwnerActive(try #require(owners.dropFirst().first), for: dates))
        #expect(!(await repository.isOwnerActive(try #require(owners.last), for: dates)))
        model.stop()
    }

    @Test func stoppedContentRefreshDoesNotCancelNewSameDateRoute() async throws {
        let repository = OwnedBrowseRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        await model.load()
        for _ in 0..<100 where model.selectedDateID != "20" {
            try await Task.sleep(for: .milliseconds(1))
        }
        let query = ProgrammeQuery.contents(programmeID: "1", dateID: "19")
        await repository.blockNext(query)

        let stale = Task { await model.selectDate("19") }
        await repository.waitUntilBlocked()
        model.stop()
        await model.load()
        for _ in 0..<100 where model.selectedDateID != "19" {
            try await Task.sleep(for: .milliseconds(1))
        }
        await repository.resumeBlocked()
        await stale.value

        let owners = await repository.ownerHistory(for: query)
        #expect(Set(owners).count == 2)
        #expect(await repository.ownerCount(query) == 1)
        #expect(await repository.isOwnerActive(try #require(owners.first), for: query))
        #expect(!(await repository.isOwnerActive(try #require(owners.last), for: query)))
        model.stop()
    }
}

private actor OwnedBrowseRepository: ProgrammeRepository {
    private var owners: [ProgrammeQuery: Set<UUID>] = [:]
    private var history: [ProgrammeQuery: [UUID]] = [:]
    private var blockedQuery: ProgrammeQuery?
    private var blocked: CheckedContinuation<Void, Never>?
    private var blockedWaiter: CheckedContinuation<Void, Never>?

    func observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate> {
        let items: ProgrammeItems
        switch query {
        case .dates:
            items = .dates([
                BroadcastDate(id: "20", date: "2026-10-22"),
                BroadcastDate(id: "19", date: "2026-10-21"),
            ])
        case .contents: items = .contents([])
        case .catalogue: items = .catalogue([])
        }
        return AsyncStream { continuation in
            continuation.yield(
                ProgrammeUpdate(
                    accepted: ProgrammeSnapshot(
                        query: query, items: items, revision: UUID(), fetchedAt: Date()),
                    pending: nil, warning: nil))
        }
    }

    func refresh(_ query: ProgrammeQuery) async throws {}
    func refresh(_ query: ProgrammeQuery, owner: UUID) async throws {
        if blockedQuery == query {
            blockedQuery = nil
            await withCheckedContinuation { continuation in
                blocked = continuation
                blockedWaiter?.resume()
                blockedWaiter = nil
            }
        }
        owners[query, default: []].insert(owner)
        history[query, default: []].append(owner)
    }
    func blockNext(_ query: ProgrammeQuery) { blockedQuery = query }
    func waitUntilBlocked() async {
        if blocked != nil { return }
        await withCheckedContinuation { blockedWaiter = $0 }
    }
    func resumeBlocked() {
        blocked?.resume()
        blocked = nil
    }
    func ownerCount(_ query: ProgrammeQuery) -> Int { owners[query, default: []].count }
    func ownerHistory(for query: ProgrammeQuery) -> [UUID] { history[query, default: []] }
    func isOwnerActive(_ owner: UUID, for query: ProgrammeQuery) -> Bool {
        owners[query, default: []].contains(owner)
    }
    func accept(_ query: ProgrammeQuery, revision: UUID) async throws {}
    func cancel(_ query: ProgrammeQuery) async {}
    func cancel(_ query: ProgrammeQuery, owner: UUID) async {
        owners[query]?.remove(owner)
    }
}
