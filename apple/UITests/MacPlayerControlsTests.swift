#if os(macOS)
    import AppKit
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
            requireState("Play control is ready", of: play) { $0.isHittable }
            if play.label == "暂停" {
                play.click()
            }
            expectLabel("播放", on: play)
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
            requireState("Playback advances after the space key", of: progress) {
                self.playbackSeconds($0) > 0
            }
            app.typeKey(.space, modifierFlags: [])
            expectLabel("播放", on: play)
            let pausedAt = playbackSeconds(progress)
            app.typeKey(.rightArrow, modifierFlags: [])
            expectPosition(min(12, pausedAt + 10), on: progress)
            app.typeKey(.leftArrow, modifierFlags: [])
            expectPosition(max(0, min(12, pausedAt + 10) - 10), on: progress)
            let feedback = app.descendants(matching: .any)["player-action-feedback"].firstMatch
            requireState("Keyboard skip shows feedback", of: feedback) {
                $0.label.contains("快退 10 秒")
            }
            let volume = app.sliders["player-volume"]
            XCTAssertTrue(volume.exists)
            let initialVolume = (volume.value as? NSNumber)?.doubleValue
            XCTAssertNotNil(initialVolume)
            app.typeKey(.downArrow, modifierFlags: [])
            expectLabel("音量 95%", on: feedback)
            XCTAssertNotEqual((volume.value as? NSNumber)?.doubleValue, initialVolume)
            app.typeKey(.upArrow, modifierFlags: [])
            expectLabel("音量 100%", on: feedback)
            XCTAssertEqual(
                (volume.value as? NSNumber)?.doubleValue ?? -1, initialVolume ?? -2,
                accuracy: 0.0001)
            app.typeKey(.space, modifierFlags: [])
            expectLabel("播放", on: feedback)
            expectLabel("暂停", on: play)
            app.typeKey(.space, modifierFlags: [])
            expectLabel("暂停", on: feedback)
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

            verifyFullscreen(in: app)
        }

        private func verifyFullscreen(in app: XCUIApplication) {
            let window = app.windows["player"]
            let windowedSize = window.frame.size
            let fullscreen = app.buttons["player-fullscreen"]
            let title = app.buttons["player-title-disclosure"]
            let surface = app.descendants(matching: .any)["mac-video-surface"].firstMatch
            requireState("Video surface is ready", of: surface) { $0.isHittable }

            fullscreen.click()
            expectFullscreenWindow(window)
            expectLabel("退出全屏", on: fullscreen)
            XCTAssertEqual(window.toolbars.count, 0)
            let fullscreenScreenshot = XCTAttachment(screenshot: window.screenshot())
            fullscreenScreenshot.name = "mac-player-fullscreen-no-toolbar"
            fullscreenScreenshot.lifetime = .keepAlways
            add(fullscreenScreenshot)
            fullscreen.click()
            expectWindowedPlayer(window, size: windowedSize)
            expectLabel("全屏", on: fullscreen)
            XCTAssertTrue(title.waitForExistence(timeout: 5))

            app.buttons["player-mute"].doubleClick()
            expectLabel("全屏", on: fullscreen)
            let video = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            video.doubleClick()
            expectFullscreenWindow(window)
            expectLabel("退出全屏", on: fullscreen)
            XCTAssertTrue(title.waitForNonExistence(timeout: 5))
            video.doubleClick()
            expectWindowedPlayer(window, size: windowedSize)
            expectLabel("全屏", on: fullscreen)
            XCTAssertTrue(title.waitForExistence(timeout: 5))
        }

        private func expectFullscreenWindow(_ window: XCUIElement) {
            let screenSizes = NSScreen.screens.map { $0.frame.size }
            requireState("AppKit window fills a screen before the next gesture", of: window) {
                let size = $0.frame.size
                return screenSizes.contains { self.matchesWindowSize(size, $0) }
                    && !$0.buttons["_XCUI:CloseWindow"].isHittable
            }
        }

        private func expectWindowedPlayer(_ window: XCUIElement, size: CGSize) {
            requireState("AppKit restores the window and its controls", of: window) {
                self.matchesWindowSize($0.frame.size, size)
                    && $0.buttons["_XCUI:CloseWindow"].isHittable
            }
        }

        private func matchesWindowSize(_ actual: CGSize, _ expected: CGSize) -> Bool {
            let tolerance: CGFloat = 4
            return abs(actual.width - expected.width) <= tolerance
                && abs(actual.height - expected.height) <= tolerance
        }

        private func expectPosition(_ target: Int, on progress: XCUIElement) {
            requireState("Player reaches position \(target)", of: progress) {
                abs(self.playbackSeconds($0) - target) <= 1
            }
        }

        private func expectLabel(_ label: String, on element: XCUIElement) {
            requireState("Control shows \(label)", of: element) { $0.label == label }
        }
    }
#endif
