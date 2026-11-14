import Foundation
import OSLog
import Observation
import SCTVCore
import SCTVData
import SCTVDownloads

@MainActor @Observable
final class DownloadDependencies {
    private static let logger = Logger(subsystem: "dev.sctvdl.apple", category: "downloads")

    let service: DownloadCoordinator
    let access: LocalDownloadedFileAccess
    let directories: SecurityScopedDirectories
    let export = FileExportService()

    private let native: BackgroundSessionDriver?
    private let destinationFile: URL
    private var startup: Task<Void, Never>?

    private(set) var destination: FileDestination
    private(set) var warning: String?

    init(stores: DatabaseStores, root: URL) throws {
        let staging = root.appending(path: "Runtime/Staging")
        let repository = SQLiteDownloadRepository(database: stores.runtime)
        directories = SecurityScopedDirectories(storage: root.appending(path: "Bookmarks"))
        destinationFile = root.appending(path: "download-destination.json")

        let usesFixtures = Self.usesFixtures
        let managed = try Self.managedDirectory(root: root, usesFixtures: usesFixtures)
        let publisher = try LocalFilePublisher(
            staging: staging, managed: managed, directories: directories)
        access = LocalDownloadedFileAccess(repository: repository, publisher: publisher)

        let drivers = try Self.transferDrivers(
            staging: staging, root: root, usesFixtures: usesFixtures)
        native = drivers.native
        service = DownloadCoordinator(
            repository: repository, transfer: drivers.service, publisher: publisher)

        destination = Self.loadDestination(from: destinationFile)
    }

    private static var usesFixtures: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--ui-fixtures")
        #else
            false
        #endif
    }

    private static func managedDirectory(root: URL, usesFixtures: Bool) throws -> URL {
        #if os(iOS)
            // Test sessions keep their downloads in the same disposable root as their database.
            if !usesFixtures {
                let documents = try FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil,
                    create: true)
                return documents.appending(path: "Downloads")
            }
        #endif
        return root.appending(path: "Downloads")
    }

    private static func transferDrivers(staging: URL, root: URL, usesFixtures: Bool) throws
        -> (service: any TransferDriver, native: BackgroundSessionDriver?)
    {
        #if DEBUG
            if usesFixtures {
                return (try FixtureTransferDriver(staging: staging), nil)
            }
        #endif
        let driver = try BackgroundSessionDriver(
            stagingRoot: staging, resumeRoot: root.appending(path: "Runtime/Resume"))
        return (driver, driver)
    }

    private static func loadDestination(from file: URL) -> FileDestination {
        do {
            return try JSONDecoder().decode(FileDestination.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .applicationManaged
        } catch {
            // Leave the saved selection available for recovery rather than overwriting it.
            logger.warning(
                "Download destination could not be loaded: \(error.localizedDescription, privacy: .private)"
            )
            return .applicationManaged
        }
    }

    func start() async {
        if let startup {
            await startup.value
            return
        }
        let task = Task {
            if let native {
                await native.restoreSessions()
                await BackgroundEventsBridge.shared.install(native)
            }
            do {
                try await service.reconcile()
                warning = nil
            } catch {
                Self.logger.error(
                    "Download recovery failed: \(error.localizedDescription, privacy: .private)")
                warning = "下载状态尚未恢复，请稍后重试。"
            }
        }
        startup = task
        await task.value
        if warning != nil { startup = nil }
    }

    func chooseDirectory(_ url: URL) async throws {
        let id = try await directories.authorize(url)
        let next = FileDestination.external(bookmarkID: id)
        try JSONEncoder().encode(next).write(to: destinationFile, options: .atomic)
        destination = next
    }

    func useManagedDirectory() throws {
        try JSONEncoder().encode(FileDestination.applicationManaged).write(
            to: destinationFile, options: .atomic)
        destination = .applicationManaged
    }
}
