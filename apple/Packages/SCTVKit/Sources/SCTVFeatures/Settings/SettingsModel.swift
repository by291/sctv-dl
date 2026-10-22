import Foundation
import Observation
import SCTVCore

@MainActor @Observable
public final class SettingsModel {
    public private(set) var value = Preferences()
    public private(set) var warning: String?
    public private(set) var isPersisted = true
    private let repository: any PreferenceRepository
    private var revision: UInt64 = 0
    private var pendingEdit: (value: Preferences, token: UUID)?
    private var observation: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    public init(repository: any PreferenceRepository) { self.repository = repository }

    public func load() async {
        guard observation == nil else { return }
        let source = await repository.updates()
        observation = Task { [weak self] in
            for await snapshot in source {
                guard !Task.isCancelled, let self else { break }
                if let pendingEdit {
                    // A recovered disk revision may be newer than an edit made during failed load.
                    // Keep the user's intent visible until that value is durably accepted.
                    revision = max(revision, snapshot.acceptedRevision + 1)
                    if snapshot.value == pendingEdit.value, snapshot.isPersisted {
                        self.pendingEdit = nil
                        value = snapshot.value
                        isPersisted = true
                        warning = nil
                    } else {
                        isPersisted = false
                        switch snapshot.warning {
                        case .loadFailed(let text), .saveFailed(let text): warning = text
                        case nil: break
                        }
                    }
                    continue
                }
                guard snapshot.acceptedRevision >= revision else { continue }
                value = snapshot.value
                revision = snapshot.acceptedRevision
                isPersisted = snapshot.isPersisted
                switch snapshot.warning {
                case .loadFailed(let text), .saveFailed(let text): warning = text
                case nil: warning = nil
                }
            }
        }
    }

    public func change(_ update: (inout Preferences) -> Void) {
        update(&value)
        revision += 1
        isPersisted = false
        let preferences = value
        let token = UUID()
        pendingEdit = (preferences, token)
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            guard let self, pendingEdit?.token == token else { return }
            let edit = revision
            do {
                try await repository.save(preferences, editRevision: edit)
                if pendingEdit?.token == token {
                    pendingEdit = nil
                    isPersisted = true
                    warning = nil
                }
            } catch {
                if pendingEdit?.token == token { warning = error.localizedDescription }
            }
        }
    }

    public func flush() async {
        let previous = saveTask
        let retry = Task { [weak self] in
            await previous?.value
            await self?.retryPendingEdit()
        }
        saveTask = retry
        await retry.value
    }

    private func retryPendingEdit() async {
        do { try await repository.flush() } catch {
            warning = error.localizedDescription
            return
        }
        guard pendingEdit != nil else { return }
        let source = await repository.updates()
        var iterator = source.makeAsyncIterator()
        guard let authoritative = await iterator.next() else { return }
        guard let pendingEdit else { return }
        if case .loadFailed(let text) = authoritative.warning {
            warning = text
            return
        }
        if authoritative.value == pendingEdit.value, authoritative.isPersisted {
            self.pendingEdit = nil
            revision = max(revision, authoritative.acceptedRevision)
            isPersisted = true
            warning = nil
            return
        }
        revision = max(revision, authoritative.acceptedRevision) + 1
        let edit = revision
        do {
            try await repository.save(pendingEdit.value, editRevision: edit)
            if self.pendingEdit?.token == pendingEdit.token {
                self.pendingEdit = nil
                isPersisted = true
                warning = nil
            }
        } catch {
            if self.pendingEdit?.token == pendingEdit.token {
                warning = error.localizedDescription
            }
        }
    }

    isolated deinit { observation?.cancel() }
}
