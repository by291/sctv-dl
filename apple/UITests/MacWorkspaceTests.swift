#if os(macOS)
    import XCTest

    @MainActor
    final class MacWorkspaceTests: XCTestCase {
        func testSidebarEmptySpaceSelectsSectionAndSettingsIsNotDuplicated() {
            let app = launchFixtures()
            let library = app.buttons["资料库"].firstMatch
            XCTAssertTrue(library.waitForExistence(timeout: 10))
            library.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()
            XCTAssertTrue(app.buttons["观看历史"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "设置").count, 1)

            let downloads = app.buttons["下载"].firstMatch
            downloads.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()
            XCTAssertTrue(app.staticTexts["暂无下载"].waitForExistence(timeout: 5))
            app.buttons["栏目"].firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
            ).click()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "设置").count, 1)
        }

        func testNativeArchiveBackButtonReturnsToCatalogue() {
            let app = launchFixtures()
            app.buttons["四川新闻"].click()
            let archive = app.scrollViews["archive-scroll"]
            XCTAssertTrue(archive.waitForExistence(timeout: 10))
            app.buttons["Back"].click()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 5))
        }

        private func launchFixtures() -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                app.typeKey("n", modifierFlags: .command)
            }
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            return app
        }
    }
#endif
