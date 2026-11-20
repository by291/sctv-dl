import XCTest

@MainActor
extension XCTestCase {
    func requireState(
        _ description: String,
        of element: XCUIElement,
        until condition: @escaping @MainActor (XCUIElement) -> Bool
    ) {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else {
                return false
            }
            return MainActor.assumeIsolated { condition(element) }
        }
        let settled = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed, description)
    }

    func playbackSeconds(_ progress: XCUIElement) -> Int {
        let value = progress.value as? String ?? ""
        let time = value.prefix(5).split(separator: ":")
        guard time.count == 2, let minutes = Int(time[0]), let seconds = Int(time[1]) else {
            return -1
        }
        let secondsPerMinute = 60
        return minutes * secondsPerMinute + seconds
    }

    #if os(macOS)
        func resizeWindow(_ window: XCUIElement, toWidth width: CGFloat) {
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            let tolerance: CGFloat = 4
            let difference = width - window.frame.width
            if abs(difference) > tolerance {
                let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                    .withOffset(CGVector(dx: -2, dy: -2))
                corner.click(
                    forDuration: 0.1,
                    thenDragTo: corner.withOffset(CGVector(dx: difference, dy: 0)))
            }
            requireState("Window did not reach width \(width)", of: window) {
                abs($0.frame.width - width) <= tolerance
            }
        }
    #endif
}
