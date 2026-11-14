import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class CatalogueModel {
    public var search = ""
    public var favouritesOnly = false
    public var alphabetical = false
    public private(set) var programmes: [Programme] = []
    public private(set) var favouriteIDs: Set<String> = []
    public private(set) var pending: ProgrammeSnapshot?
    public private(set) var hasAcceptedSnapshot = false
    public private(set) var isLoading = false

    private var explorationID: String?
    private let repository: any ProgrammeRepository
    private let favourites: any FavouriteRepository
    private var catalogueWarning: String?
    private var favouritesWarning: String?
    private var lifecycleToken = UUID()
    private var refreshToken = UUID()
    private var isRunning = false
    private var observations: [Task<Void, Never>] = []

    public init(repository: any ProgrammeRepository, favourites: any FavouriteRepository) {
        self.repository = repository
        self.favourites = favourites
    }

    public var visibleProgrammes: [Programme] {
        let result = programmes.filter {
            (search.isEmpty || $0.name.localizedStandardContains(search))
                && (!favouritesOnly || favouriteIDs.contains($0.id))
        }
        return alphabetical
            ? result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : result
    }

    public var exploration: Programme? {
        programmes.first { $0.id == explorationID }
    }

    public var warning: String? { catalogueWarning ?? favouritesWarning }

    public func shuffleExploration() {
        let alternatives = programmes.filter { $0.id != explorationID }
        explorationID = (alternatives.isEmpty ? programmes : alternatives).randomElement()?.id
    }

    public func load() async {
        guard !isRunning else { return }

        isRunning = true
        lifecycleToken = UUID()
        let active = lifecycleToken
        let source = await repository.observe(.catalogue)
        let saved = await favourites.stateUpdates()
        guard isRunning, lifecycleToken == active else { return }

        observations = [
            Task { [weak self] in
                for await update in source {
                    guard !Task.isCancelled, let self, isRunning, lifecycleToken == active else {
                        break
                    }

                    if case .catalogue(let values) = update.accepted?.items {
                        programmes = values
                        // Preserve a valid choice through refreshes and accepted snapshots.
                        if exploration == nil { shuffleExploration() }
                        hasAcceptedSnapshot = true
                    }
                    pending = update.pending
                    if case .refreshFailed(let message) = update.warning {
                        catalogueWarning = message
                    }
                }
            },
            Task { [weak self] in
                for await state in saved {
                    guard !Task.isCancelled, let self, isRunning, lifecycleToken == active else {
                        break
                    }

                    favouriteIDs = state.desiredIDs
                    favouritesWarning = state.warning
                }
            },
        ]
        await refresh()
    }

    /// Refreshes the catalogue; only the most recent request may settle its UI.
    public func refresh() async {
        let request = UUID()
        refreshToken = request
        isLoading = true

        // The repository may return normally when a newer generation supersedes this call.
        defer {
            if refreshToken == request { isLoading = false }
        }

        do {
            try await repository.refresh(.catalogue)
            guard refreshToken == request else { return }

            catalogueWarning = nil
        } catch {
            guard refreshToken == request else { return }

            catalogueWarning = error.localizedDescription
        }
    }

    public func acceptUpdate() async {
        guard let pending else { return }
        do {
            try await repository.accept(.catalogue, revision: pending.revision)
            catalogueWarning = nil
        } catch {
            catalogueWarning = error.localizedDescription
        }
    }

    public func toggleFavourite(_ programme: Programme) async {
        do {
            try await favourites.set(
                programme.id, isFavourite: !favouriteIDs.contains(programme.id))
        } catch {
            favouritesWarning = error.localizedDescription
        }
    }

    public func stop() {
        isRunning = false
        lifecycleToken = UUID()
        refreshToken = UUID()
        isLoading = false

        for observation in observations { observation.cancel() }
        observations.removeAll()
    }

    isolated deinit { for observation in observations { observation.cancel() } }
}
