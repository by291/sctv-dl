import XCTest

@MainActor
final class ApplicationAcceptanceTests: XCTestCase {
    func testExplorationKeepsGeometryWhenChangingTitle() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-fixtures", "--ui-long-titles", "-ApplePersistenceIgnoreState", "YES",
        ]
        continueAfterFailure = false
        app.launch()
        #if os(macOS)
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                app.typeKey("n", modifierFlags: .command)
            }
        #endif
        let title = app.staticTexts["exploration-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let card = app.descendants(matching: .any)["catalogue-exploration"].firstMatch
        let initial = card.frame
        let initialShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        initialShot.name = "editorial-short-title"
        initialShot.lifetime = .keepAlways
        add(initialShot)
        XCTAssertTrue(title.isHittable)
        #if os(iOS)
            if app.windows.firstMatch.frame.width < 500 {
                XCTAssertLessThanOrEqual(
                    app.buttons["四川新闻"].frame.maxY,
                    app.buttons["下载"].firstMatch.frame.minY)
            }
        #endif
        if initial.width >= 580 {
            XCTAssertLessThan(initial.height, initial.width * 0.7)
        }
        activate(app.buttons["换一个"])
        #if os(macOS)
            XCTAssertEqual(title.value as? String, "防癌大讲堂")
        #else
            XCTAssertEqual(title.label, "防癌大讲堂")
        #endif
        XCTAssertEqual(card.frame.height, initial.height, accuracy: 1)
        XCTAssertEqual(card.frame.width, initial.width, accuracy: 1)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "polished-long-title"
        shot.lifetime = .keepAlways
        add(shot)
        activate(app.buttons["换一个"])
        #if os(macOS)
            XCTAssertEqual(title.value as? String, "四川新闻")
        #else
            XCTAssertEqual(title.label, "四川新闻")
        #endif
        XCTAssertEqual(card.frame.height, initial.height, accuracy: 1)
        activate(app.buttons["查看节目"])
        XCTAssertTrue(
            app.descendants(matching: .any)["完整节目"].firstMatch.waitForExistence(timeout: 10))
    }

    func testLongArchiveTitlesKeepCompactCardHeight() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-fixtures", "--ui-long-content-titles", "-ApplePersistenceIgnoreState", "YES",
        ]
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
        let long = app.buttons["archive-play-31"]
        let short = app.buttons["archive-play-32"]
        reveal(short, in: app)
        XCTAssertTrue(long.waitForExistence(timeout: 10))
        XCTAssertTrue(short.exists)
        XCTAssertGreaterThan(long.label.count, 200)
        XCTAssertLessThan(long.frame.height, 120)
        XCTAssertEqual(long.frame.height, short.frame.height, accuracy: 2)
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "compact-long-archive-title"
        shot.lifetime = .keepAlways
        add(shot)

        let menu = app.descendants(matching: .any)["content-actions-32"].firstMatch
        XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        let edge = menu.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        #if os(macOS)
            edge.click()
        #else
            edge.tap()
        #endif
        XCTAssertTrue(
            app.descendants(matching: .any)["download-content-32"].firstMatch.waitForExistence(
                timeout: 5))
    }

    func testLongDateHistoryOpensOnDemandAndSelectsOlderBroadcast() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-fixtures", "--ui-many-dates", "-ApplePersistenceIgnoreState", "YES",
        ]
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
        let dates = app.buttons["archive-all-dates"]
        XCTAssertTrue(dates.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["archive-date-3421"].exists)
        activate(dates)
        XCTAssertTrue(app.staticTexts["2026年10月"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["当前选择"].exists)
        let browser = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        browser.name = "archive-monthly-date-browser"
        browser.lifetime = .keepAlways
        add(browser)
        let search = activateSearch(in: app)
        search.typeText("20170630")
        let oldest = app.buttons["archive-date-3421"]
        XCTAssertTrue(oldest.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "archive-date-search"
        shot.lifetime = .keepAlways
        add(shot)
        activate(oldest)
        XCTAssertTrue(app.buttons["四川新闻（2017.06.30）"].waitForExistence(timeout: 10))
        XCTAssertFalse(search.exists)
        activate(dates)
        XCTAssertTrue(oldest.waitForExistence(timeout: 5))
        XCTAssertTrue(oldest.isHittable)
        let reopened = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        reopened.name = "archive-date-reopened-at-selection"
        reopened.lifetime = .keepAlways
        add(reopened)
        activate(app.buttons["关闭"])
        XCTAssertFalse(oldest.exists)
    }

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
        #if os(iOS)
            let settingsButton = app.buttons["设置"]
            XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
            activate(settingsButton)
            XCTAssertTrue(
                app.descendants(matching: .any)["首选画质"].firstMatch.waitForExistence(timeout: 5))
            activate(app.buttons["完成"])
            XCTAssertTrue(programme.waitForExistence(timeout: 5))
        #endif
        let catalogueShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        catalogueShot.name = "redesign-catalogue"
        catalogueShot.lifetime = .keepAlways
        add(catalogueShot)
        activate(programme)
        XCTAssertTrue(
            app.descendants(matching: .any)["完整节目"].firstMatch.waitForExistence(timeout: 10))
        let clip = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "秋日里的城市故事")
        ).firstMatch
        reveal(clip, in: app)
        XCTAssertTrue(clip.exists)
        let archive = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        archive.name = "native-archive"
        archive.lifetime = .keepAlways
        add(archive)

        #if os(macOS)
            activate(app.descendants(matching: .any)["资料库"].firstMatch)
        #else
            let library = app.buttons["资料库"].firstMatch
            activate(library)
        #endif
        XCTAssertTrue(app.buttons["设置"].firstMatch.waitForExistence(timeout: 10))
        let libraryShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        libraryShot.name = "redesign-library"
        libraryShot.lifetime = .keepAlways
        add(libraryShot)
        activate(app.buttons["下载"].firstMatch)
        XCTAssertTrue(app.staticTexts["暂无下载"].waitForExistence(timeout: 10))
        let downloadsShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        downloadsShot.name = "polished-empty-downloads"
        downloadsShot.lifetime = .keepAlways
        add(downloadsShot)
        activate(app.buttons["资料库"].firstMatch)
        activate(app.buttons["设置"].firstMatch)
        XCTAssertTrue(
            app.descendants(matching: .any)["首选画质"].firstMatch.waitForExistence(timeout: 10))
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "native-settings"
        settings.lifetime = .keepAlways
        add(settings)
    }

    func testFavouriteActionFiltersCatalogueWithoutOpeningProgramme() {
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
        let favourite = app.buttons["收藏 四川新闻"]
        XCTAssertTrue(favourite.waitForExistence(timeout: 15))
        reveal(favourite, in: app)
        activate(favourite)
        let saved = app.buttons["取消收藏 四川新闻"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        activate(app.buttons["只看收藏"])
        XCTAssertTrue(app.buttons["四川新闻"].exists)
        XCTAssertFalse(app.buttons["今日视点"].exists)
        activate(saved)
        XCTAssertTrue(app.staticTexts["还没有收藏栏目"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["查看节目"].exists)
        activate(app.buttons["显示全部栏目"])
        XCTAssertTrue(app.buttons["今日视点"].waitForExistence(timeout: 5))
        #if os(macOS)
            let search = app.searchFields.firstMatch
            search.click()
            search.typeText("sctv-no-results")
            XCTAssertTrue(app.staticTexts["没有找到栏目"].waitForExistence(timeout: 5))
            search.typeKey("a", modifierFlags: .command)
            search.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            XCTAssertTrue(app.buttons["今日视点"].waitForExistence(timeout: 5))
        #endif
    }

    #if os(iOS)
        func testCataloguePullToRefreshLoadsUpdates() {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "--ui-slow-catalogue", "-ApplePersistenceIgnoreState", "YES",
            ]
            app.launch()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 20))
            let scroll = app.scrollViews["catalogue-scroll"]
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.1, thenDragTo: end)
            let update = app.buttons["发现新内容 · 点此更新"]
            XCTAssertTrue(update.waitForExistence(timeout: 10))
            update.tap()
            XCTAssertTrue(app.buttons["刷新后的栏目"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["栏目"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "catalogue-after-pull-to-refresh"
            shot.lifetime = .keepAlways
            add(shot)
        }

        func testCustomPlayerControlsAndTitleDisclosure() {
            XCUIDevice.shared.orientation = .portrait
            defer { XCUIDevice.shared.orientation = .portrait }
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "--ui-long-content-titles", "-ApplePersistenceIgnoreState", "YES",
            ]
            continueAfterFailure = false
            app.launch()
            let programme = app.buttons["四川新闻"]
            XCTAssertTrue(programme.waitForExistence(timeout: 15))
            programme.tap()
            let clip = app.buttons["archive-play-31"]
            reveal(clip, in: app)
            clip.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["native-player-ready"].firstMatch.waitForExistence(
                    timeout: 20))
            XCTAssertFalse(app.navigationBars["播放"].exists)
            let title = app.buttons["player-title-disclosure"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let collapsedHeight = title.frame.height
            title.tap()
            XCTAssertTrue(app.staticTexts["player-full-title"].waitForExistence(timeout: 5))
            app.buttons["完成"].tap()
            XCTAssertEqual(title.frame.height, collapsedHeight, accuracy: 2)
            let inline = XCTAttachment(screenshot: app.screenshot())
            inline.name = "custom-player-inline"
            inline.lifetime = .keepAlways
            add(inline)
            app.buttons["player-quality"].tap()
            XCTAssertTrue(app.buttons["标准"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 0.5)
            let qualityMenu = XCTAttachment(screenshot: app.screenshot())
            qualityMenu.name = "custom-player-quality-options"
            qualityMenu.lifetime = .keepAlways
            add(qualityMenu)
            app.buttons["标准"].tap()
            let progress = app.sliders["player-progress"]
            XCTAssertTrue(progress.exists)
            progress.adjust(toNormalizedSliderPosition: 0.5)
            app.buttons["player-fullscreen"].tap()
            let speed = app.buttons["player-speed"]
            XCTAssertTrue(speed.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(speed.frame.minX, progress.frame.maxX)
            XCTAssertTrue(
                app.windows.allElementsBoundByIndex.contains {
                    $0.frame.width > 0 && $0.frame.contains(app.buttons["player-fullscreen"].frame)
                })
            let fullscreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            fullscreen.name = "custom-player-fullscreen"
            fullscreen.lifetime = .keepAlways
            add(fullscreen)
            progress.adjust(toNormalizedSliderPosition: 0)
            app.buttons["player-toggle-play"].tap()
            speed.tap()
            Thread.sleep(forTimeInterval: 5)
            XCTAssertTrue(app.buttons["1.5 倍速"].exists)
            app.buttons["1.5 倍速"].tap()
            XCTAssertEqual(speed.value as? String, "1.5 倍")
            let surface = app.descendants(matching: .any)["player-gesture-surface"].firstMatch
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)).press(
                forDuration: 0.6)
            XCTAssertEqual(speed.value as? String, "1.5 倍")
            // A short horizontal gesture commits one seek and keeps the video usable.
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)).press(
                forDuration: 0.05,
                thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)))
            XCTAssertTrue(app.buttons["player-toggle-play"].exists)
            app.buttons["player-fullscreen"].tap()
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            app.buttons["player-back"].tap()
            XCTAssertTrue(clip.waitForExistence(timeout: 5))
        }

        func testCatalogueNativeHeadingAndSearch() {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "--ui-many-programmes", "-ApplePersistenceIgnoreState", "YES",
            ]
            continueAfterFailure = false
            app.launch()
            let heading = app.navigationBars["栏目"]
            XCTAssertTrue(heading.waitForExistence(timeout: 15))
            let search = app.searchFields.firstMatch
            let scroll = app.scrollViews["catalogue-scroll"]
            if !search.isHittable { scroll.swipeDown() }
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            let initialShot = XCTAttachment(screenshot: app.screenshot())
            initialShot.name = "catalogue-native-heading-and-search"
            initialShot.lifetime = .keepAlways
            add(initialShot)
            let initialSpotlightY = app.buttons["查看节目"].frame.minY
            scroll.swipeUp()
            scroll.swipeUp()
            // Native navigation can move its title and controls into a side rail,
            // even on a narrow iPhone window. Assert the route, not that hierarchy.
            XCTAssertTrue(heading.exists)
            XCTAssertTrue(app.buttons["栏目"].firstMatch.isSelected)
            XCTAssertLessThan(app.buttons["查看节目"].frame.minY, initialSpotlightY)
            scroll.swipeDown()
            scroll.swipeDown()
            if !search.isHittable { scroll.swipeDown() }
            activateSearch(in: app).typeText("今日")
            XCTAssertTrue(app.buttons["今日视点"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["四川新闻"].exists)
            let focusedShot = XCTAttachment(screenshot: app.screenshot())
            focusedShot.name = "catalogue-native-search-focused"
            focusedShot.lifetime = .keepAlways
            add(focusedShot)
            let clear = search.buttons.firstMatch
            XCTAssertTrue(clear.exists)
            clear.tap()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 5))
        }

        func testPlayerEdgeSwipeReturnsToArchive() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            app.buttons["四川新闻"].tap()
            let clip = app.buttons["archive-play-31"]
            reveal(clip, in: app)
            clip.tap()
            XCTAssertTrue(app.buttons["player-back"].waitForExistence(timeout: 15))
            guard
                let window = app.windows.allElementsBoundByIndex.first(where: {
                    $0.frame.width > 100
                })
            else {
                XCTFail("Expected a visible application window")
                return
            }
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.2)).press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)))
            XCTAssertTrue(clip.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["player-back"].exists)
            app.buttons["资料库"].firstMatch.tap()
            XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 5))
        }

        func testDownloadSelectionSurvivesRapidTaps() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            app.buttons["四川新闻"].tap()
            for id in ["30", "31"] {
                let content = app.buttons["content-actions-\(id)"]
                reveal(content, in: app)
                content.tap()
                app.buttons["download-content-\(id)"].tap()
                XCTAssertTrue(app.alerts["提示"].waitForExistence(timeout: 5))
                app.alerts["提示"].buttons["好"].tap()
            }
            app.buttons["下载"].firstMatch.tap()
            let title = app.staticTexts["秋日里的城市故事"]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            let secondTitle = app.staticTexts["四川新闻（2026.10.22）"]
            XCTAssertTrue(secondTitle.exists)
            let filters = app.buttons["全部"]
            let originalTitleInset = title.frame.minX - filters.frame.minX
            let originalSecondInset = secondTitle.frame.minX - filters.frame.minX
            let usesBottomTabs = app.buttons["栏目"].firstMatch.frame.midY > app.frame.midY
            assertRapidSelectionTaps(
                app, identifier: "downloads-select", activeLabel: "完成", expectsEveryTap: true
            ) {
                let selecting = app.buttons["downloads-select"].label == "完成"
                let catalogue = app.buttons["栏目"].firstMatch
                XCTAssertEqual(
                    catalogue.exists && catalogue.isHittable, !usesBottomTabs || !selecting)
                XCTAssertEqual(app.buttons["下载操作"].firstMatch.exists, !selecting)
                XCTAssertEqual(
                    title.frame.minX - filters.frame.minX - originalTitleInset,
                    secondTitle.frame.minX - filters.frame.minX - originalSecondInset, accuracy: 2)
                if selecting {
                    XCTAssertGreaterThan(
                        title.frame.minX - filters.frame.minX, originalTitleInset + 20)
                    XCTAssertTrue(app.staticTexts["请选择要操作的下载任务"].isHittable)
                    let firstSelection = app.buttons["select-download-30"]
                    let secondSelection = app.buttons["select-download-31"]
                    firstSelection.tap()
                    XCTAssertTrue(app.staticTexts["已选 1 项"].exists)
                    XCTAssertTrue(firstSelection.isSelected)
                    XCTAssertFalse(secondSelection.isSelected)
                    firstSelection.tap()
                    app.buttons["全选"].tap()
                    XCTAssertTrue(app.staticTexts["已选 2 项"].waitForExistence(timeout: 5))
                    app.buttons["取消全选"].tap()
                    XCTAssertTrue(app.staticTexts["已选 0 项"].exists)
                } else {
                    XCTAssertEqual(
                        title.frame.minX - filters.frame.minX, originalTitleInset, accuracy: 2)
                }
            }
            app.buttons["play-download-30"].tap()
            XCTAssertTrue(app.buttons["player-back"].waitForExistence(timeout: 10))
            app.buttons["player-back"].tap()
            XCTAssertTrue(app.buttons["downloads-select"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["栏目"].firstMatch.isHittable)
        }

        func testArchiveSelectionSurvivesRapidTaps() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            app.buttons["四川新闻"].tap()
            assertRapidSelectionTaps(app, identifier: "archive-select", activeLabel: "取消选择")
        }

        private func assertRapidSelectionTaps(
            _ app: XCUIApplication, identifier: String, activeLabel: String,
            expectsEveryTap: Bool = false,
            verify: () -> Void = {}
        ) {
            let toggle = app.buttons[identifier]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            for _ in 0..<4 {
                let initialLabel = toggle.label
                toggle.tap(withNumberOfTaps: 6, numberOfTouches: 1)
                XCTAssertTrue(toggle.exists)
                XCTAssertTrue(toggle.isHittable)
                XCTAssertTrue(toggle.isEnabled)
                XCTAssertTrue(["选择", activeLabel].contains(toggle.label))
                if expectsEveryTap { XCTAssertEqual(toggle.label, initialLabel) }
                verify()
                let expectedLabel = toggle.label == "选择" ? activeLabel : "选择"
                toggle.tap()
                let changed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@", expectedLabel), object: toggle)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
                verify()
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(identifier)-after-rapid-taps"
            shot.lifetime = .keepAlways
            add(shot)
        }

        func testDownloadsUseExplicitSelectionAndCompactTitles() {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "--ui-long-content-titles", "-ApplePersistenceIgnoreState", "YES",
            ]
            continueAfterFailure = false
            app.launch()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            app.buttons["四川新闻"].tap()
            for id in ["31", "32"] {
                let menu = app.buttons["content-actions-\(id)"]
                reveal(menu, in: app)
                menu.tap()
                app.buttons["download-content-\(id)"].tap()
                XCTAssertTrue(app.alerts["提示"].waitForExistence(timeout: 5))
                app.alerts["提示"].buttons["好"].tap()
            }
            app.buttons["下载"].firstMatch.tap()
            let longTitle = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "秋日里的城市故事")
            ).firstMatch
            XCTAssertTrue(longTitle.waitForExistence(timeout: 15))
            XCTAssertLessThan(longTitle.frame.height, 55)
            let cards = XCTAttachment(screenshot: app.screenshot())
            cards.name = "download-compact-cards"
            cards.lifetime = .keepAlways
            add(cards)
            XCTAssertFalse(app.buttons["批量操作"].exists)
            longTitle.tap()
            XCTAssertFalse(app.buttons["批量操作"].exists)
            XCTAssertFalse(app.staticTexts["已选 1 项"].exists)
            let menu = app.buttons["download-31-completed"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            XCTAssertTrue(app.buttons["导出副本"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["批量操作"].exists)
            let menuShot = XCTAttachment(screenshot: app.screenshot())
            menuShot.name = "download-secondary-actions"
            menuShot.lifetime = .keepAlways
            add(menuShot)
            app.navigationBars["下载"].tap()
            let filtersTop = app.buttons["全部"].frame.minY
            let usesBottomTabs = app.buttons["栏目"].firstMatch.frame.midY > app.frame.midY
            app.buttons["选择"].tap()
            XCTAssertEqual(app.buttons["全部"].frame.minY, filtersTop, accuracy: 2)
            longTitle.tap()
            XCTAssertTrue(app.staticTexts["已选 1 项"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["栏目"].firstMatch.isHittable, !usesBottomTabs)
            XCTAssertFalse(menu.exists)
            XCTAssertTrue(app.buttons["删除文件"].isHittable)
            XCTAssertTrue(app.buttons["移除记录"].isHittable)
            app.buttons["全选"].tap()
            XCTAssertTrue(app.staticTexts["已选 2 项"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "download-selection-actions"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["完成"].tap()
            XCTAssertFalse(app.staticTexts["已选 2 项"].exists)
            XCTAssertTrue(menu.exists)
            XCTAssertEqual(app.buttons["全部"].frame.minY, filtersTop, accuracy: 2)
            XCTAssertTrue(app.buttons["栏目"].firstMatch.isHittable)
            app.buttons["选择"].tap()
            app.buttons["全选"].tap()
            app.buttons["移除记录"].tap()
            XCTAssertTrue(app.buttons["确认"].waitForExistence(timeout: 5))
            app.buttons["确认"].tap()
            XCTAssertTrue(app.staticTexts["暂无下载"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["完成"].exists)
        }

        func testContinuingDeletionKeepsLibraryPosition() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            app.buttons["四川新闻"].tap()
            for id in ["30", "31"] {
                let content = app.buttons["archive-play-\(id)"]
                reveal(content, in: app)
                content.tap()
                XCTAssertTrue(
                    app.descendants(matching: .any)["native-player-ready"].firstMatch
                        .waitForExistence(
                            timeout: 20))
                app.sliders["player-progress"].adjust(toNormalizedSliderPosition: 0.25)
                app.buttons["player-back"].tap()
            }
            app.buttons["资料库"].firstMatch.tap()
            let row = app.buttons["秋日里的城市故事"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let heading = app.staticTexts["继续观看"]
            let headingY = heading.frame.minY
            row.swipeLeft()
            app.buttons["删除记录"].tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 5))
            let remaining = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "四川新闻（")
            ).firstMatch
            XCTAssertTrue(remaining.exists)
            XCTAssertEqual(heading.frame.minY, headingY, accuracy: 2)
            remaining.swipeLeft()
            app.buttons["删除记录"].tap()
            XCTAssertTrue(remaining.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["故事，留待下次继续"].exists)
            XCTAssertEqual(heading.frame.minY, headingY, accuracy: 2)
            XCTAssertTrue(app.buttons["观看历史"].isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "library-after-continuing-deletion"
            shot.lifetime = .keepAlways
            add(shot)
        }

        func testLongHistoryTitlesKeepCardsCompact() {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "--ui-long-content-titles", "-ApplePersistenceIgnoreState", "YES",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            ]
            continueAfterFailure = false
            app.launch()
            let programme = app.buttons["四川新闻"]
            XCTAssertTrue(programme.waitForExistence(timeout: 15))
            programme.tap()
            for id in ["31", "32"] {
                let clip = app.buttons["archive-play-\(id)"]
                reveal(clip, in: app)
                clip.tap()
                let player = app.descendants(matching: .any)["native-player-ready"].firstMatch
                XCTAssertTrue(player.waitForExistence(timeout: 20))
                app.sliders["player-progress"].adjust(toNormalizedSliderPosition: 0.25)
                app.buttons["player-back"].firstMatch.tap()
            }
            app.buttons["资料库"].firstMatch.tap()
            let libraryShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            libraryShot.name = "compact-continuing-cards"
            libraryShot.lifetime = .keepAlways
            add(libraryShot)
            reveal(app.buttons["观看历史"], in: app)
            app.buttons["观看历史"].tap()
            let long = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "秋日里的城市故事"))
                .firstMatch
            let short = app.buttons["城市一刻"]
            XCTAssertTrue(long.waitForExistence(timeout: 10))
            XCTAssertTrue(short.exists)
            XCTAssertLessThan(long.frame.height, 120)
            XCTAssertEqual(long.frame.height, short.frame.height, accuracy: 2)
            let chineseDate = app.staticTexts.matching(
                NSPredicate(format: "label MATCHES %@", "[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日")
            ).firstMatch
            XCTAssertTrue(chineseDate.exists)
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "compact-history-titles"
            shot.lifetime = .keepAlways
            add(shot)
            long.swipeLeft()
            let delete = app.buttons["删除记录"]
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            delete.tap()
            XCTAssertTrue(long.waitForNonExistence(timeout: 5))
            XCTAssertTrue(short.exists)
            let clear = app.buttons["history-clear"]
            clear.tap()
            XCTAssertTrue(
                app.buttons["history-confirm-clear"].firstMatch.waitForExistence(timeout: 5))
            let confirmation = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            confirmation.name = "history-clear-confirmation-anchor"
            confirmation.lifetime = .keepAlways
            add(confirmation)
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7))
                .tap()
            XCTAssertTrue(short.exists)
            clear.tap()
            app.buttons["history-confirm-clear"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["暂无观看记录"].waitForExistence(timeout: 5))

        }

        func testPlaybackPreservesArchiveScrollOffset() {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-fixtures", "--ui-many-contents", "-ApplePersistenceIgnoreState", "YES",
            ]
            continueAfterFailure = false
            app.launch()
            let programme = app.buttons["四川新闻"]
            XCTAssertTrue(programme.waitForExistence(timeout: 15))
            programme.tap()
            let clip = app.buttons["archive-play-40"]
            reveal(clip, in: app)
            XCTAssertTrue(clip.isHittable)
            let before = clip.frame
            clip.tap()
            let player = app.descendants(matching: .any)["native-player-ready"].firstMatch
            XCTAssertTrue(player.waitForExistence(timeout: 20))
            app.buttons["player-back"].firstMatch.tap()
            XCTAssertTrue(clip.waitForExistence(timeout: 10))
            XCTAssertTrue(clip.isHittable)
            XCTAssertEqual(clip.frame.minY, before.minY, accuracy: 2)
            XCTAssertEqual(clip.frame.height, before.height, accuracy: 2)
        }

        func testPlaybackReturnsToArchiveThroughNavigation() {
            XCUIDevice.shared.orientation = .portrait
            defer { XCUIDevice.shared.orientation = .portrait }
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            let programme = app.buttons["四川新闻"]
            XCTAssertTrue(programme.waitForExistence(timeout: 15))
            programme.tap()
            let menu = app.descendants(matching: .any)["content-actions-30"].firstMatch
            reveal(menu, in: app)
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            app.buttons["播放"].firstMatch.tap()
            let player = app.descendants(matching: .any)["native-player-ready"].firstMatch
            XCTAssertTrue(player.waitForExistence(timeout: 20))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "redesign-player"
            shot.lifetime = .keepAlways
            add(shot)
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(player.waitForExistence(timeout: 5))
            let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            landscape.name = "redesign-player-landscape"
            landscape.lifetime = .keepAlways
            add(landscape)
            XCUIDevice.shared.orientation = .portrait
            let back = app.buttons["player-back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            XCTAssertFalse(player.exists)
            app.buttons["资料库"].firstMatch.tap()
            let history = app.buttons["观看历史"]
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            history.tap()
            let entry = app.buttons["四川新闻（2026.10.22）"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(player.waitForExistence(timeout: 20))
            app.buttons["player-back"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["观看历史"].waitForExistence(timeout: 5))
            XCTAssertTrue(entry.exists)
        }

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
            let entry = app.buttons["查看节目"]
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            reveal(entry, in: app)
            let catalogue = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            catalogue.name = "editorial-large-text-dark"
            catalogue.lifetime = .keepAlways
            add(catalogue)
            entry.tap()
            let content = app.descendants(matching: .any)["content-actions-30"].firstMatch
            reveal(content, in: app)
            XCTAssertTrue(content.waitForExistence(timeout: 10))
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(content, in: app)
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

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            #if os(macOS)
                let archive = app.scrollViews["archive-scroll"]
                let scroll = archive.exists ? archive : app.scrollViews["catalogue-scroll"]
                scroll.scroll(byDeltaX: 0, deltaY: -300)
            #else
                app.swipeUp()
            #endif
        }
    }

    private func activateSearch(in app: XCUIApplication) -> XCUIElement {
        let search = app.searchFields.firstMatch
        if !search.exists {
            // Adaptive navigation may expose a search button before its text field.
            let searchButton = app.buttons.matching(
                NSPredicate(format: "label IN %@", ["Search", "搜索"])
            ).firstMatch
            XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
            activate(searchButton)
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        activate(search)
        return search
    }

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
            element.click()
        #else
            element.tap()
        #endif
    }
}
