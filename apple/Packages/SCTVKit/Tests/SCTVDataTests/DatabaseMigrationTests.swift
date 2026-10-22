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

    @Test func reopensUserDataAfterRuntimeRecreation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = StorageLocations(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldUser = try DatabaseQueue(path: locations.userDatabase.path)
        try UserMigrations.migrator.migrate(oldUser, upTo: "user-v1")
        try oldUser.write { db in
            try db.execute(
                sql: "INSERT INTO favourites (programme_id, created_at) VALUES ('42', 1)")
            try db.execute(
                sql:
                    "INSERT INTO history (programme_id, date_id, content_id, title, programme_name, position_ms, duration_ms, completed, updated_at) VALUES ('42', '7', '9', 'News', 'Programme', 25000, 100000, 0, 2)"
            )
        }
        let first = try DatabaseFactory.open(at: locations)
        #expect(
            try first.user.read { db in try UserMigrations.migrator.appliedMigrations(db) } == [
                "user-v1", "user-v2", "user-v3",
            ])
        try FileManager.default.removeItem(at: locations.runtimeDatabase)
        let reopened = try DatabaseFactory.open(at: locations)
        let count = try reopened.user.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM favourites")! + Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM history")!
        }
        #expect(count == 2)
        #expect(
            try reopened.runtime.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM programme_snapshots")
            } == 0)
        #expect(
            try reopened.runtime.read { db in
                try String.fetchOne(
                    db,
                    sql:
                        "SELECT type FROM pragma_table_info('programme_snapshots') WHERE name = 'revision'"
                )
            } == "TEXT")
    }
}
