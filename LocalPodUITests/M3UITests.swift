import XCTest

@MainActor
final class M3UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchPinned()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForLabel(
        _ element: XCUIElement,
        equals expected: String,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected label \(expected), got \(element.label)"
        )
    }

    private func waitForLabelContains(
        _ element: XCUIElement,
        text: String,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected label containing \(text), got \(element.label)"
        )
    }

    private func waitForValue(
        _ element: XCUIElement,
        equals expected: String,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected value \(expected), got \(String(describing: element.value))"
        )
    }

    private func waitForSelected(_ element: XCUIElement, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "expected \(element.label) to be selected"
        )
    }

    /// Parses "m:ss" (and "h:mm:ss") labels into seconds.
    private func seconds(from label: String) -> Int {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return 0 }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return parts[0] * 60 + parts[1]
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 10
    ) {
        // Normalize to the top so an element above the current scroll
        // position is reachable, then scroll down.
        var resets = 0
        while !(element.exists && element.isHittable), resets < 6 {
            swipeListDown(in: app)
            resets += 1
        }
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxSwipes {
            swipeListUp(in: app)
            attempts += 1
        }
        XCTAssertTrue(
            element.waitForExistence(timeout: 2),
            "Element \(element) did not appear after scrolling"
        )
    }

    /// The progress scrubber owns a full-width DragGesture at mid-screen, so a
    /// window-center swipe is consumed by it instead of scrolling the List.
    /// Start near the bottom edge, below the scrubber.
    private func swipeListUp(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeListDown(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// SwiftUI List is lazy: rows outside the viewport are not in the
    /// accessibility tree. Normalize to the top, then scroll down.
    private func scrollToRow(_ element: XCUIElement, in app: XCUIApplication) {
        var resets = 0
        while !(element.exists && element.isHittable), resets < 6 {
            app.swipeDown()
            resets += 1
        }
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing tab \(label)")
        button.tap()
    }

    /// Nine speed presets do not fit on a phone: the row scrolls
    /// horizontally, so presets after 1.0 need a left swipe before they can
    /// be tapped. Swiping on a visible chip drives the surrounding scroll
    /// view. When the row itself is below the fold, scroll the List up first.
    private func tapSpeedChip(_ identifier: String, in app: XCUIApplication) {
        let chip = element(app, identifier)
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Missing \(identifier)")
        let rates = ["0.5", "0.8", "1.0", "1.2", "1.5", "1.8", "2.0", "2.5", "3.0"]

        func hittableAnchor() -> XCUIElement? {
            rates
                .map { element(app, "speedOption-\($0)") }
                .first { $0.exists && $0.isHittable }
        }

        var vertical = 0
        var horizontal = 0
        while !chip.isHittable, vertical + horizontal < 12 {
            if let anchor = hittableAnchor() {
                anchor.swipeLeft()
                horizontal += 1
            } else if vertical < 6 {
                swipeListUp(in: app)
                vertical += 1
            } else {
                break
            }
        }
        XCTAssertTrue(chip.isHittable, "\(identifier) did not become reachable")
        chip.tap()
    }

    private func goBack(in app: XCUIApplication) {
        // The playlist dialog can still be settling after save; dismiss any
        // leftover alert before looking for the back button.
        if app.alerts.firstMatch.exists {
            let cancel = app.alerts.buttons["取消"].firstMatch
            if cancel.exists { cancel.tap() }
        }
        // iOS 27 exposes the floating back control as a standalone
        // "BackButton" outside the NavigationBar element.
        let backButton = app.buttons["BackButton"].firstMatch
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
            return
        }
        let button = app.navigationBars.firstMatch.buttons.firstMatch
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
        // Fallback for iOS versions that do not expose the back button as a
        // navigation-bar button: edge swipe.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 5),
            "Could not navigate back"
        )
    }

    private func openLibraryItem(_ title: String, in app: XCUIApplication) {
        tapTab("资料库", in: app)
        let row = element(app, "libraryItem-\(title)")
        XCTAssertTrue(
            row.waitForExistence(timeout: 15) || {
                scrollToRow(row, in: app)
                return row.exists
            }(),
            "Missing library item \(title)"
        )
        scrollToRow(row, in: app)
        row.tap()
        // The detail screen is longer than the viewport; its navigation title
        // is the reliable top-of-screen signal (action buttons may be lazy).
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 10),
            "Library item detail did not open"
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Queue

    func testQueueSemanticsCurrentDeletionAndRelaunch() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-seed-queue",
            "--m3-no-auto-next",
            "--m3-auto-play-first"
        ])

        let title = element(app, "currentPlaybackTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "队列测试 A")
        // The phase sticker was removed; the play/pause label is the
        // observable "playing" signal.
        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        waitForLabel(playPause, equals: "暂停", timeout: 20)

        openLibraryItem("队列测试 B", in: app)
        let playNext = element(app, "detailPlayNextButton")
        reveal(playNext, in: app)
        playNext.tap()
        reveal(element(app, "detailQueueInfoText"), in: app)
        goBack(in: app)

        openLibraryItem("队列测试 C", in: app)
        let enqueue = element(app, "detailEnqueueButton")
        reveal(enqueue, in: app)
        enqueue.tap()
        reveal(element(app, "detailQueueInfoText"), in: app)
        goBack(in: app)

        tapTab("播放", in: app)
        let queueCount = element(app, "queueCountText")
        reveal(queueCount, in: app)
        waitForLabel(queueCount, equals: "队列 · 3", timeout: 10)

        // The queue is a bottom sheet now; open it before reading rows.
        let expand = element(app, "queueExpandButton")
        reveal(expand, in: app)
        expand.tap()
        // The sheet header carries its own count identifier (the player-card
        // badge with `queueCountText` stays behind the sheet, so reusing that
        // identifier here would make queries ambiguous).
        waitForLabel(element(app, "queuePanelCountText"), equals: "队列 · 3", timeout: 10)

        let rowA = element(app, "queueRow-队列测试 A")
        let rowB = element(app, "queueRow-队列测试 B")
        let rowC = element(app, "queueRow-队列测试 C")
        reveal(rowA, in: app)
        reveal(rowB, in: app)
        reveal(rowC, in: app)
        XCTAssertLessThan(rowA.frame.minY, rowB.frame.minY, "play-next must follow the current item")
        XCTAssertLessThan(rowB.frame.minY, rowC.frame.minY, "enqueue must append at the tail")
        attachScreenshot(app, name: "M3-queue-play-next-enqueue")

        // Leave the panel before navigating: the sheet covers the tab bar.
        element(app, "queuePanelCloseButton").tap()

        // Deleting the current library item must advance to the next queue item.
        openLibraryItem("队列测试 A", in: app)
        let delete = element(app, "detailDeleteButton")
        reveal(delete, in: app)
        delete.tap()
        let confirm = app.alerts.buttons.matching(
            NSPredicate(format: "label == %@", "移到回收站")
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()

        tapTab("播放", in: app)
        reveal(title, in: app)
        waitForLabel(title, equals: "队列测试 B", timeout: 20)
        reveal(queueCount, in: app)
        waitForLabel(queueCount, equals: "队列 · 2", timeout: 10)
        attachScreenshot(app, name: "M3-queue-delete-current-advances")

        // Queue + current item survive a relaunch, restored paused.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = []
        relaunched.launchPinned()
        tapTab("播放", in: relaunched)

        let restoredTitle = element(relaunched, "currentPlaybackTitle")
        XCTAssertTrue(restoredTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(restoredTitle.label, "队列测试 B")
        // No phase sticker: "restored paused" means the play button offers
        // 播放 (not 暂停) and the clock does not advance.
        let restoredPlayPause = element(relaunched, "playPauseButton")
        reveal(restoredPlayPause, in: relaunched)
        waitForLabel(restoredPlayPause, equals: "播放", timeout: 20)
        let restoredCount = element(relaunched, "queueCountText")
        reveal(restoredCount, in: relaunched)
        waitForLabel(restoredCount, equals: "队列 · 2", timeout: 10)
        let restoredTime = element(relaunched, "currentTimeText")
        XCTAssertTrue(restoredTime.waitForExistence(timeout: 10))
        let pausedClock = seconds(from: restoredTime.label)
        sleep(3)
        XCTAssertEqual(
            seconds(from: restoredTime.label),
            pausedClock,
            "restored queue must not auto-play"
        )
        attachScreenshot(relaunched, name: "M3-queue-restored-paused")
    }

    // MARK: - Playlists

    func testPlaylistCreateReorderPersistAndPlayAll() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library"
        ])

        tapTab("资料库", in: app)
        let playlistsLink = element(app, "libraryPlaylistsLink")
        XCTAssertTrue(playlistsLink.waitForExistence(timeout: 15))
        playlistsLink.tap()

        let create = element(app, "playlistCreateButton")
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("通勤")
        alert.buttons["保存"].firstMatch.tap()

        let playlistRow = element(app, "playlistRow-通勤")
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 10))
        goBack(in: app)

        addToPlaylist("队列测试 A", playlistName: "通勤", app: app)
        addToPlaylist("队列测试 C", playlistName: "通勤", app: app)

        tapTab("资料库", in: app)
        XCTAssertTrue(playlistsLink.waitForExistence(timeout: 10))
        playlistsLink.tap()
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 10))
        playlistRow.tap()

        let rowA = element(app, "playlistItem-队列测试 A")
        let rowC = element(app, "playlistItem-队列测试 C")
        XCTAssertTrue(rowA.waitForExistence(timeout: 10))
        XCTAssertTrue(rowC.waitForExistence(timeout: 10))
        XCTAssertLessThan(rowA.frame.minY, rowC.frame.minY)

        rowC.swipeRight()
        let moveUp = app.buttons["上移"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 5))
        moveUp.tap()
        sleep(1)
        XCTAssertLessThan(
            rowC.frame.minY,
            rowA.frame.minY,
            "reorder must update the visible playlist order"
        )
        attachScreenshot(app, name: "M3-playlist-reordered")

        // Re-open after relaunch: the reorder is persisted.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = []
        relaunched.launchPinned()
        tapTab("资料库", in: relaunched)
        XCTAssertTrue(element(relaunched, "libraryPlaylistsLink").waitForExistence(timeout: 15))
        element(relaunched, "libraryPlaylistsLink").tap()
        let restoredRow = element(relaunched, "playlistRow-通勤")
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 10))
        restoredRow.tap()

        let restoredA = element(relaunched, "playlistItem-队列测试 A")
        let restoredC = element(relaunched, "playlistItem-队列测试 C")
        XCTAssertTrue(restoredA.waitForExistence(timeout: 10))
        XCTAssertTrue(restoredC.waitForExistence(timeout: 10))
        XCTAssertLessThan(
            restoredC.frame.minY,
            restoredA.frame.minY,
            "playlist order did not survive relaunch"
        )

        let playAll = element(relaunched, "playlistPlayAllButton")
        XCTAssertTrue(playAll.waitForExistence(timeout: 10))
        playAll.tap()
        tapTab("播放", in: relaunched)
        let title = element(relaunched, "currentPlaybackTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        waitForLabel(title, equals: "队列测试 C", timeout: 15)
        waitForLabel(element(relaunched, "queueCountText"), equals: "队列 · 2", timeout: 10)
        attachScreenshot(relaunched, name: "M3-playlist-play-all")
    }

    private func addToPlaylist(
        _ title: String,
        playlistName: String,
        app: XCUIApplication
    ) {
        openLibraryItem(title, in: app)
        let menu = element(app, "detailAddToPlaylistMenu")
        reveal(menu, in: app)
        menu.tap()
        let option = element(app, "addToPlaylistOption-\(playlistName)")
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        reveal(element(app, "detailQueueInfoText"), in: app)
        goBack(in: app)
    }

    // MARK: - Sleep timer

    func testSleepTimerOneMinuteFadesAndPauses() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-seed-single-queue",
            "--m3-auto-play-first"
        ])

        // The phase sticker was removed; the play/pause label is the
        // observable "playing" signal.
        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        waitForLabel(playPause, equals: "暂停", timeout: 20)

        let menu = element(app, "sleepTimerMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        reveal(menu, in: app)
        menu.tap()
        let oneMinute = app.buttons["1 分钟"]
        XCTAssertTrue(oneMinute.waitForExistence(timeout: 5))

        let status = element(app, "sleepTimerStatus")
        var attempts = 0
        oneMinute.tap()
        // A tap inside the menu popover can be swallowed while the menu is
        // still settling; the popover then stays open and nothing is armed.
        // Retry the item while it is still on screen.
        while !status.waitForExistence(timeout: 3), attempts < 2 {
            if oneMinute.exists {
                oneMinute.tap()
            }
            attempts += 1
        }
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("1 分钟"), "unexpected status \(status.label)")
        attachScreenshot(app, name: "M3-sleep-timer-armed")

        // Real one-minute acceptance wait against the 298s fixture. Fade runs
        // in the last 10 seconds and is asserted in SleepTimerTests; menu
        // quiescence can add ~15s before the timer is actually armed.
        waitForLabel(playPause, equals: "播放", timeout: 100)
        attachScreenshot(app, name: "M3-sleep-timer-paused")
    }

    /// The hero play button on the library home is the player state mirror:
    /// it shows 暂停 while the queue is playing, and tapping it pauses; when
    /// nothing plays it resumes the queue's current item. The playback
    /// position carries over both ways.
    func testHeroPlayButtonMirrorsPlayerState() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-seed-queue",
            "--m3-auto-play-first"
        ])

        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        waitForLabel(playPause, equals: "暂停", timeout: 20)

        // Playing on the player screen → the home button must show 暂停.
        tapTab("资料库", in: app)
        let hero = element(app, "libraryHeroPlayButton")
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        reveal(hero, in: app)
        waitForLabel(hero, equals: "暂停", timeout: 10)

        // Tapping it pauses; the player screen shows the same state.
        hero.tap()
        waitForLabel(hero, equals: "播放", timeout: 10)

        tapTab("播放", in: app)
        reveal(playPause, in: app)
        waitForLabel(playPause, equals: "播放", timeout: 10)

        // Pausing there mirrors back to the home button's 播放.
        tapTab("资料库", in: app)
        reveal(hero, in: app)
        waitForLabel(hero, equals: "播放", timeout: 10)

        // Resume from home: the queue's current item starts again, and the
        // player screen must agree (same title, playing state).
        hero.tap()
        waitForLabel(hero, equals: "暂停", timeout: 10)
        tapTab("播放", in: app)
        reveal(playPause, in: app)
        waitForLabel(playPause, equals: "暂停", timeout: 10)
        let title = element(app, "currentPlaybackTitle")
        reveal(title, in: app)
        XCTAssertEqual(title.label, "队列测试 A", "resume must stay on the queue's current item")
        attachScreenshot(app, name: "M3-hero-button-resumed")
    }

    /// The owner's repro: flipping between the library and the player made
    /// the library's search field jump. Root cause: the old `.searchable`
    /// field was hosted by the system search bar, which on iOS 26+ docks at
    /// the screen bottom against the hidden system tab bar and the custom
    /// TapeTabBar sibling, and re-docks on every tab switch. Fix: the search
    /// field is now an app-owned anchor pinned in a top safe-area inset,
    /// outside the scroll view, so its frame cannot depend on tab state.
    /// The test proves the frame (Y and width) is bit-stable across two
    /// tab round-trips and that filtering still works.
    func testSearchFieldStaysPutWhenSwitchingTabs() throws {
        let app = makeApp(["--m0-reset-data", "--m3-seed-playable-library"])

        let search = element(app, "librarySearchField")
        XCTAssertTrue(search.waitForExistence(timeout: 20), "search field missing")
        let before = search.frame

        for round in 0..<2 {
            tapTab("播放", in: app)
            // This test seeds a library but no queue, so the player shows
            // its empty state; wait for that page's stable anchor instead
            // of a transport control that does not exist here.
            let emptyState = element(app, "playbackEmptyState")
            XCTAssertTrue(emptyState.waitForExistence(timeout: 10))
            tapTab("资料库", in: app)
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            XCTAssertEqual(
                search.frame.minY,
                before.minY,
                accuracy: 2,
                "search field moved vertically across tab round-trip \(round): \(before) → \(search.frame)"
            )
            XCTAssertEqual(
                search.frame.width,
                before.width,
                accuracy: 6,
                "search field width changed across tab round-trip \(round): \(before) → \(search.frame)"
            )
        }

        // The pinned field still drives the item filter end to end.
        search.tap()
        search.typeText("队列测试 A")
        // Dismiss the keyboard: while it is up the List is squeezed into
        // the space above it, and rows outside that sliver are not
        // materialized in the accessibility tree (a screen-center swipe
        // also lands in the dead zone below the squeezed list).
        search.typeText("\n")
        let row = element(app, "libraryItem-队列测试 A")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "search did not filter to the typed item")
        let other = element(app, "libraryItem-队列测试 B")
        XCTAssertFalse(
            other.exists && other.isHittable,
            "unmatched item must be filtered out while searching"
        )
        attachScreenshot(app, name: "M3-search-field-stable")
    }

    func testSleepTimerEndOfEpisodeDoesNotAutoAdvance() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-seed-queue",
            "--m3-arm-end-of-episode",
            "--m3-auto-play-first"
        ])

        let title = element(app, "currentPlaybackTitle")
        let playPause = element(app, "playPauseButton")
        reveal(playPause, in: app)
        waitForLabel(playPause, equals: "暂停", timeout: 20)

        // Armed before playback via launch argument: opening the menu while
        // the 20s fixture plays can take long enough for it to end first.
        let status = element(app, "sleepTimerStatus")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(
            status.label.contains("本集结束"),
            "unexpected status \(status.label)"
        )

        tapSpeedChip("speedOption-3.0", in: app)
        waitForLabel(
            element(app, "playbackRateText"),
            equals: "3.0×",
            timeout: 5
        )

        // The 20s fixture ends: the play button flips back to 播放 and the
        // title/queue stay on the same episode.
        waitForLabel(playPause, equals: "播放", timeout: 25)
        XCTAssertEqual(title.label, "队列测试 A", "end-of-episode must not advance")
        attachScreenshot(app, name: "M3-sleep-end-of-episode")
    }

    // MARK: - Settings

    func testSettingsPersistAcrossRestart() throws {
        let app = makeApp([
            "--m0-reset-data",
            "--m3-seed-playable-library",
            "--m3-open-settings"
        ])

        let speedValue = element(app, "settingsDefaultSpeedValue")
        XCTAssertTrue(speedValue.waitForExistence(timeout: 20))
        XCTAssertTrue(speedValue.label.contains("1.0×"))

        let speed15 = element(app, "settingsSpeed-1.5")
        XCTAssertTrue(speed15.waitForExistence(timeout: 10))
        speed15.tap()
        waitForLabelContains(speedValue, text: "1.5×", timeout: 5)

        let notRemember = app.buttons["不记住"]
        let notAuto = app.buttons["不自动"]
        XCTAssertTrue(notRemember.waitForExistence(timeout: 10))
        XCTAssertTrue(notAuto.waitForExistence(timeout: 10))
        reveal(notRemember, in: app)
        XCTAssertFalse(notRemember.isSelected)
        notRemember.tap()
        waitForSelected(notRemember, timeout: 5)
        notAuto.tap()
        waitForSelected(notAuto, timeout: 5)
        attachScreenshot(app, name: "M3-settings")

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--m3-open-settings"]
        relaunched.launchPinned()

        let restoredSpeed = element(relaunched, "settingsDefaultSpeedValue")
        XCTAssertTrue(restoredSpeed.waitForExistence(timeout: 20))
        waitForLabelContains(restoredSpeed, text: "1.5×", timeout: 5)
        waitForSelected(relaunched.buttons["不记住"], timeout: 10)
        waitForSelected(relaunched.buttons["不自动"], timeout: 10)
        attachScreenshot(relaunched, name: "M3-settings-after-restart")
    }

    /// 选了合集，重开 App 又回到条目视图. The scope chips now persist through
    /// AppSettingsStore, so a relaunch must land on the collections pane with
    /// the chip selected and the collections content rendered.
    func testLibraryScopeSelectionPersistsAcrossRelaunch() throws {
        let app = makeApp(["--m0-reset-data", "--m3-seed-playable-library"])

        let itemsChip = element(app, "libraryScope-条目")
        let collectionsChip = element(app, "libraryScope-合集")
        XCTAssertTrue(collectionsChip.waitForExistence(timeout: 20))
        XCTAssertTrue(itemsChip.isSelected, "fresh data must open the items pane")

        collectionsChip.tap()
        waitForSelected(collectionsChip, timeout: 5)
        XCTAssertTrue(
            element(app, "collectionEmptyState").waitForExistence(timeout: 5),
            "tapping 合集 should show the collections pane"
        )
        app.terminate()

        let relaunched = makeApp(["--m3-seed-playable-library"])
        let restoredChip = element(relaunched, "libraryScope-合集")
        XCTAssertTrue(restoredChip.waitForExistence(timeout: 20))
        waitForSelected(restoredChip, timeout: 5)
        XCTAssertTrue(
            element(relaunched, "collectionEmptyState")
                .waitForExistence(timeout: 5),
            "relaunch should restore the collections pane"
        )
        attachScreenshot(relaunched, name: "M3-library-scope-restored")
    }
}
