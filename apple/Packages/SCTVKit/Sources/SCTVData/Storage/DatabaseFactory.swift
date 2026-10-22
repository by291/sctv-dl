import Foundation
import GRDB

public struct DatabaseStores: @unchecked Sendable {
    public let user: DatabaseQueue
    public let runtime: DatabaseQueue

    public init(user: DatabaseQueue, runtime: DatabaseQueue) {
        self.user = user
        self.runtime = runtime
    }
}

public enum DatabaseFactory {
    public enum StorageError: Error, Equatable, Sendable {
        case overlappingUserAndRuntime
    }

    public static func open(at locations: StorageLocations) throws -> DatabaseStores {
        let userPath = locations.userDatabase.standardizedFileURL.resolvingSymlinksInPath().path
        let runtimeDirectoryPath = locations.runtimeDatabase.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath().path
        guard userPath != runtimeDirectoryPath,
            !userPath.hasPrefix(
                runtimeDirectoryPath.hasSuffix("/")
                    ? runtimeDirectoryPath : runtimeDirectoryPath + "/")
        else { throw StorageError.overlappingUserAndRuntime }

        let manager = FileManager.default
        try manager.createDirectory(
            at: locations.userDatabase.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try manager.createDirectory(
            at: locations.runtimeDatabase.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        var backup = URLResourceValues()
        backup.isExcludedFromBackup = true
        var runtimeDirectory = locations.runtimeDatabase.deletingLastPathComponent()
        try runtimeDirectory.setResourceValues(backup)

        let user = try DatabaseQueue(path: locations.userDatabase.path)
        let runtime = try DatabaseQueue(path: locations.runtimeDatabase.path)
        try UserMigrations.migrator.migrate(user)
        try RuntimeMigrations.migrator.migrate(runtime)
        return DatabaseStores(user: user, runtime: runtime)
    }
}
