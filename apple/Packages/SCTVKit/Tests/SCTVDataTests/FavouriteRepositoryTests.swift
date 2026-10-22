import Foundation
import GRDB
import SCTVCore
import Testing

@testable import SCTVData

struct FavouriteRepositoryTests {
    @Test func failedWritePreservesConfirmedState() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        let repository = SQLiteFavouriteRepository(database: database)
        try await repository.set("1", isFavourite: true)
        var first = await repository.updates().makeAsyncIterator()
        var second = await repository.updates().makeAsyncIterator()
        #expect(await first.next() == ["1"])
        #expect(await second.next() == ["1"])
        try await database.write { db in
            try db.execute(
                sql:
                    "CREATE TRIGGER reject_favourites BEFORE DELETE ON favourites BEGIN SELECT RAISE(ABORT, 'blocked'); END"
            )
        }
        await #expect(throws: (any Error).self) {
            try await repository.set("1", isFavourite: false)
        }
        #expect(try await repository.ids() == ["1"])
        let state = await repository.current()
        #expect(state.confirmedIDs == ["1"])
        #expect(state.desiredIDs == [])
        #expect(state.warning != nil)
        try await repository.set("2", isFavourite: true)
        let afterUnrelatedWrite = await repository.current()
        #expect(afterUnrelatedWrite.confirmedIDs == ["1", "2"])
        #expect(afterUnrelatedWrite.desiredIDs == ["2"])
        #expect(afterUnrelatedWrite.warning != nil)
    }

    @Test func failedInitialLoadShowsWarningThenRecovers() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        try await database.write { db in try db.execute(sql: "DROP TABLE favourites") }
        let repository = SQLiteFavouriteRepository(database: database)
        var observer = await repository.stateUpdates().makeAsyncIterator()
        let failed = await observer.next()
        #expect(failed?.warning != nil)
        await #expect(throws: (any Error).self) { try await repository.ids() }

        try await database.write { db in
            try db.execute(
                sql:
                    "CREATE TABLE favourites (programme_id TEXT PRIMARY KEY, created_at REAL NOT NULL)"
            )
            try db.execute(
                sql: "INSERT INTO favourites (programme_id, created_at) VALUES ('4', 1)")
        }
        #expect(try await repository.ids() == ["4"])
        var recovered: FavouriteSnapshot?
        for _ in 0..<3 {
            let next = await observer.next()
            if next?.confirmedIDs == ["4"] {
                recovered = next
                break
            }
        }
        #expect(recovered?.confirmedIDs == ["4"])
        #expect(recovered?.warning == nil)
    }
}
