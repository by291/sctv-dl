import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func testNativeHostLaunches() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["--media-probe", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        #if os(macOS)
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                app.typeKey("n", modifierFlags: .command)
            }
        #endif
        XCTAssertTrue(app.staticTexts["媒体验证"].waitForExistence(timeout: 10))
        #if os(macOS)
            app.buttons["载入测试视频"].click()
        #else
            app.buttons["载入测试视频"].tap()
        #endif
        XCTAssertTrue(app.staticTexts["player-ready"].waitForExistence(timeout: 25))
        #if os(macOS)
            app.buttons["跳至 8 秒"].click()
        #else
            app.buttons["跳至 8 秒"].tap()
        #endif
        XCTAssertTrue(app.staticTexts["已定位至 8 秒"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
