import Foundation
import Observation
import SCTVCore
import SCTVData
import SCTVFeatures
import SCTVMedia
import SwiftUI

@MainActor @Observable
final class AppDependencies {
    let programmes: CachedProgrammeRepository
    let favourites: SQLiteFavouriteRepository
    let history: SQLiteHistoryRepository
    let settings: SettingsModel
    let resolver: PlaybackRequestResolver
    let cache: CacheMaintenance
    let downloads: DownloadDependencies
    let player: PlayerSession
    let root: URL

    init() throws {
        let manager = FileManager.default
        var support = try manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixtures") {
                support = manager.temporaryDirectory.appending(path: UUID().uuidString)
            }
        #endif

        root = support.appending(path: "SCTV", directoryHint: .isDirectory)
        let locations = StorageLocations(root: root)
        let stores = try DatabaseFactory.open(at: locations)

        var api: any ProgrammeAPI = try ProgrammeHTTPClient(
            identity: InstallationIdentity(location: locations.installationIdentity))
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixtures") {
                api = FixtureProgrammeAPI()
            }
        #endif

        programmes = CachedProgrammeRepository(api: api, database: stores.runtime)
        favourites = SQLiteFavouriteRepository(database: stores.user)
        history = SQLiteHistoryRepository(database: stores.user)

        var playback = PlaybackCoordinator()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixtures") {
                playback = PlaybackCoordinator(transport: FixtureMediaTransport())
            }
        #endif
        player = PlayerSession(history: history, playback: playback)

        settings = SettingsModel(repository: SQLitePreferenceRepository(database: stores.user))
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixtures"),
                ProcessInfo.processInfo.arguments.contains("--ui-dark")
            {
                settings.change { $0.appearance = .dark }
            }
        #endif

        resolver = PlaybackRequestResolver(
            api: api, history: history)
        cache = CacheMaintenance(database: stores.runtime)
        downloads = try DownloadDependencies(stores: stores, root: root)
        #if os(macOS)
            NativeApplicationDelegate.dependencies = self
        #endif

        Task { await downloads.start() }
    }
}
