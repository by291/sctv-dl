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

        func testHistoryUsesTwoColumnsAndAdaptsToNarrowWindows() {
            let app = launchFixtures(arguments: ["--ui-long-content-titles"])
            let window = app.windows["workspace-AppWindow-1"]
            // AppKit can retain the frame from a previous narrow-window run.
            let initialCorner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            initialCorner.click(
                forDuration: 0.1,
                thenDragTo: initialCorner.withOffset(
                    CGVector(dx: 1180 - window.frame.width, dy: 0)))
            XCTAssertEqual(window.frame.width, 1180, accuracy: 4)
            app.buttons["exploration-cover"].click()
            for id in ["30", "31", "32"] {
                let clip = app.buttons["archive-play-\(id)"]
                XCTAssertTrue(clip.waitForExistence(timeout: 10))
                for _ in 0..<6 where !clip.isHittable {
                    app.scrollViews["archive-scroll"].scroll(byDeltaX: 0, deltaY: -220)
                }
                clip.click()
                XCTAssertTrue(
                    app.descendants(matching: .any)["native-player-ready"].firstMatch
                        .waitForExistence(timeout: 20))
                let progress = app.sliders["player-progress"]
                progress.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                    .click(
                        forDuration: 0.1,
                        thenDragTo: progress.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)))
                app.windows["player"].buttons["_XCUI:CloseWindow"].click()
            }
            app.buttons["资料库"].firstMatch.click()
            let long = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "秋日里的城市故事")
            ).firstMatch
            let short = app.descendants(matching: .any)["城市一刻"].firstMatch
            XCTAssertTrue(long.waitForExistence(timeout: 10))
            XCTAssertTrue(short.exists)
            let episode = app.descendants(matching: .any)["四川新闻（2026.10.22）"].firstMatch
            XCTAssertTrue(episode.exists)
            XCTAssertGreaterThan(episode.frame.minY, short.frame.minY + 80)
            XCTAssertEqual(long.frame.minY, short.frame.minY, accuracy: 2)
            XCTAssertGreaterThan(abs(long.frame.minX - short.frame.minX), 300)
            let libraryShot = XCTAttachment(screenshot: window.screenshot())
            libraryShot.name = "library-at-most-two-columns"
            libraryShot.lifetime = .keepAlways
            add(libraryShot)
            app.buttons["观看历史"].click()
            XCTAssertEqual(long.frame.minY, short.frame.minY, accuracy: 2)
            let wideShot = XCTAttachment(screenshot: window.screenshot())
            wideShot.name = "mac-history-two-columns"
            wideShot.lifetime = .keepAlways
            add(wideShot)

            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            corner.click(forDuration: 0.1, thenDragTo: corner.withOffset(CGVector(dx: -420, dy: 0)))
            XCTAssertEqual(long.frame.minX, short.frame.minX, accuracy: 2)
            XCTAssertGreaterThan(abs(long.frame.minY - short.frame.minY), 80)
            let narrowShot = XCTAttachment(screenshot: window.screenshot())
            narrowShot.name = "mac-history-one-column"
            narrowShot.lifetime = .keepAlways
            add(narrowShot)

            short.rightClick()
            app.menuItems["删除记录"].click()
            XCTAssertTrue(short.waitForNonExistence(timeout: 5))
            XCTAssertTrue(long.exists)
            long.click()
            XCTAssertTrue(
                app.descendants(matching: .any)["native-player-ready"].firstMatch
                    .waitForExistence(timeout: 20))
            app.windows["player"].buttons["_XCUI:CloseWindow"].click()
        }

        private func launchFixtures(dark: Bool = false, arguments: [String] = []) -> XCUIApplication
        {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            app.launchArguments += arguments
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
