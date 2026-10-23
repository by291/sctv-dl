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
        #endif
        let programme = app.buttons["四川新闻"]
        XCTAssertTrue(programme.waitForExistence(timeout: 15))
        activate(programme)
        let menu = app.descendants(matching: .any)["content-actions-30"].firstMatch
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
        activate(app.descendants(matching: .any)["download-content-30"].firstMatch)
        #if os(macOS)
            let acknowledge = app.windows.buttons["好"].firstMatch
        #else
            let acknowledge = app.buttons["好"].firstMatch
        #endif
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        activate(acknowledge)
        activate(app.descendants(matching: .any)["下载"].firstMatch)
        let completed = app.descendants(matching: .any)["download-30-completed"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 20))
        #if os(iOS)
            app.buttons["选择"].tap()
            XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
            app.buttons["完成"].tap()
            XCTAssertTrue(app.buttons["选择"].exists)
        #endif
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
