import Foundation
import Testing

@testable import SCTVMedia

private actor AudioOperationProbe {
    var events: [String] = []
    private var release: CheckedContinuation<Void, Never>?

    func deactivate() async {
        events.append("deactivation started")
        await withCheckedContinuation { release = $0 }
        events.append("deactivation finished")
    }

    func configure() { events.append("configured replacement") }
    func finishDeactivation() {
        release?.resume()
        release = nil
    }
}

@MainActor struct AudioSessionOperationsTests {
    @Test func replacementWaitsForOldDeactivationWithoutBlockingTheMainActor() async throws {
        let operations = AudioSessionOperations()
        let probe = AudioOperationProbe()
        let closing = operations.perform { await probe.deactivate() }
        for _ in 0..<100 where await probe.events.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await probe.events == ["deactivation started"])
        let opening = operations.perform { await probe.configure() }

        // The main actor remains responsive while the native callback is outstanding.
        try await Task.sleep(for: .milliseconds(30))
        #expect(await probe.events == ["deactivation started"])
        await probe.finishDeactivation()
        try await closing.value
        try await opening.value
        #expect(
            await probe.events == [
                "deactivation started", "deactivation finished", "configured replacement",
            ])
    }

    @Test func failedDeactivationDoesNotPreventTheNextConfiguration() async throws {
        let operations = AudioSessionOperations()
        let probe = AudioOperationProbe()
        let closing = operations.perform { throw CocoaError(.featureUnsupported) }
        let opening = operations.perform { await probe.configure() }
        do {
            try await closing.value
            Issue.record("Expected the deactivation failure")
        } catch {}
        try await opening.value
        #expect(await probe.events == ["configured replacement"])
    }
}
