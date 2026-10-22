import XCTest

@MainActor
final class ApplicationAcceptanceTests: XCTestCase {
    func testCatalogueArchiveLibraryAndSettings() {
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
        XCTAssertTrue(
            app.descendants(matching: .any)["完整节目"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "秋日里的城市故事")
            ).firstMatch
                .exists)
        let archive = XCTAttachment(screenshot: app.screenshot())
        archive.name = "native-archive"
        archive.lifetime = .keepAlways
        add(archive)

        #if os(macOS)
            activate(app.descendants(matching: .any)["资料库"].firstMatch)
        #else
            let library = app.buttons["资料库"].firstMatch
            activate(library)
        #endif
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10))
        activate(app.buttons["设置"])
        XCTAssertTrue(
            app.descendants(matching: .any)["首选画质"].firstMatch.waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "native-settings"
        settings.lifetime = .keepAlways
        add(settings)
    }

    #if os(iOS)
        func testLargeTextDarkArchiveSurvivesRotation() {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "-ApplePersistenceIgnoreState", "YES",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                "--ui-dark",
            ]
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait
            defer { XCUIDevice.shared.orientation = .portrait }
            app.launch()
            let programme = app.buttons["四川新闻"]
            XCTAssertTrue(programme.waitForExistence(timeout: 15))
            programme.tap()
            let content = app.descendants(matching: .any)["content-actions-30"].firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 10))
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(content.waitForExistence(timeout: 10))
            content.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["download-content-30"].firstMatch.waitForExistence(
                    timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "large-text-dark-rotated-archive"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    #endif

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
            element.click()
        #else
            element.tap()
        #endif
    }
}
