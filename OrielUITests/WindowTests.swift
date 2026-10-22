import XCTest

/// Several windows (phase 16): windows on one session share its store and agree on one controller (D66); the other
/// watches with the control capsule. Session one's t1 is p1 | (p2 / p3), t2 holds p4.
extension OrielUITests {
    func testSecondWindowWatchesUntilItsUserTypes() async throws {
        let (first, second) = try newWindow()
        // Window 1 opened the session first: it controls, window 2 watches.
        XCTAssertTrue(element("notice.controlled", in: second).waitForExistence(timeout: connect))
        XCTAssertFalse(element("notice.controlled", in: first).exists)
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
        XCTAssertTrue(element("notice.controlled", in: first).waitForExistence(timeout: 3))
        XCTAssertTrue(element("notice.controlled", in: second).waitForNonExistence(timeout: 3))
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
        XCTAssertTrue(element("notice.controlled", in: second).waitForExistence(timeout: 3))
        XCTAssertTrue(element("notice.controlled", in: first).waitForNonExistence(timeout: 3))
        try await expectPTYSize("w1:p1", in: first)

        // Each window keeps its own selection.
        raise(second)
        element("tab.w1:t2", in: second).click()
        XCTAssertTrue(element("tab.w1:t2", in: second).wait(for: \.isSelected, toEqual: true, timeout: 2))
        XCTAssertTrue(element("tab.w1:t1", in: first).isSelected)
        // Window 1 never showed t2, so nobody holds p4: watching, window 2 still opens it as observe.
        try await expectStreams(terminalID("w1:p4"), control: 0, observe: 1)
        // A key press with no click takes the session, and is then sent.
        app.typeText("echo two-$((40+3))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p4") { $0.contains("\ntwo-43") }
        XCTAssertTrue(element("notice.controlled", in: first).waitForExistence(timeout: 3))
        XCTAssertTrue(element("notice.controlled", in: second).waitForNonExistence(timeout: 3))
        try await expectStreams(terminalID("w1:p4"), control: 1, observe: 0)
    }

