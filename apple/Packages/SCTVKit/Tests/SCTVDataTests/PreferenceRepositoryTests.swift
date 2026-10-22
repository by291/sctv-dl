import Foundation
import GRDB
import SCTVCore
import Testing

@testable import SCTVData

struct PreferenceRepositoryTests {
    @Test func failedLoadCannotOverwriteStoredPreferencesAndCanRetry() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        try await database.write { db in
            try db.execute(
                sql:
                    "INSERT INTO preferences (key, value, edit_revision) VALUES ('user', 'invalid-json', 5)"
            )
        }
        let repository = SQLitePreferenceRepository(database: database)

        let failed = await repository.current()
        #expect(!failed.isPersisted)
        #expect(failed.warning != nil)
        await #expect(throws: PreferenceStorageError.self) {
            try await repository.save(Preferences(), editRevision: 6)
        }
        let stored: String? = try await database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM preferences WHERE key = 'user'")
        }
        #expect(stored == "invalid-json")

        try await database.write { db in
            try db.execute(
                sql: "UPDATE preferences SET value = ? WHERE key = 'user'",
                arguments: ["{\"appearance\":\"dark\"}"])
        }
        let recovered = await repository.current()
        #expect(recovered.isPersisted)
        #expect(recovered.value.appearance == .dark)
        #expect(recovered.acceptedRevision == 5)
    }

    @Test func delayedLoadCannotReplaceLocalEdit() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        let repository = SQLitePreferenceRepository(database: database)
        var edited = Preferences()
        edited.appearance = .dark
        try await repository.save(edited, editRevision: 2)
        try await repository.flush()
        var first = await repository.updates().makeAsyncIterator()
        var second = await repository.updates().makeAsyncIterator()
        #expect(await first.next()?.value == edited)
        #expect(await second.next()?.value == edited)
        var stale = Preferences()
        stale.appearance = .light
        await #expect(throws: PreferenceStorageError.self) {
            try await repository.save(stale, editRevision: 1)
        }
        let current = await repository.current()
        #expect(current.value == edited)
        #expect(current.acceptedRevision == 2)
        #expect(current.isPersisted)
        let reopened = SQLitePreferenceRepository(database: database)
        #expect(await reopened.current().value == edited)
    }

    @Test func failedWriteKeepsDesiredValueRetryable() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        try await database.write { db in
            try db.execute(
                sql:
                    "CREATE TRIGGER reject_preferences BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'blocked'); END"
            )
        }
        let repository = SQLitePreferenceRepository(database: database)
        var edited = Preferences()
        edited.appearance = .dark
        try? await repository.save(edited, editRevision: 1)
        let pending = await repository.current()
        #expect(pending.value == edited)
        #expect(!pending.isPersisted)
        await #expect(throws: (any Error).self) { try await repository.flush() }
        try await database.write { db in try db.execute(sql: "DROP TRIGGER reject_preferences") }
        try await repository.flush()
        #expect(await repository.current().isPersisted)
    }

    @Test func twoObserversReceiveTheAcceptedEdit() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        let repository = SQLitePreferenceRepository(database: database)
        var first = await repository.updates().makeAsyncIterator()
        var second = await repository.updates().makeAsyncIterator()
        _ = await first.next()
        _ = await second.next()

        var edited = Preferences()
        edited.playbackQuality = .smooth
        try await repository.save(edited, editRevision: 1)

        _ = await first.next()
        _ = await second.next()
        let firstPersisted = await first.next()
        let secondPersisted = await second.next()
        #expect(firstPersisted?.value == edited)
        #expect(firstPersisted?.isPersisted == true)
        #expect(secondPersisted == firstPersisted)
    }

    @Test func competingSameRevisionEditsRejectSecondWindow() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        let repository = SQLitePreferenceRepository(database: database)
        var first = await repository.updates().makeAsyncIterator()
        var second = await repository.updates().makeAsyncIterator()
        let initial = await first.next()
        #expect(await second.next()?.acceptedRevision == initial?.acceptedRevision)

        var dark = Preferences()
        dark.appearance = .dark
        try await repository.save(dark, editRevision: 1)
        var light = Preferences()
        light.appearance = .light
        await #expect(throws: PreferenceStorageError.self) {
            try await repository.save(light, editRevision: 1)
        }
        #expect(await repository.current().value == dark)
        #expect(await repository.current().isPersisted)
    }

    @Test func flushRejectsStaleDatabaseRevisionAndKeepsPendingEdit() async throws {
        let database = try DatabaseQueue()
        try UserMigrations.migrator.migrate(database)
        let repository = SQLitePreferenceRepository(database: database)
        _ = await repository.current()
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO preferences (key, value, edit_revision) VALUES ('user', ?, 2)",
                arguments: ["{\"appearance\":\"light\"}"])
        }
        var dark = Preferences()
        dark.appearance = .dark
        await #expect(throws: PreferenceStorageError.self) {
            try await repository.save(dark, editRevision: 1)
        }
        let pending = await repository.current()
        #expect(pending.value == dark)
        #expect(!pending.isPersisted)
        #expect(pending.warning != nil)
        await #expect(throws: PreferenceStorageError.self) { try await repository.flush() }
    }
}
