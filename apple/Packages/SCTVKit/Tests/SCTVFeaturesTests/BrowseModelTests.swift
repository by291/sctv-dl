import Foundation
import SCTVCore
import Testing

@testable import SCTVFeatures

actor BrowseFixture: ProgrammeRepository {
    var queries: [ProgrammeQuery] = []
    let programme = Programme(id: "1", name: "四川新闻", cover: nil)
    func observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate> {
        let items: ProgrammeItems
        switch query {
        case .catalogue: items = .catalogue([programme])
        case .dates:
            items = .dates([
                BroadcastDate(id: "20", date: "2026-10-22"),
                BroadcastDate(id: "19", date: "2026-10-21"),
            ])
        case .contents: items = .contents([])
        }
        return AsyncStream { continuation in
            continuation.yield(
                ProgrammeUpdate(
                    accepted: ProgrammeSnapshot(
                        query: query, items: items, revision: UUID(), fetchedAt: Date()),
                    pending: nil, warning: nil))
        }
    }
    func refresh(_ query: ProgrammeQuery) async throws { queries.append(query) }
    func accept(_ query: ProgrammeQuery, revision: UUID) async throws {}
    func cancel(_ query: ProgrammeQuery) async {}
}

actor FavouriteFixture: FavouriteRepository {
    func ids() async throws -> Set<String> { ["1"] }
    func set(_ programmeID: String, isFavourite: Bool) async throws {}
    func updates() async -> AsyncStream<Set<String>> { AsyncStream { $0.yield(["1"]) } }
}

@MainActor
struct BrowseModelTests {
    @Test func removedRestoredDateSelectsNewestOnce() async throws {
        let repository = BrowseFixture()
        let model = ArchiveModel(
            programme: await repository.programme, repository: repository, restoredDateID: "removed"
        )
        await model.load()
        let expectedRefresh = ProgrammeQuery.contents(programmeID: "1", dateID: "20")
        // Selecting the date precedes the asynchronous refresh; wait for the effect being asserted.
        for _ in 0..<50 {
            if await repository.queries.contains(expectedRefresh) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.selectedDateID == "20")
        #expect(
            await repository.queries.filter { $0 == .contents(programmeID: "1", dateID: "20") }
                .count == 1)
        model.setSelection(["old"])
        await model.selectDate("19")
        #expect(model.selection.isEmpty)
        #expect(model.selectedDateID == "19")
        model.stop()
    }

    @Test func catalogueSearchAndFavouritesKeepServiceOrder() async throws {
        let model = CatalogueModel(repository: BrowseFixture(), favourites: FavouriteFixture())
        await model.load()
        for _ in 0..<50 where model.programmes.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        model.search = "不存在"
        #expect(model.visibleProgrammes.isEmpty)
        model.search = "新闻"
        model.favouritesOnly = true
        #expect(model.visibleProgrammes.map(\.id) == ["1"])
        model.stop()
    }
}
