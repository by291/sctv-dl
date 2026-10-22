import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class ArchiveModel {
    public let programme: Programme
    public private(set) var dates: [BroadcastDate] = []
    public private(set) var selectedDateID: String?
    public private(set) var contents: [ProgrammeContent] = []
    public private(set) var selection: Set<String> = []
    public private(set) var pendingDates: ProgrammeSnapshot?
    public private(set) var pendingContents: ProgrammeSnapshot?
    public private(set) var warning: String?
    public private(set) var isLoading = false
    public var scrollAnchor: String?
    public var ascending = true

    private let repository: any ProgrammeRepository
    private var datesOwner = UUID()
    private var contentOwner = UUID()
    private var restoredDateID: String?
    private var datesObservation: Task<Void, Never>?
    private var contentsObservation: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var generation = UUID()
    private var lifecycle = UUID()
    private var running = false

    public init(
        programme: Programme, repository: any ProgrammeRepository, restoredDateID: String? = nil
    ) {
        self.programme = programme
        self.repository = repository
        self.restoredDateID = restoredDateID
    }

    public var broadcast: BroadcastDate? { dates.first { $0.id == selectedDateID } }
    public var fullEpisodes: [ProgrammeContent] { contents.filter(isFullEpisode) }
    public var clips: [ProgrammeContent] {
        ProgrammeRules.sortClips(contents.filter { !isFullEpisode($0) }, ascending: ascending)
    }
    public var selectedContents: [ProgrammeContent] {
        contents.filter { selection.contains($0.id) }
    }
    public var hasPendingUpdate: Bool { pendingDates != nil || pendingContents != nil }
    private var contentQuery: ProgrammeQuery? {
        selectedDateID.map { .contents(programmeID: programme.id, dateID: $0) }
    }

    public func load() async {
        guard !running else { return }
        running = true
        lifecycle = UUID()
        datesOwner = UUID()
        let active = lifecycle
        let source = await repository.observe(.dates(programmeID: programme.id))
        guard running, lifecycle == active else { return }
        datesObservation = Task { [weak self] in
            for await update in source {
                guard !Task.isCancelled, let self, running, lifecycle == active else { break }
                pendingDates = update.pending
                if case .refreshFailed(let message) = update.warning { warning = message }
                guard case .dates(let values) = update.accepted?.items else { continue }
                dates = values
                if !values.contains(where: { $0.id == selectedDateID }) {
                    let candidate = values.first { $0.id == restoredDateID } ?? values.first
                    restoredDateID = nil
                    if let candidate { await selectDate(candidate.id) } else { await clearDate() }
                }
            }
        }
        await refresh()
    }

    public func refresh() async {
        guard running else { return }
        let active = lifecycle
        let owner = datesOwner
        let query = ProgrammeQuery.dates(programmeID: programme.id)
        do {
            try await repository.refresh(query, owner: owner)
            if lifecycle == active { warning = nil }
        } catch { if lifecycle == active { warning = error.localizedDescription } }
        // Refresh can acquire ownership after stop has already released this lifecycle.
        if lifecycle != active { await repository.cancel(query, owner: owner) }
    }

    public func selectDate(_ id: String) async {
        guard running, selectedDateID != id, dates.contains(where: { $0.id == id }) else { return }
        let route = UUID()
        generation = route
        await clearDate()
        guard generation == route else { return }
        contentOwner = UUID()
        let owner = contentOwner
        selectedDateID = id
        let query = ProgrammeQuery.contents(programmeID: programme.id, dateID: id)
        let source = await repository.observe(query)
        guard running, generation == route else { return }
        contentsObservation = Task { [weak self] in
            for await update in source {
                guard !Task.isCancelled, let self, generation == route else { break }
                if case .contents(let values) = update.accepted?.items { contents = values }
                pendingContents = update.pending
                if case .refreshFailed(let message) = update.warning { warning = message }
            }
        }
        isLoading = true
        do { try await repository.refresh(query, owner: owner) } catch {
            if generation == route { warning = error.localizedDescription }
        }
        if generation != route { await repository.cancel(query, owner: owner) }
        if generation == route { isLoading = false }
    }

    public func setSelection(_ ids: Set<String>) {
        selection = ids
        guard let query = contentQuery else { return }
        let previous = selectionTask
        let repository = repository
        let owner = contentOwner
        // Serialize ownership changes so a late clear cannot unlock a newer selection.
        selectionTask = Task {
            await previous?.value
            await repository.setSelectionActive(!ids.isEmpty, for: query, owner: owner)
        }
    }

    public func acceptUpdate() async {
        guard selection.isEmpty, running else { return }
        let route = generation
        let datesUpdate = pendingDates
        let contentsUpdate = pendingContents
        do {
            if let datesUpdate {
                try await repository.accept(datesUpdate.query, revision: datesUpdate.revision)
                guard generation == route, running else { return }
                if let query = contentQuery {
                    let owner = contentOwner
                    do {
                        try await repository.refresh(query, owner: owner)
                    } catch {
                        if generation != route { await repository.cancel(query, owner: owner) }
                        throw error
                    }
                    if generation != route { await repository.cancel(query, owner: owner) }
                }
                // A refreshed content revision requires its own explicit acceptance.
            } else if let contentsUpdate {
                try await repository.accept(contentsUpdate.query, revision: contentsUpdate.revision)
            }
        } catch { if generation == route { warning = error.localizedDescription } }
    }

    public func stop() {
        running = false
        lifecycle = UUID()
        datesObservation?.cancel()
        datesObservation = nil
        contentsObservation?.cancel()
        contentsObservation = nil
        releaseOwnership()
        restoredDateID = selectedDateID
        selectedDateID = nil
        generation = UUID()
    }

    private func releaseOwnership() {
        setSelection([])
        let query = contentQuery
        let datesQuery = ProgrammeQuery.dates(programmeID: programme.id)
        let datesOwner = datesOwner
        let contentOwner = contentOwner
        let repository = repository
        let previous = selectionTask
        selectionTask = Task {
            await previous?.value
            await repository.cancel(datesQuery, owner: datesOwner)
            if let query { await repository.cancel(query, owner: contentOwner) }
        }
    }

    private func clearDate() async {
        let oldQuery = contentQuery
        let oldOwner = contentOwner
        setSelection([])
        let selectionChange = selectionTask
        contentsObservation?.cancel()
        contentsObservation = nil
        selectedDateID = nil
        contents = []
        pendingContents = nil
        await selectionChange?.value
        if let oldQuery {
            await repository.cancel(oldQuery, owner: oldOwner)
            await repository.setSelectionActive(false, for: oldQuery, owner: oldOwner)
        }
    }

    private func isFullEpisode(_ content: ProgrammeContent) -> Bool {
        ProgrammeRules.isFullEpisode(
            title: content.title, programmeName: programme.name,
            broadcastDate: broadcast?.date ?? "")
    }

    isolated deinit {
        datesObservation?.cancel()
        contentsObservation?.cancel()
        let query = contentQuery
        let datesQuery = ProgrammeQuery.dates(programmeID: programme.id)
        let datesOwner = datesOwner
        let contentOwner = contentOwner
        let repository = repository
        let previous = selectionTask
        Task {
            await previous?.value
            await repository.cancel(datesQuery, owner: datesOwner)
            if let query {
                await repository.cancel(query, owner: contentOwner)
                await repository.setSelectionActive(false, for: query, owner: contentOwner)
            }
        }
    }
}
