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
    public private(set) var isLoading = true
    public var scrollAnchor: String?
    public var ascending = true {
        didSet {
            if ascending != oldValue { rebuildContentGroups() }
        }
    }

    private struct ContentGroups {
        var fullEpisodes: [ProgrammeContent] = []
        var clips: [ProgrammeContent] = []
    }

    private var contentGroups = ContentGroups()

    private let repository: any ProgrammeRepository
    private var datesRequestOwner = UUID()
    private var contentsRequestOwner = UUID()
    private var restoredDateID: String?
    private var datesObservation: Task<Void, Never>?
    private var contentsObservation: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var contentsGeneration = UUID()
    private var lifecycleToken = UUID()
    private var isRunning = false

    public init(
        programme: Programme, repository: any ProgrammeRepository, restoredDateID: String? = nil
    ) {
        self.programme = programme
        self.repository = repository
        self.restoredDateID = restoredDateID
    }

    public var broadcast: BroadcastDate? { dates.first { $0.id == selectedDateID } }

    public var fullEpisodes: [ProgrammeContent] { contentGroups.fullEpisodes }

    public var clips: [ProgrammeContent] { contentGroups.clips }

    public var selectedContents: [ProgrammeContent] {
        contents.filter { selection.contains($0.id) }
    }

    public var hasPendingUpdate: Bool { pendingDates != nil || pendingContents != nil }

    private var contentQuery: ProgrammeQuery? {
        selectedDateID.map { .contents(programmeID: programme.id, dateID: $0) }
    }

    public func load() async {
        guard !isRunning else { return }

        isRunning = true
        if contents.isEmpty { isLoading = true }
        lifecycleToken = UUID()
        datesRequestOwner = UUID()
        let activeLifecycle = lifecycleToken

        let source = await repository.observe(.dates(programmeID: programme.id))
        guard isRunning, lifecycleToken == activeLifecycle else { return }

        datesObservation = Task { [weak self] in
            for await update in source {
                guard !Task.isCancelled, let self, isRunning, lifecycleToken == activeLifecycle
                else { break }

                pendingDates = update.pending
                if case .refreshFailed(let message) = update.warning {
                    warning = message
                }

                guard case .dates(let values) = update.accepted?.items else { continue }

                dates = values
                rebuildContentGroups()
                if values.isEmpty {
                    await clearDate()
                    guard isRunning, lifecycleToken == activeLifecycle else { break }
                    isLoading = false
                    continue
                }
                if !values.contains(where: { $0.id == selectedDateID }) {
                    let candidate = values.first { $0.id == restoredDateID } ?? values.first
                    restoredDateID = nil
                    if let candidate { await selectDate(candidate.id) } else { await clearDate() }
                } else if let id = selectedDateID, contentsObservation == nil {
                    // Returning from playback reconnects ownership without removing
                    // the rows that SwiftUI uses to retain the exact scroll offset.
                    await observeContents(id)
                }
            }
        }

        await refresh()
    }

    public func refresh() async {
        guard isRunning else { return }

        let activeLifecycle = lifecycleToken
        let owner = datesRequestOwner
        let query = ProgrammeQuery.dates(programmeID: programme.id)

        do {
            try await repository.refresh(query, owner: owner)
            if lifecycleToken == activeLifecycle { warning = nil }
        } catch {
            if lifecycleToken == activeLifecycle {
                warning = error.localizedDescription
                // Once dates exist, selectDate owns loading even while it is
                // releasing the previous date and selectedDateID is temporarily nil.
                if dates.isEmpty { isLoading = false }
            }
        }

        // Refresh can acquire ownership after stop has already released this lifecycle.
        if lifecycleToken != activeLifecycle { await repository.cancel(query, owner: owner) }
    }

    public func selectDate(_ id: String) async {
        guard isRunning, selectedDateID != id, dates.contains(where: { $0.id == id }) else {
            return
        }

        let requestGeneration = UUID()
        contentsGeneration = requestGeneration
        isLoading = true
        warning = nil

        await clearDate()
        guard contentsGeneration == requestGeneration else { return }
        selectedDateID = id
        await observeContents(id)
    }

    private func observeContents(_ id: String) async {
        let requestGeneration = UUID()
        contentsGeneration = requestGeneration
        contentsRequestOwner = UUID()
        let owner = contentsRequestOwner
        let query = ProgrammeQuery.contents(programmeID: programme.id, dateID: id)
        let source = await repository.observe(query)
        guard isRunning, contentsGeneration == requestGeneration else { return }

        contentsObservation = Task { [weak self] in
            for await update in source {
                guard !Task.isCancelled, let self, contentsGeneration == requestGeneration else {
                    break
                }

                if case .contents(let values) = update.accepted?.items {
                    contents = values
                    rebuildContentGroups()
                    isLoading = false
                    warning = nil
                }

                pendingContents = update.pending
                if case .refreshFailed(let message) = update.warning {
                    warning = message
                }
            }
        }

        do {
            try await repository.refresh(query, owner: owner)
        } catch {
            if contentsGeneration == requestGeneration {
                warning = error.localizedDescription
                isLoading = false
            }
        }

        if contentsGeneration != requestGeneration { await repository.cancel(query, owner: owner) }
        // Only an accepted snapshot can establish an empty result. Refresh completion
        // can precede delivery to the observation task.
    }

    public func setSelection(_ ids: Set<String>) {
        selection = ids
        guard let query = contentQuery else { return }

        let previousSelectionChange = selectionTask
        let repository = repository
        let owner = contentsRequestOwner

        // Serialize ownership changes so a late clear cannot unlock a newer selection.
        selectionTask = Task {
            await previousSelectionChange?.value
            await repository.setSelectionActive(!ids.isEmpty, for: query, owner: owner)
        }
    }

    public func acceptUpdate() async {
        guard selection.isEmpty, isRunning else { return }

        let requestGeneration = contentsGeneration
        let datesUpdate = pendingDates
        let contentsUpdate = pendingContents
        do {
            if let datesUpdate {
                try await repository.accept(datesUpdate.query, revision: datesUpdate.revision)
                guard contentsGeneration == requestGeneration, isRunning else { return }
                if let query = contentQuery {
                    let owner = contentsRequestOwner
                    do {
                        try await repository.refresh(query, owner: owner)
                    } catch {
                        if contentsGeneration != requestGeneration {
                            await repository.cancel(query, owner: owner)
                        }
                        throw error
                    }
                    if contentsGeneration != requestGeneration {
                        await repository.cancel(query, owner: owner)
                    }
                }
                // A refreshed content revision requires its own explicit acceptance.
            } else if let contentsUpdate {
                try await repository.accept(contentsUpdate.query, revision: contentsUpdate.revision)
            }
        } catch {
            if contentsGeneration == requestGeneration { warning = error.localizedDescription }
        }
    }

    public func stop() {
        isRunning = false
        lifecycleToken = UUID()
        datesObservation?.cancel()
        datesObservation = nil
        contentsObservation?.cancel()
        contentsObservation = nil
        releaseOwnership()
        contentsGeneration = UUID()
    }

    private func releaseOwnership() {
        setSelection([])

        let query = contentQuery
        let datesQuery = ProgrammeQuery.dates(programmeID: programme.id)
        let datesRequestOwner = datesRequestOwner
        let contentsRequestOwner = contentsRequestOwner
        let repository = repository
        let previousSelectionChange = selectionTask
        selectionTask = Task {
            await previousSelectionChange?.value
            await repository.cancel(datesQuery, owner: datesRequestOwner)
            if let query { await repository.cancel(query, owner: contentsRequestOwner) }
        }
    }

    private func clearDate() async {
        let previousContentsQuery = contentQuery
        let previousContentsOwner = contentsRequestOwner
        setSelection([])
        let selectionChange = selectionTask
        contentsObservation?.cancel()
        contentsObservation = nil

        selectedDateID = nil
        contents = []
        contentGroups = ContentGroups()
        pendingContents = nil

        await selectionChange?.value
        if let previousContentsQuery {
            await repository.cancel(previousContentsQuery, owner: previousContentsOwner)
            await repository.setSelectionActive(
                false, for: previousContentsQuery, owner: previousContentsOwner)
        }
    }

    private func rebuildContentGroups() {
        let date = broadcast?.date ?? ""
        var groups = ContentGroups()

        for content in contents {
            if ProgrammeRules.isFullEpisode(
                title: content.title, programmeName: programme.name, broadcastDate: date)
            {
                groups.fullEpisodes.append(content)
            } else {
                groups.clips.append(content)
            }
        }

        groups.clips = ProgrammeRules.sortClips(groups.clips, ascending: ascending)
        // Scroll-anchor updates redraw the archive. Keep date parsing and sorting out
        // of those render passes; only accepted data or ordering changes rebuild groups.
        contentGroups = groups
    }

    isolated deinit {
        datesObservation?.cancel()
        contentsObservation?.cancel()

        let query = contentQuery
        let datesQuery = ProgrammeQuery.dates(programmeID: programme.id)
        let datesRequestOwner = datesRequestOwner
        let contentsRequestOwner = contentsRequestOwner
        let repository = repository
        let previousSelectionChange = selectionTask
        Task {
            await previousSelectionChange?.value
            await repository.cancel(datesQuery, owner: datesRequestOwner)
            if let query {
                await repository.cancel(query, owner: contentsRequestOwner)
                await repository.setSelectionActive(false, for: query, owner: contentsRequestOwner)
            }
        }
    }
}
