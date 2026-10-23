import Foundation
import SCTVCore
import Testing

@testable import SCTVFeatures

private actor ArchiveLoadingRepository: ProgrammeRepository {
    private var observers: [ProgrammeQuery: AsyncStream<ProgrammeUpdate>.Continuation] = [:]
    private var failedQuery: ProgrammeQuery?

    func observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate> {
        let (stream, continuation) = AsyncStream<ProgrammeUpdate>.makeStream()
        observers[query] = continuation
        return stream
    }

    func isObserving(_ query: ProgrammeQuery) -> Bool { observers[query] != nil }
    func failRefresh(_ query: ProgrammeQuery) { failedQuery = query }
    func refresh(_ query: ProgrammeQuery) async throws {
        if failedQuery == query { throw CocoaError(.fileReadUnknown) }
    }
    func accept(_ query: ProgrammeQuery, revision: UUID) async throws {}
    func cancel(_ query: ProgrammeQuery) async {}
    func publishPreviousFailure(_ query: ProgrammeQuery) {
        observers[query]?.yield(
            ProgrammeUpdate(
                accepted: nil, pending: nil, warning: .refreshFailed("Previous failure")))
    }
    func publish(_ query: ProgrammeQuery, items: ProgrammeItems) {
        observers[query]?.yield(
            ProgrammeUpdate(
                accepted: ProgrammeSnapshot(
                    query: query, items: items, revision: UUID(), fetchedAt: Date()),
                pending: nil, warning: nil))
    }
}

@MainActor struct ArchiveLoadingTests {
    @Test func contentGroupsFollowAcceptedSnapshotsDatesAndSortOrder() async throws {
        let repository = ArchiveLoadingRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        await model.load()
        let dates = ProgrammeQuery.dates(programmeID: "1")
        let first = ProgrammeQuery.contents(programmeID: "1", dateID: "20")
        let second = ProgrammeQuery.contents(programmeID: "1", dateID: "19")
        await repository.publish(
            dates,
            items: .dates([
                BroadcastDate(id: "20", date: "2026-10-22"),
                BroadcastDate(id: "19", date: "2026-10-21"),
            ]))
        for _ in 0..<100 where !(await repository.isObserving(first)) {
            try await Task.sleep(for: .milliseconds(1))
        }
        func content(_ id: String, _ title: String, _ time: String?) -> ProgrammeContent {
            ProgrammeContent(
                id: id, title: title, cover: nil, video: nil, smoothVideo: nil,
                publishedAt: time)
        }
        let rows = [
            content("full", "News（2026.10.22）", nil),
            content("late", "Late", "2026-10-22 19:05:00"),
            content("early", "Early", "2026-10-22 19:00:00"),
            content("tie", "Same time", "2026-10-22 19:00:00"),
            content("unknown", "Unknown", nil),
        ]
        await repository.publish(first, items: .contents(rows))
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(1)) }
        #expect(model.fullEpisodes.map(\.id) == ["full"])
        #expect(model.clips.map(\.id) == ["early", "tie", "late", "unknown"])
        model.scrollAnchor = "late"
        model.setSelection(["late"])
        #expect(model.clips.map(\.id) == ["early", "tie", "late", "unknown"])
        model.ascending = false
        #expect(model.clips.map(\.id) == ["late", "early", "tie", "unknown"])
        model.ascending = true
        #expect(model.clips.map(\.id) == ["early", "tie", "late", "unknown"])
        await repository.publish(first, items: .contents([rows[0], rows[2]]))
        for _ in 0..<100 where model.contents.count != 2 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(model.clips.map(\.id) == ["early"])

        await model.selectDate("19")
        #expect(model.fullEpisodes.isEmpty)
        #expect(model.clips.isEmpty)
        await repository.publish(
            second,
            items: .contents([
                content("previous", "News（2026.10.21）", nil)
            ]))
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(1)) }
        #expect(model.fullEpisodes.map(\.id) == ["previous"])
        #expect(model.clips.isEmpty)

        await repository.publish(
            dates, items: .dates([BroadcastDate(id: "19", date: "2026-10-20")]))
        for _ in 0..<100 where model.broadcast?.date != "2026-10-20" {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(model.selectedDateID == "19")
        #expect(model.fullEpisodes.isEmpty)
        #expect(model.clips.map(\.id) == ["previous"])
        model.stop()
    }

    @Test func waitsForDatesAndContentSnapshotBeforeShowingEmptyState() async throws {
        let repository = ArchiveLoadingRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        #expect(model.isLoading)
        await model.load()
        #expect(model.isLoading)

        let dates = ProgrammeQuery.dates(programmeID: "1")
        let contents = ProgrammeQuery.contents(programmeID: "1", dateID: "20")
        await repository.publish(
            dates, items: .dates([BroadcastDate(id: "20", date: "2026-10-22")]))
        for _ in 0..<100 where !(await repository.isObserving(contents)) {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await repository.isObserving(contents))
        #expect(model.isLoading)

        await repository.publishPreviousFailure(contents)
        for _ in 0..<100 where model.warning == nil { try await Task.sleep(for: .milliseconds(1)) }
        #expect(model.warning != nil)
        #expect(model.isLoading)

        await repository.publish(contents, items: .contents([]))
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(1)) }
        #expect(!model.isLoading)
        #expect(model.contents.isEmpty)
        #expect(model.warning == nil)
        model.stop()
    }

    @Test func acceptedEmptyDatesAndFailedRequestsEndInitialLoading() async throws {
        let repository = ArchiveLoadingRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        await model.load()
        await repository.publish(.dates(programmeID: "1"), items: .dates([]))
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(1)) }
        #expect(!model.isLoading)
        model.stop()

        await repository.failRefresh(.dates(programmeID: "1"))
        await model.load()
        #expect(!model.isLoading)
        #expect(model.warning != nil)
        model.stop()
    }

    @Test func failedDatesRefreshDoesNotEndTheSelectedDatesContentLoading() async throws {
        let repository = ArchiveLoadingRepository()
        let model = ArchiveModel(
            programme: Programme(id: "1", name: "News", cover: nil), repository: repository)
        await model.load()
        let dates = ProgrammeQuery.dates(programmeID: "1")
        let contents = ProgrammeQuery.contents(programmeID: "1", dateID: "20")
        await repository.publish(
            dates, items: .dates([BroadcastDate(id: "20", date: "2026-10-22")]))
        for _ in 0..<100 where !(await repository.isObserving(contents)) {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await repository.isObserving(contents))

        await repository.failRefresh(dates)
        await model.refresh()
        #expect(model.warning != nil)
        #expect(model.isLoading)

        await repository.publish(contents, items: .contents([]))
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(1)) }
        #expect(!model.isLoading)
        model.stop()
    }
}
