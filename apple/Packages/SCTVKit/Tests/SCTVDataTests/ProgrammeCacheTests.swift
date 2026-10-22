import Foundation
import GRDB
import SCTVCore
import Testing

@testable import SCTVData

private actor ControlledProgrammeAPI: ProgrammeAPI {
    private var requests: [CheckedContinuation<[Programme], any Error>] = []

    func catalogue() async throws -> [Programme] {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }

    func dates(programmeID: String) async throws -> [BroadcastDate] { [] }
    func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] { [] }

    func complete(_ index: Int, with items: [Programme]) {
        requests[index].resume(returning: items)
    }

    func count() -> Int { requests.count }
}

struct ProgrammeCacheTests {
    private func repository(api: any ProgrammeAPI) throws -> CachedProgrammeRepository {
        let database = try DatabaseQueue()
        try RuntimeMigrations.migrator.migrate(database)
        return CachedProgrammeRepository(api: api, database: database)
    }

    @Test func lateResponseCannotReplaceNewGeneration() async throws {
        let api = ControlledProgrammeAPI()
        let repository = try repository(api: api)
        let older = Task { try await repository.refresh(.catalogue) }
        while await api.count() < 1 { await Task.yield() }
        let newer = Task { try await repository.refresh(.catalogue) }
        while await api.count() < 2 { await Task.yield() }
        let newestItems = [Programme(id: "2", name: "New", cover: nil)]
        await api.complete(1, with: newestItems)
        try await newer.value
        await api.complete(0, with: [Programme(id: "1", name: "Old", cover: nil)])
        try? await older.value

        let accepted = await repository.current(.catalogue).accepted
        #expect(accepted?.items == .catalogue(newestItems))
    }

    @Test func emptyIsFetched() async throws {
        let repository = try repository(api: EmptyProgrammeAPI())
        try await repository.refresh(.catalogue)
        let update = await repository.current(.catalogue)
        #expect(update.accepted?.items == .catalogue([]))
    }

    @Test func unchangedFieldsKeepRevision() async throws {
        let api = SequencedProgrammeAPI([
            .success([Programme(id: "7", name: "Seven ", cover: nil)]),
            .success([Programme(id: "7", name: "Seven", cover: nil)]),
        ])
        let repository = try repository(api: api)
        try await repository.refresh(.catalogue)
        let revision = await repository.current(.catalogue).accepted?.revision
        try await repository.refresh(.catalogue)
        #expect(await repository.current(.catalogue).accepted?.revision == revision)
        #expect(await repository.current(.catalogue).pending == nil)
    }

