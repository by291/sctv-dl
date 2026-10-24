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
    public private(set) var warning: String?
    public private(set) var hasAcceptedSnapshot = false
    public private(set) var isLoading = false

    private var explorationID: String?
    private let repository: any ProgrammeRepository
    private let favourites: any FavouriteRepository
    private var lifecycle = UUID()
    private var running = false
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

    public func shuffleExploration() {
        let alternatives = programmes.filter { $0.id != explorationID }
        explorationID = (alternatives.isEmpty ? programmes : alternatives).randomElement()?.id
    }

    public func load() async {
        guard !running else { return }
        running = true
        lifecycle = UUID()
        let active = lifecycle
        let source = await repository.observe(.catalogue)
        let saved = await favourites.stateUpdates()
        guard running, lifecycle == active else { return }
        observations = [
            Task { [weak self] in
                for await update in source {
                    guard !Task.isCancelled, let self, running, lifecycle == active else { break }
                    if case .catalogue(let values) = update.accepted?.items {
                        programmes = values
                        // Preserve a valid choice through refreshes and accepted snapshots.
                        if exploration == nil { shuffleExploration() }
                        hasAcceptedSnapshot = true
                    }
                    pending = update.pending
                    if case .refreshFailed(let message) = update.warning { warning = message }
                }
            },
            Task { [weak self] in
                for await state in saved {
                    guard !Task.isCancelled, let self, running, lifecycle == active else { break }
                    favouriteIDs = state.desiredIDs
                    if let message = state.warning { warning = message }
                }
            },
        ]
        await refresh()
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.refresh(.catalogue)
            warning = nil
        } catch { warning = error.localizedDescription }
    }

    public func acceptUpdate() async {
        guard let pending else { return }
        do { try await repository.accept(.catalogue, revision: pending.revision) } catch {
            warning = error.localizedDescription
        }
    }

    public func toggleFavourite(_ programme: Programme) async {
        do {
            try await favourites.set(
                programme.id, isFavourite: !favouriteIDs.contains(programme.id))
        } catch { warning = error.localizedDescription }
    }

    public func stop() {
        running = false
        lifecycle = UUID()
        for observation in observations { observation.cancel() }
        observations.removeAll()
    }

    isolated deinit { for observation in observations { observation.cancel() } }
}
