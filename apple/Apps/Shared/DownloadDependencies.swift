import Foundation
import Observation
import SCTVCore
import SCTVData
import SCTVDownloads

@MainActor @Observable
final class DownloadDependencies {
    let service: DownloadCoordinator
    let access: LocalDownloadedFileAccess
    let directories: SecurityScopedDirectories
    let native: BackgroundSessionDriver?
    let export = FileExportService()
    private(set) var destination = FileDestination.applicationManaged
    private let destinationFile: URL
    private var startup: Task<Void, Never>?
    private(set) var warning: String?

    init(stores: DatabaseStores, root: URL) throws {
        let manager = FileManager.default
        let staging = root.appending(path: "Runtime/Staging")
        let repository = SQLiteDownloadRepository(database: stores.runtime)
        directories = SecurityScopedDirectories(storage: root.appending(path: "Bookmarks"))
        destinationFile = root.appending(path: "download-destination.json")
        #if os(iOS)
            var managed = try manager.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appending(path: "Downloads")
        #else
            var managed = root.appending(path: "Downloads")
        #endif
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixtures") {
                managed = root.appending(path: "Downloads")
            }
        #endif
        let publisher = try LocalFilePublisher(
            staging: staging, managed: managed, directories: directories)
        access = LocalDownloadedFileAccess(repository: repository, publisher: publisher)
        let transfer: any TransferDriver
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixtures") {
                native = nil
                transfer = try FixtureTransferDriver(staging: staging)
            } else {
                let driver = try BackgroundSessionDriver(
                    stagingRoot: staging, resumeRoot: root.appending(path: "Runtime/Resume"))
                native = driver
                transfer = driver
            }
        #else
            let driver = try BackgroundSessionDriver(
                stagingRoot: staging, resumeRoot: root.appending(path: "Runtime/Resume"))
            native = driver
            transfer = driver
        #endif
        service = DownloadCoordinator(
            repository: repository, transfer: transfer, publisher: publisher)
        if let data = try? Data(contentsOf: destinationFile),
            let saved = try? JSONDecoder().decode(FileDestination.self, from: data)
        {
            destination = saved
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
            } catch { warning = error.localizedDescription }
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
