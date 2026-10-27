import AppKit
import XCTest

/// Several windows: windows on one session share its store and agree on one controller (D66); the other
/// watches with the control capsule. Session one's t1 is p1 | (p2 / p3), t2 holds p4.
extension OrielUITests {
    func testSecondWindowWatchesUntilItsUserTypes() async throws {
        let (first, second) = try newWindow()
        // Window 1 opened the session first: it controls, window 2 watches.
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        XCTAssertFalse(element("notice.controlled", in: first).exists)
        // The notice look, in the info tone, with no ✕.
        XCTAssertEqual(element("notice.controlled", in: second).images["notice.symbol"].label, "Information")
        XCTAssertFalse(element("notice.controlled", in: second).buttons["notice.close"].exists)
        let terminal = try await terminalID("w1:p1")
        try await expectStreams(terminal, control: 1, observe: 1)
        // Watched because of another Oriel window: the capsule, not the per-card button.
        XCTAssertFalse(element("pane.w1:p1.take-back", in: second).exists)
        // A wider card than window 1's, so the PTY size tells the windows apart.
        app.typeKey("s", modifierFlags: [.command, .control])
        keepScreenshot("window 1 controls", of: first)
        keepScreenshot("window 2 watches", of: second)

        // Typing in window 2 makes it the controller, and the key is sent.
        element("terminal.w1:p1", in: second).click()
        XCTAssertTrue(element("notice.controlled", in: first).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        app.typeText("echo one-$((40+2))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p1") { $0.contains("\none-42") }
        // keepScreenshot raises window 1, which is not input: window 2 keeps control (the PTY size below).
        keepScreenshot("window 1 observes the echo", of: first)
        // Window 1 still streams the pane, now watching it.
        try await expectStreams(terminal, control: 1, observe: 1)
        try await expectPTYSize("w1:p1", in: second)

        // Take Back in window 1: the capsule moves to window 2.
        raise(first)
        element("notice.controlled.take-back", in: first).click()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: first).vanishes(within: 3))
        try await expectPTYSize("w1:p1", in: first)

        // Each window keeps its own selection.
        raise(second)
        element("tab.w1:t2", in: second).click()
        XCTAssertTrue(element("tab.w1:t2", in: second).has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("tab.w1:t1", in: first).isSelected)
        // Window 1 never showed t2, so nobody holds p4: watching, window 2 still opens it as observe.
        try await expectStreams(terminalID("w1:p4"), control: 0, observe: 1)
        // A key press with no click takes the session, and is then sent.
        app.typeText("echo two-$((40+3))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p4") { $0.contains("\ntwo-43") }
        XCTAssertTrue(element("notice.controlled", in: first).exists(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectStreams(terminalID("w1:p4"), control: 1, observe: 0)
    }

    func testClosingTheControllingWindowHandsControlOver() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        // One events stream per session, however many windows show it (request bridges come and go).
        try await expect("one bridge run") { try await bridges(one) == 1 }
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        try await expect("still one bridge run") { try await bridges(one) == 1 }
        app.typeKey("s", modifierFlags: [.command, .control])

        // Window 1 controls and closes: window 2 takes over at its own card size.
        raise(first)
        first.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(first.vanishes(within: 3))
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectPTYSize("w1:p1", in: second)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
    }

    func testControllerClosingItsPageHandsControlOver() async throws {
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))
        app.typeKey("s", modifierFlags: [.command, .control])

        // Window 1 controls, opens session two and closes its page of session one: window 2 takes over.
        raise(first)
        openPage(two, in: first)
        // Still window 1's until its page closes.
        XCTAssertTrue(element("notice.controlled", in: second).exists)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 1)
        closePage(one, in: first)
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
        try await expectPTYSize("w1:p1", in: second)
    }

    func testWindowsOnDifferentSessionsEachControlTheirOwn() async throws {
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: connect))

        // Window 2 opens session two and closes its page of session one.
        openPage(two, in: second)
        // The capsule shows only while the page in view is watched.
        XCTAssertTrue(element("notice.controlled", in: second).vanishes(within: 3))
        element("sidebar.dot.\(one)", in: second).click()
        XCTAssertTrue(element("notice.controlled", in: second).exists(within: 3))
        closePage(one, in: second)

        XCTAssertTrue(element("terminal.w1:p1", in: second).exists(within: connect))
        XCTAssertFalse(element("notice.controlled", in: second).exists)
        XCTAssertFalse(element("notice.controlled", in: first).exists)
        try await expectStreams(terminalID("w1:p1", in: two), control: 1, observe: 0, session: two)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
        keepScreenshot("window 1 on session one", of: first)
        keepScreenshot("window 2 on session two", of: second)
    }

    // MARK: Helpers

    /// ⌘N once the first window shows session one: the first window and the new one.
    func newWindow() throws -> (XCUIElement, XCUIElement) {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let first = app.windows.firstMatch
        let identifier = first.identifier
        app.typeKey("n", modifierFlags: .command)
        return try (app.windows[identifier], otherWindow(than: identifier))
    }

    /// ⌘N opens a big window in the middle of the screen: 90 % of it, 1200 × 760 at least, the
    /// screen at most.
    func testNewWindowFillsMostOfTheScreen() throws {
        let (_, window) = try newWindow()
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        func side(_ length: CGFloat, _ least: CGFloat) -> CGFloat {
            min(length, max(least, length * 0.9))
        }
        XCTAssertEqual(window.frame.width, side(screen.width, 1200), accuracy: 2, "\(window.frame) in \(screen)")
        // A window as tall as the screen comes out a few points taller, its bottom under the Dock's top edge: 677 and
        // 679 in 674 on CI, the second window only (the first comes out at 674), from one run to the next.
        let height = side(screen.height, 760)
        XCTAssertTrue((height - 2 ... height + 8).contains(window.frame.height), "\(window.frame) in \(screen)")
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 2, "\(window.frame) in \(screen)")
    }

    /// The window that is not this one, once there are two; it shows session one.
    func otherWindow(than identifier: String) throws -> XCUIElement {
        XCTAssertTrue(app.windows.element(boundBy: 1).exists(within: 3))
        XCTAssertEqual(app.windows.count, 2)
        let other = try XCTUnwrap(app.windows.allElementsBoundByIndex.map(\.identifier).first { $0 != identifier })
        let window = app.windows[other]
        XCTAssertTrue(element("terminal.w1:p1", in: window).exists(within: connect))
        return window
    }

    /// The terminal's `control` and `observe` runs, any client's, settle at these counts.
    private func expectStreams(_ terminal: String, control: Int, observe: Int, session: String? = nil) async throws {
        try await expect("\(control) control and \(observe) observe runs of \(terminal)") {
            let runs = try await streams(session ?? one).filter { $0.contains(terminal) }
            let controls = runs.count { $0.contains("session control") },
                observes = runs.count { $0.contains("observe") }
            return controls == control && observes == observe
        }
    }

    private func bridges(_ session: String) async throws -> Int {
        try await runs(session).count { $0.contains("remote-api-bridge") }
    }

    /// Brings the window to the front with Window ▸ Cycle Through Windows (⌘`), as a click cannot: on CI's 1024×768
    /// screen both windows have the same frame. `firstMatch` is the front window.
    func raise(_ window: XCUIElement) {
        let identifier = window.identifier
        if app.windows.firstMatch.identifier != identifier {
            app.typeKey("`", modifierFlags: .command)
        }
        XCTAssertTrue(until(3) { app.windows.firstMatch.identifier == identifier }, "window \(identifier) in front")
    }
}
