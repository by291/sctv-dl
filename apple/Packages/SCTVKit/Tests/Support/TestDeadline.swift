import Foundation

private enum TestDeadlineError: Error, CustomStringConvertible {
    case timedOut(String)
    case streamEnded(String)

    var description: String {
        switch self {
        case .timedOut(let event):
            "Timed out waiting for \(event)"
        case .streamEnded(let event):
            "Stream ended while waiting for \(event)"
        }
    }
}

private let testTimeout: Duration = .seconds(2)
private let pollingInterval: Duration = .milliseconds(5)

/// Waits for an observable test event, with a deadline and cancellation-aware polling.
public func waitForTestCondition(
    _ event: String,
    until condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + testTimeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            throw TestDeadlineError.timedOut(event)
        }
        try await Task.sleep(for: pollingInterval)
    }
}

/// Reads one element from a test stream, with only one outstanding reader at a time.
public func requireTestElement<Element: Sendable>(
    from stream: AsyncStream<Element>,
    _ event: String
) async throws -> Element {
    try await withThrowingTaskGroup(of: Element.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let element = await iterator.next() else {
                throw TestDeadlineError.streamEnded(event)
            }
            return element
        }
        group.addTask {
            try await Task.sleep(for: testTimeout)
            throw TestDeadlineError.timedOut(event)
        }
        defer { group.cancelAll() }
        guard let element = try await group.next() else {
            throw TestDeadlineError.streamEnded(event)
        }
        return element
    }
}
