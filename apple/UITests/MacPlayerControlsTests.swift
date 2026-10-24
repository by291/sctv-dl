#if os(macOS)
    import XCTest

    @MainActor
    final class MacPlayerControlsTests: XCTestCase {
        func testControlsAndVideoDoubleClickFullscreen() {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "-ApplePersistenceIgnoreState", "YES"]
            continueAfterFailure = false
            app.launch()
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                app.typeKey("n", modifierFlags: .command)
            }
            XCTAssertTrue(app.buttons["四川新闻"].waitForExistence(timeout: 15))
            app.buttons["四川新闻"].click()
            let clip = app.buttons["archive-play-31"]
            for _ in 0..<8 {
                if clip.exists && clip.isHittable { break }
                app.scrollViews["archive-scroll"].scroll(byDeltaX: 0, deltaY: -250)
            }
            XCTAssertTrue(clip.waitForExistence(timeout: 10))
            clip.click()
            XCTAssertTrue(
                app.descendants(matching: .any)["native-player-ready"].firstMatch
                    .waitForExistence(timeout: 20))
            let play = app.buttons["player-toggle-play"]
            XCTAssertTrue(play.waitForExistence(timeout: 5))
            if play.label == "暂停" { play.click() }
            let progress = app.sliders["player-progress"]
            progress.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                .click(
                    forDuration: 0.1,
                    thenDragTo: progress.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            // Native thumb geometry and frame quantization may land just below six seconds.
            let middle = NSPredicate(
                format: "value BEGINSWITH %@ OR value BEGINSWITH %@", "00:05", "00:06")
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [expectation(for: middle, evaluatedWith: progress)],
                    timeout: 5), .completed)
            XCTAssertEqual(play.label, "播放")
            app.buttons["player-skip-backward"].click()
            let beginning = NSPredicate(format: "value BEGINSWITH %@", "00:00")
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [expectation(for: beginning, evaluatedWith: progress)],
                    timeout: 5), .completed)
            // Keyboard transport must keep using the live intent and position after layout updates.
            app.typeKey(.space, modifierFlags: [])
            expectLabel("暂停", on: play)
            Thread.sleep(forTimeInterval: 1)
            app.typeKey(.space, modifierFlags: [])
            expectLabel("播放", on: play)
            let pausedAt = positionSeconds(progress)
            app.typeKey(.rightArrow, modifierFlags: [])
            expectPosition(min(12, pausedAt + 10), on: progress)
            app.typeKey(.leftArrow, modifierFlags: [])
            expectPosition(max(0, min(12, pausedAt + 10) - 10), on: progress)
            let feedback = app.descendants(matching: .any)["player-action-feedback"].firstMatch
            XCTAssertTrue(feedback.label.contains("快退 10 秒"))
            let volume = app.sliders["player-volume"]
            XCTAssertTrue(volume.exists)
            let initialVolume = (volume.value as? NSNumber)?.doubleValue
            XCTAssertNotNil(initialVolume)
            app.typeKey(.downArrow, modifierFlags: [])
            XCTAssertEqual(feedback.label, "音量 95%")
            XCTAssertNotEqual((volume.value as? NSNumber)?.doubleValue, initialVolume)
            app.typeKey(.upArrow, modifierFlags: [])
            XCTAssertEqual(feedback.label, "音量 100%")
            XCTAssertEqual(
                (volume.value as? NSNumber)?.doubleValue ?? -1, initialVolume ?? -2,
                accuracy: 0.0001)
            app.typeKey(.space, modifierFlags: [])
            XCTAssertEqual(feedback.label, "播放")
            expectLabel("暂停", on: play)
            app.typeKey(.space, modifierFlags: [])
            XCTAssertEqual(feedback.label, "暂停")
            let feedbackScreenshot = XCTAttachment(screenshot: app.windows["player"].screenshot())
            feedbackScreenshot.name = "mac-player-keyboard-feedback"
            feedbackScreenshot.lifetime = .keepAlways
            add(feedbackScreenshot)
            expectLabel("播放", on: play)
            XCTAssertTrue(app.buttons["player-pip"].exists)
            let speed = app.buttons["player-speed"]
            speed.click()
            XCTAssertTrue(app.buttons["1.5 倍速"].waitForExistence(timeout: 5))
            app.buttons["1.5 倍速"].click()
            XCTAssertEqual(speed.value as? String, "1.5 倍")
            XCTAssertFalse(app.buttons["player-details-toggle"].exists)
            XCTAssertTrue(app.buttons["player-title-disclosure"].exists)
            let screenshot = XCTAttachment(screenshot: app.windows["player"].screenshot())
            screenshot.name = "mac-floating-player-controls"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            let surface = app.descendants(matching: .any)["mac-video-surface"].firstMatch
            XCTAssertTrue(surface.waitForExistence(timeout: 5))
            let fullscreen = app.buttons["player-fullscreen"]
            fullscreen.click()
            expectLabel("退出全屏", on: fullscreen)
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertEqual(app.windows["player"].toolbars.count, 0)
            let fullscreenScreenshot = XCTAttachment(screenshot: app.windows["player"].screenshot())
            fullscreenScreenshot.name = "mac-player-fullscreen-no-toolbar"
            fullscreenScreenshot.lifetime = .keepAlways
            add(fullscreenScreenshot)
            fullscreen.click()
            expectLabel("全屏", on: fullscreen)
            Thread.sleep(forTimeInterval: 1.5)
            app.buttons["player-mute"].doubleClick()
            XCTAssertEqual(fullscreen.label, "全屏")
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).doubleClick()
            expectLabel("退出全屏", on: fullscreen)
            XCTAssertFalse(app.buttons["player-title-disclosure"].exists)
            // Wait for AppKit's Space transition before sending a second double-click.
            Thread.sleep(forTimeInterval: 1.5)
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).doubleClick()
            expectLabel("全屏", on: fullscreen)
            XCTAssertTrue(app.buttons["player-title-disclosure"].waitForExistence(timeout: 5))
            app.terminate()
        }

        private func positionSeconds(_ progress: XCUIElement) -> Int {
            let value = progress.value as? String ?? ""
            let fields = value.prefix(5).split(separator: ":").compactMap { Int($0) }
            return fields.count == 2 ? fields[0] * 60 + fields[1] : -1
        }

        private func expectPosition(_ target: Int, on progress: XCUIElement) {
            let reached = NSPredicate { _, _ in
                MainActor.assumeIsolated { abs(self.positionSeconds(progress) - target) <= 1 }
            }
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [expectation(for: reached, evaluatedWith: progress)], timeout: 5),
                .completed)
        }

        private func expectLabel(_ label: String, on element: XCUIElement) {
            let predicate = NSPredicate(format: "label == %@", label)
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [expectation(for: predicate, evaluatedWith: element)],
                    timeout: 8), .completed)
        }
    }
#endif
