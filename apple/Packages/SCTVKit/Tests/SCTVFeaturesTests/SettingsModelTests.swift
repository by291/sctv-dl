import Foundation
import SCTVCore
import Testing

@testable import SCTVFeatures

@MainActor struct SettingsModelTests {
    @Test func editAfterFailedLoadPersistsWhenRetryRecoversStoredRevision() async throws {
        let repository = RecoveringPreferenceRepository()
        let model = SettingsModel(repository: repository)
        await model.load()
        model.change { $0.appearance = .light }
        await model.flush()
        #expect(!model.isPersisted)

        await repository.recover()
        await model.flush()

        let stored = await repository.stored()
        #expect(stored.value.appearance == .light)
        #expect(stored.acceptedRevision > 5)
        #expect(model.value.appearance == .light)
        #expect(model.isPersisted)
    }

    @Test func editDuringRecoveryRetryWinsOverEarlierDesiredValue() async throws {
        let repository = RecoveringPreferenceRepository()
        let model = SettingsModel(repository: repository)
        await model.load()
        model.change { $0.appearance = .light }
        await model.flush()
        await repository.recover()
        await repository.blockNextSave()

        let retry = Task { await model.flush() }
        await repository.waitUntilSaveBlocked()
        model.change { $0.appearance = .system }
        await repository.resumeBlockedSave()
        await retry.value
        await model.flush()

        #expect((await repository.stored()).value.appearance == .system)
        #expect(model.value.appearance == .system)
        #expect(model.isPersisted)
    }
}

private actor RecoveringPreferenceRepository: PreferenceRepository {
    private var available = false
    private var snapshot = PreferenceSnapshot(
        value: Preferences(appearance: .dark), acceptedRevision: 5,
        isPersisted: true, warning: nil)
    private var observers: [UUID: AsyncStream<PreferenceSnapshot>.Continuation] = [:]
    private var shouldBlockSave = false
    private var blockedSave: CheckedContinuation<Void, Never>?
    private var saveWaiter: CheckedContinuation<Void, Never>?

    func updates() -> AsyncStream<PreferenceSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(
                available
                    ? snapshot
                    : PreferenceSnapshot(
                        value: Preferences(), acceptedRevision: 0, isPersisted: false,
                        warning: .loadFailed("Unavailable")))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    func save(_ preferences: Preferences, editRevision: UInt64) async throws {
        guard available else { throw PreferenceFixtureError.unavailable }
        if shouldBlockSave {
            shouldBlockSave = false
            await withCheckedContinuation { continuation in
                blockedSave = continuation
                saveWaiter?.resume()
                saveWaiter = nil
            }
        }
        guard editRevision > snapshot.acceptedRevision else {
            throw PreferenceFixtureError.staleRevision
        }
        snapshot = PreferenceSnapshot(
            value: preferences, acceptedRevision: editRevision, isPersisted: true, warning: nil)
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    func flush() throws {
        guard available else { throw PreferenceFixtureError.unavailable }
    }
    func recover() { available = true }
    func blockNextSave() { shouldBlockSave = true }
    func waitUntilSaveBlocked() async {
        if blockedSave != nil { return }
        await withCheckedContinuation { saveWaiter = $0 }
    }
    func resumeBlockedSave() {
        blockedSave?.resume()
        blockedSave = nil
    }
    func stored() -> PreferenceSnapshot { snapshot }
    private func remove(_ id: UUID) { observers.removeValue(forKey: id) }
}

private enum PreferenceFixtureError: Error { case unavailable, staleRevision }