    @Test func acceptDatesBeforeContents() async throws {
        let repository = try repository(api: ChangingProgrammeAPI())
        let dates = ProgrammeQuery.dates(programmeID: "1")
        let contents = ProgrammeQuery.contents(programmeID: "1", dateID: "10")
        try await repository.refresh(dates)
        try await repository.refresh(contents)
        try await repository.refresh(dates)
        try await repository.refresh(contents)
        let pendingContents = try #require(await repository.current(contents).pending)
        let firstOwner = UUID()
        let secondOwner = UUID()
        await repository.setSelectionActive(true, for: contents, owner: firstOwner)
        await repository.setSelectionActive(true, for: contents, owner: secondOwner)
        let unrelated = ProgrammeQuery.contents(programmeID: "2", dateID: "10")
        try await repository.refresh(unrelated)
        try await repository.refresh(unrelated)
        let unrelatedRevision = try #require(await repository.current(unrelated).pending?.revision)
        try await repository.accept(unrelated, revision: unrelatedRevision)
        await #expect(throws: (any Error).self) {
            try await repository.accept(contents, revision: pendingContents.revision)
        }
        await repository.setSelectionActive(false, for: contents, owner: firstOwner)
        await #expect(throws: (any Error).self) {
            try await repository.accept(contents, revision: pendingContents.revision)
        }
        await repository.setSelectionActive(false, for: contents, owner: secondOwner)
        await #expect(throws: (any Error).self) {
            try await repository.accept(contents, revision: pendingContents.revision)
        }
        let pendingDates = try #require(await repository.current(dates).pending)
        try await repository.accept(dates, revision: pendingDates.revision)
        try await repository.accept(contents, revision: pendingContents.revision)
        #expect(await repository.current(contents).accepted?.revision == pendingContents.revision)
    }

    @Test func oneWindowCancelKeepsOtherWindowsRefresh() async throws {
        let api = ControlledProgrammeAPI()
        let repository = try repository(api: api)
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstStream = await repository.observe(.catalogue)
        let secondStream = await repository.observe(.catalogue)
        var first = firstStream.makeAsyncIterator()
        var second = secondStream.makeAsyncIterator()
        _ = await first.next()
        _ = await second.next()

        let older = Task { try await repository.refresh(.catalogue, owner: firstOwner) }
        while await api.count() < 1 { await Task.yield() }
        let newer = Task { try await repository.refresh(.catalogue, owner: secondOwner) }
        while await api.count() < 2 { await Task.yield() }
        await repository.cancel(.catalogue, owner: firstOwner)
        let newestItems = [Programme(id: "2", name: "Other window", cover: nil)]
        await api.complete(1, with: newestItems)
        try await newer.value
        await api.complete(0, with: [])
        try? await older.value

        #expect(await repository.current(.catalogue).accepted?.items == .catalogue(newestItems))
    }

    @Test func changedEmptyWaitsForAcceptanceAndSurvivesReopen() async throws {
        let database = try DatabaseQueue()
        try RuntimeMigrations.migrator.migrate(database)
        let api = SequencedProgrammeAPI([
            .success([Programme(id: "7", name: "Seven", cover: nil)]),
            .success([]),
        ])
        let repository = CachedProgrammeRepository(api: api, database: database)
        try await repository.refresh(.catalogue)
        let accepted = await repository.current(.catalogue).accepted
        try await repository.refresh(.catalogue)
        let update = await repository.current(.catalogue)
        #expect(update.accepted?.revision == accepted?.revision)
        #expect(update.pending?.items == .catalogue([]))
        let reopened = CachedProgrammeRepository(api: EmptyProgrammeAPI(), database: database)
        #expect(await reopened.current(.catalogue).accepted?.items == accepted?.items)
        try await repository.accept(.catalogue, revision: update.pending!.revision)
        #expect(await reopened.current(.catalogue).accepted?.items == accepted?.items)
        let afterAcceptance = CachedProgrammeRepository(
            api: EmptyProgrammeAPI(), database: database)
        #expect(await afterAcceptance.current(.catalogue).accepted?.items == .catalogue([]))
    }

    @Test func failedRefreshRetainsAcceptedSnapshot() async throws {
        let api = SequencedProgrammeAPI([
            .success([Programme(id: "7", name: "Seven", cover: nil)]),
            .failure(.offline),
        ])
        let repository = try repository(api: api)
        try await repository.refresh(.catalogue)
        let accepted = await repository.current(.catalogue).accepted
        await #expect(throws: (any Error).self) { try await repository.refresh(.catalogue) }
        let update = await repository.current(.catalogue)
        #expect(update.accepted == accepted)
        #expect(update.warning != nil)
    }

    @Test func browseStatePersistsStableAnchorsPerWindow() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        let repository = BrowseStateRepository(database: database)
        let revision = UUID()
        let state = BrowseState(
            selectedProgrammeID: "123", selectedDateID: "456", catalogueSort: .title,
            clipsAscending: true, catalogueAnchorID: "123", archiveAnchorID: "789",
            snapshotRevision: revision)
        try await repository.save(state, windowID: "first")
        #expect(try await repository.load(windowID: "first") == state)
        #expect(try await repository.load(windowID: "second") == BrowseState())
    }
}

private struct EmptyProgrammeAPI: ProgrammeAPI {
    func catalogue() async throws -> [Programme] { [] }
    func dates(programmeID: String) async throws -> [BroadcastDate] { [] }
    func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] { [] }
}

private actor ChangingProgrammeAPI: ProgrammeAPI {
    private var dateCount = 0
    private var contentCount = 0
    func catalogue() async throws -> [Programme] { [] }
    func dates(programmeID: String) async throws -> [BroadcastDate] {
        dateCount += 1
        return [BroadcastDate(id: "10", date: dateCount == 1 ? "2026-01-01" : "2026-01-02")]
    }
    func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] {
        contentCount += 1
        return [
            ProgrammeContent(
                id: "3", title: "Version \(contentCount)", cover: nil, video: nil,
                smoothVideo: nil, publishedAt: nil)
        ]
    }
}

private enum ProgrammeTestError: Error { case offline }

private actor SequencedProgrammeAPI: ProgrammeAPI {
    private var responses: [Result<[Programme], ProgrammeTestError>]
    init(_ responses: [Result<[Programme], ProgrammeTestError>]) { self.responses = responses }
    func catalogue() async throws -> [Programme] { try responses.removeFirst().get() }
    func dates(programmeID: String) async throws -> [BroadcastDate] { [] }
    func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent] { [] }
}
