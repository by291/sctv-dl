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
            let emptyDownloads = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            emptyDownloads.name = "mac-downloads-empty-centered"
            emptyDownloads.lifetime = .keepAlways
            add(emptyDownloads)
            let contentCenter =
                (app.splitters.firstMatch.frame.maxX + app.windows.firstMatch.frame.maxX) / 2
            XCTAssertEqual(app.staticTexts["暂无下载"].frame.midX, contentCenter, accuracy: 4)
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

        func testStorageActionsKeepDirectoryAndCacheOperationsSeparate() {
            for dark in [false, true] {
                let app = launchFixtures(dark: dark)
                app.buttons["设置"].firstMatch.click()
                let change = app.buttons["settings-change-directory"]
                XCTAssertTrue(change.waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["恢复默认"].exists)
                let clear = app.buttons["settings-clear-cache"]
                let settingsWindow = app.windows.containing(
                    .button, identifier: "settings-change-directory"
                ).firstMatch
                settingsWindow.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -260)
                XCTAssertTrue(clear.isHittable)
                let shot = XCTAttachment(screenshot: settingsWindow.screenshot())
                shot.name = dark ? "storage-settings-dark" : "storage-settings-light"
                shot.lifetime = .keepAlways
                add(shot)

                change.click()
                XCTAssertTrue(app.buttons["选择下载目录"].waitForExistence(timeout: 5))
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertFalse(app.buttons["恢复默认"].exists)
                let initialClearFrame = clear.frame
                clear.click()
                let confirmation = settingsWindow.sheets.firstMatch
                XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["缓存已清理"].exists)
                let confirmationShot = XCTAttachment(screenshot: settingsWindow.screenshot())
                confirmationShot.name =
                    dark ? "cache-confirmation-dark" : "cache-confirmation-light"
                confirmationShot.lifetime = .keepAlways
                add(confirmationShot)
                confirmation.buttons["取消"].click()
                XCTAssertFalse(app.staticTexts["缓存已清理"].exists)
                clear.click()
                confirmation.buttons["清理缓存"].click()
                let result = settingsWindow.sheets.firstMatch
                XCTAssertTrue(result.staticTexts["缓存已清理"].waitForExistence(timeout: 5))
                let resultShot = XCTAttachment(screenshot: settingsWindow.screenshot())
                resultShot.name = dark ? "cache-result-dark" : "cache-result-light"
                resultShot.lifetime = .keepAlways
                add(resultShot)
                result.buttons["好"].click()
                XCTAssertFalse(app.staticTexts["缓存已清理"].exists)
                XCTAssertEqual(clear.frame.minY, initialClearFrame.minY, accuracy: 1)
                XCTAssertTrue(app.staticTexts["应用下载目录"].exists)
                app.terminate()
            }
        }

        private func launchFixtures(dark: Bool = false) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            if dark { app.launchArguments.append("--ui-dark") }
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
