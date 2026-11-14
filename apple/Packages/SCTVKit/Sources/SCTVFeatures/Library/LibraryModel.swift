import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class LibraryModel {
    public private(set) var entries: [HistoryEntry] = []
    public private(set) var warning: String?

    private let repository: any HistoryRepository
    private var isStartingObservation = false
    private var observation: Task<Void, Never>?

    public init(repository: any HistoryRepository) { self.repository = repository }

    public var continuing: [HistoryEntry] {
        Array(entries.filter { !$0.completed && $0.positionMs > 0 }.prefix(10))
    }

    /// Loads history and shares one observation between the library and history destinations.
    public func load() async {
        guard observation == nil, !isStartingObservation else { return }

        isStartingObservation = true
        defer { isStartingObservation = false }

        do {
            entries = try await repository.entries()
            warning = nil
        } catch {
            warning = error.localizedDescription
        }

        let source = await repository.updates()
        observation = Task { [weak self] in
            for await values in source {
                guard !Task.isCancelled, let self else { break }
                entries = values
            }
        }
    }

    public func remove(_ entry: HistoryEntry) async {
        do {
            try await repository.remove(entry.content)
            warning = nil
        } catch {
            warning = error.localizedDescription
        }
    }

    public func clear() async {
        do {
            try await repository.clear()
            warning = nil
        } catch {
            warning = error.localizedDescription
        }
    }

    isolated deinit { observation?.cancel() }
}
