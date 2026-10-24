import XCTest

@MainActor
final class DownloadFlowTests: XCTestCase {
    func testDownloadedFixtureOpensInNativePlayer() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
        continueAfterFailure = false
        app.launch()
        #if os(macOS)
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                app.typeKey("n", modifierFlags: .command)
            }
            let window = app.windows["workspace-AppWindow-1"]
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            corner.click(
                forDuration: 0.1,
                thenDragTo: corner.withOffset(
                    CGVector(dx: 1180 - window.frame.width, dy: 0)))
        #endif
        let programme = app.buttons["四川新闻"]
        XCTAssertTrue(programme.waitForExistence(timeout: 15))
        activate(programme)
        for id in ["30", "31"] {
            let menu = app.descendants(matching: .any)["content-actions-\(id)"].firstMatch
            for _ in 0..<8 {
                if menu.exists && menu.isHittable { break }
                #if os(macOS)
                    app.scrollViews["archive-scroll"].scroll(byDeltaX: 0, deltaY: -300)
                #else
                    app.swipeUp()
                #endif
            }
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            activate(menu)
            activate(app.descendants(matching: .any)["download-content-\(id)"].firstMatch)
            #if os(macOS)
                let acknowledge = app.windows.buttons["好"].firstMatch
            #else
                let acknowledge = app.buttons["好"].firstMatch
            #endif
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
            activate(acknowledge)
        }
        activate(app.descendants(matching: .any)["下载"].firstMatch)
        let completed = app.descendants(matching: .any)["download-30-completed"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 20))
        let second = app.descendants(matching: .any)["download-31-completed"].firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 20))
        #if os(macOS)
            let firstCard = app.buttons["play-download-30"]
            let secondCard = app.buttons["play-download-31"]
            XCTAssertEqual(firstCard.frame.minY, secondCard.frame.minY, accuracy: 2)
            XCTAssertGreaterThan(abs(firstCard.frame.minX - secondCard.frame.minX), 300)
        #endif
        #if os(macOS)
            activate(app.buttons["play-download-30"])
            XCTAssertTrue(
                app.descendants(matching: .any)["native-player-ready"].firstMatch.waitForExistence(
                    timeout: 10))
            app.windows["player"].buttons["_XCUI:CloseWindow"].click()
        #endif
        activate(app.buttons["downloads-select"])
        let selection = app.buttons["select-download-30"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        activate(selection)
        XCTAssertTrue(app.staticTexts["已选 1 项"].waitForExistence(timeout: 5))
        activate(app.buttons["全选"])
        XCTAssertTrue(app.staticTexts["已选 2 项"].waitForExistence(timeout: 5))
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "download-two-column-selection"
        selected.lifetime = .keepAlways
        add(selected)
        activate(app.buttons["downloads-select"])
        activate(app.descendants(matching: .any)["play-download-30"].firstMatch)
        XCTAssertTrue(
            app.descendants(matching: .any)["native-player-ready"].firstMatch.waitForExistence(
                timeout: 20))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "downloaded-local-playback"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
            element.click()
        #else
            element.tap()
        #endif
    }
}
