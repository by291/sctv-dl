import Foundation
import GRDB
import Testing

@testable import SCTVData

struct DatabaseMigrationTests {
    @Test func excludesOnlyDisjointRuntimeDirectoryFromBackup() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = StorageLocations(root: root)
        _ = try DatabaseFactory.open(at: defaults)

        let userExcluded = try defaults.userDatabase.resourceValues(forKeys: [
            .isExcludedFromBackupKey
        ]).isExcludedFromBackup
        let runtimeDirectory = defaults.runtimeDatabase.deletingLastPathComponent()
        let runtimeExcluded = try runtimeDirectory.resourceValues(forKeys: [
            .isExcludedFromBackupKey
        ]).isExcludedFromBackup
        #expect(userExcluded != true)
        #expect(runtimeExcluded == true)

        let custom = StorageLocations(
            userDatabase: root.appending(path: "CustomUser/user.sqlite"),
            runtimeDatabase: root.appending(path: "CustomCache/runtime.sqlite"),
            installationIdentity: root.appending(path: "CustomCache/identity")
        )
        _ = try DatabaseFactory.open(at: custom)
        #expect(
            try custom.userDatabase.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup != true)
        #expect(
            try custom.runtimeDatabase.deletingLastPathComponent().resourceValues(forKeys: [
                .isExcludedFromBackupKey
            ]).isExcludedFromBackup == true)

        let unsafe = StorageLocations(
            userDatabase: root.appending(path: "unsafe/user.sqlite"),
            runtimeDatabase: root.appending(path: "unsafe/runtime.sqlite"),
            installationIdentity: root.appending(path: "unsafe/identity")
        )
        #expect(throws: (any Error).self) {
            try DatabaseFactory.open(at: unsafe)
        }
        #expect(!FileManager.default.fileExists(atPath: unsafe.userDatabase.path))
    }

    @Test func reopensLegacyUserDataAfterRuntimeRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = StorageLocations(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try seedVersionOneDatabase(at: locations.userDatabase)

        let first = try DatabaseFactory.open(at: locations)
        try first.user.close()
        try first.runtime.close()
        try FileManager.default.removeItem(at: locations.runtimeDatabase)

        let reopened = try DatabaseFactory.open(at: locations)
        let favourites = SQLiteFavouriteRepository(database: reopened.user)
        #expect(try await favourites.ids() == ["42"])
        let preferences = SQLitePreferenceRepository(database: reopened.user)
        let saved = await preferences.current()
        #expect(saved.value.appearance == .dark)
        #expect(saved.acceptedRevision == 5)
        #expect(saved.isPersisted)

        let history = SQLiteHistoryRepository(database: reopened.user)
        let entries = try await history.entries()
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.content.programmeID == "42")
        #expect(entry.content.dateID == "7")
        #expect(entry.content.contentID == "9")
        #expect(entry.title == "News")
        #expect(entry.programmeName == "Programme")
        #expect(entry.broadcastDate.isEmpty)
        #expect(entry.cover?.absoluteString == "https://example.com/news.jpg")
        #expect(entry.positionMs == 25_000)
        #expect(entry.durationMs == 100_000)
        #expect(entry.updatedAt == Date(timeIntervalSince1970: 2))
        #expect(!entry.completed)
        #expect(
            try await reopened.runtime.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM programme_snapshots")
            } == 0)
        try reopened.user.close()
        try reopened.runtime.close()
    }

    private func seedVersionOneDatabase(at location: URL) throws {
        let database = try DatabaseQueue(path: location.path)
        // Keep the old schema and payload independent of the current migrations and codecs.
        var legacy = DatabaseMigrator()
        legacy.registerMigration("user-v1") { database in
            try database.execute(
                sql: """
                    CREATE TABLE favourites (
                        programme_id TEXT PRIMARY KEY,
                        created_at REAL NOT NULL
                    );
                    CREATE TABLE preferences (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL,
                        edit_revision INTEGER NOT NULL DEFAULT 0
                    );
                    CREATE TABLE history (
                        programme_id TEXT NOT NULL,
                        date_id TEXT NOT NULL,
                        content_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        programme_name TEXT NOT NULL,
                        cover TEXT,
                        position_ms INTEGER NOT NULL,
                        duration_ms INTEGER,
                        completed BOOLEAN NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (programme_id, date_id, content_id)
                    );
                    INSERT INTO favourites (programme_id, created_at) VALUES ('42', 1);
                    INSERT INTO preferences (key, value, edit_revision)
                    VALUES ('user', '{"appearance":"dark"}', 5);
                    INSERT INTO history (
                        programme_id, date_id, content_id, title, programme_name, cover,
                        position_ms, duration_ms, completed, updated_at
                    ) VALUES ('42', '7', '9', 'News', 'Programme',
                        'https://example.com/news.jpg', 25000, 100000, 0, 2);
                    """)
        }
        try legacy.migrate(database)
        try database.close()
    }
}