    func testClosingTheControllingWindowHandsControlOver() async throws {
        XCTAssertTrue(element("terminal.w1:p1").waitForExistence(timeout: connect))
        // One events stream per session, however many windows show it (request bridges come and go).
        try await poll("one bridge run") { () async throws -> Bool? in try await bridges(one) == 1 ? true : nil }
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).waitForExistence(timeout: connect))
        try await poll("still one bridge run") { () async throws -> Bool? in try await bridges(one) == 1 ? true : nil }
        app.typeKey("s", modifierFlags: [.command, .control])

        // Window 1 controls and closes: window 2 takes over at its own card size.
        first.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(first.waitForNonExistence(timeout: 3))
        XCTAssertTrue(element("notice.controlled", in: second).waitForNonExistence(timeout: 3))
        try await expectPTYSize("w1:p1", in: second)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
    }

    func testControllerClosingItsPageHandsControlOver() async throws {
        let (first, second) = try newWindow()
        XCTAssertTrue(element("notice.controlled", in: second).waitForExistence(timeout: connect))
        app.typeKey("s", modifierFlags: [.command, .control])

        // Window 1 controls, opens session two and closes its page of session one: window 2 takes over.
        raise(first)
        openSessionTwo(in: first)
        // Still window 1's until its page closes.
        XCTAssertTrue(element("notice.controlled", in: second).exists)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 1)
        closePageOne(in: first)
        XCTAssertTrue(element("notice.controlled", in: second).waitForNonExistence(timeout: 3))
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
        try await expectPTYSize("w1:p1", in: second)
    }

    func testWindowsOnDifferentSessionsEachControlTheirOwn() async throws {
        XCTAssertTrue(element("terminal.w1:p1").waitForExistence(timeout: connect))
        // By identifier: `firstMatch` would follow the front window.
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        // A plain click on This Mac opens nothing; ⌥-click opens a window, as ⌘N.
        element("titlebar.machine", in: first).click()
        app.menuItems["This Mac"].click()
        XCTAssertFalse(app.windows.element(boundBy: 1).waitForExistence(timeout: 2))
        element("titlebar.machine", in: first).click()
        XCUIElement.perform(withKeyModifiers: .option) { app.menuItems["This Mac"].click() }
        let second = try otherWindow(than: identifier)
        XCTAssertTrue(element("notice.controlled", in: second).waitForExistence(timeout: connect))

        // Window 2 opens session two and closes its page of session one.
        openSessionTwo(in: second)
        // The capsule shows only while the page in view is watched.
        XCTAssertTrue(element("notice.controlled", in: second).waitForNonExistence(timeout: 3))
        element("sidebar.dot.\(one)", in: second).click()
        XCTAssertTrue(element("notice.controlled", in: second).waitForExistence(timeout: 3))
        closePageOne(in: second)

        XCTAssertTrue(element("terminal.w1:p1", in: second).waitForExistence(timeout: connect))
        XCTAssertFalse(element("notice.controlled", in: second).exists)
        XCTAssertFalse(element("notice.controlled", in: first).exists)
        let gamma = try await Self.call(two, "pane.get", ["pane_id": "w1:p1"])["pane"] as? [String: Any]
        try await expectStreams(XCTUnwrap(gamma?["terminal_id"] as? String), control: 1, observe: 0, session: two)
        try await expectStreams(terminalID("w1:p1"), control: 1, observe: 0)
        keepScreenshot("window 1 on session one", of: first)
        keepScreenshot("window 2 on session two", of: second)
    }

    // MARK: Helpers

    /// Opens session two's page in the window through the Open Session sheet.
    private func openSessionTwo(in window: XCUIElement) {
        element("sidebar.open-session", in: window).click()
        element("open-session.session.\(two)", in: window).click()
        XCTAssertTrue(element("sidebar.dot.\(two)", in: window).waitForExistence(timeout: connect))
    }

    /// Closes the window's page of session one from its header's context menu.
    private func closePageOne(in window: XCUIElement) {
        element("sidebar.dot.\(one)", in: window).click()
        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header", in: window).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        app.menuItems["Close Page"].click()
        XCTAssertTrue(element("sidebar.dot.\(one)", in: window).waitForNonExistence(timeout: 3))
    }

    /// ⌘N once the first window shows session one: the first window and the new one.
    private func newWindow() throws -> (XCUIElement, XCUIElement) {
        XCTAssertTrue(element("terminal.w1:p1").waitForExistence(timeout: connect))
        let first = app.windows.firstMatch
        let identifier = first.identifier
        app.typeKey("n", modifierFlags: .command)
        return try (app.windows[identifier], otherWindow(than: identifier))
    }

    /// The window that is not this one, once there are two; it shows session one.
    private func otherWindow(than identifier: String) throws -> XCUIElement {
        XCTAssertTrue(app.windows.element(boundBy: 1).waitForExistence(timeout: 3))
        XCTAssertEqual(app.windows.count, 2)
        let other = try XCTUnwrap(app.windows.allElementsBoundByIndex.map(\.identifier).first { $0 != identifier })
        let window = app.windows[other]
        XCTAssertTrue(element("terminal.w1:p1", in: window).waitForExistence(timeout: connect))
        return window
    }

    /// The terminal's `control` and `observe` runs, any client's, settle at these counts.
    private func expectStreams(_ terminal: String, control: Int, observe: Int, session: String? = nil) async throws {
        try await poll("\(control) control and \(observe) observe runs of \(terminal)") { () async throws -> Bool? in
            let runs = try await streams(session ?? one).filter { $0.contains(terminal) }
            let controls = runs.count { $0.contains("session control") },
                observes = runs.count { $0.contains("observe") }
            return controls == control && observes == observe ? true : nil
        }
    }

    private func bridges(_ session: String) async throws -> Int {
        let (data, _) = try await Self.post("\(session)/children", Data())
        return String(decoding: data, as: UTF8.self).split(separator: "\n").count { $0.contains("remote-api-bridge") }
    }

    /// Brings the window to the front: a click on a part the other window does not cover (macOS offsets a new window
    /// by about 29 pt), in its title row right of the tabs, else below its cards.
    func raise(_ window: XCUIElement) {
        let frame = window.frame
        let others = app.windows.allElementsBoundByIndex.filter { $0.identifier != window.identifier }.map(\.frame)
        let points = [CGVector(dx: frame.width * 0.75, dy: 8), CGVector(dx: frame.width / 2, dy: frame.height - 3)]
        guard let point = points.first(where: { point in
            !others.contains { $0.contains(CGPoint(x: frame.minX + point.dx, y: frame.minY + point.dy)) }
        }) else { return XCTFail("window \(window.identifier) is covered") }
        window.coordinate(withNormalizedOffset: .zero).withOffset(point).click()
    }
}
