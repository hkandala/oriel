import XCTest

/// Live terminals (phase 4), checked through herdr: `pane.read`, `pane.get` and a second
/// `control` stream from the helper. Session one's t1 is p1 | (p2 / p3), t2 holds p4.
extension OrielUITests {
    func testCardsAttachAtTheirSize() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        for pane in ["w1:p1", "w1:p2", "w1:p3"] {
            try await expectPTYSize(pane)
            // The stream opened at that size: no resize after attach, so an agent draws once.
            let terminal = try await terminalID(pane)
            let line = try await streams(one).first { $0.contains(terminal) } ?? ""
            let rows = line.firstMatch(of: /--rows (\d+)/)?.1, cols = line.firstMatch(of: /--cols (\d+)/)?.1
            XCTAssertEqual("\(rows ?? "") \(cols ?? "")", element("terminal.\(pane)").value as? String, line)
        }
        keepScreenshot("terminals")
    }

    func testResizingACardResizesThePTY() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await expectPTYSize("w1:p1")
        let before = terminal.value as? String
        // Hiding the sidebar widens the cards. Not the window: CI's window already fills the screen
        // (Zoom changes nothing there), and a drag on its corner does not resize it under XCUITest.
        element("titlebar.sidebar").click()
        XCTAssertTrue(until(3) { terminal.value as? String != before })
        try await expectPTYSize("w1:p1")
    }

    func testScrollingMovesTheViewport() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p1")
        try await send("seq 1 500\r", to: "w1:p1")
        try await waitFor("w1:p1") { $0.contains("\n500\n") }
        // The wheel goes where the pointer is. Which sign is up depends on the Mac's natural
        // scrolling setting (up for negative here, down on CI), so try both; at the bottom, down
        // does nothing.
        terminal.hover()
        var delta = -100.0
        try await poll("the viewport to move", times: 10) { () async throws -> Int? in
            terminal.scroll(byDeltaX: 0, deltaY: delta)
            delta = -delta
            try await Task.sleep(for: .milliseconds(300))
            let offset = try await (pane("w1:p1")["scroll"] as? [String: Any])?["offset_from_bottom"] as? Int ?? 0
            return offset > 0 ? offset : nil
        }
        // Up and down do not page the strip.
        XCTAssertTrue(element("tab.w1:t1").isSelected)
        keepScreenshot("vertical scroll")
    }

    /// A sideways scroll over a terminal pages the strip, and the new tab's panes attach.
    func testSwipingOverACardPagesToTheNextTab() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p1")
        keepScreenshot("before the swipe")
        // Which sign goes right follows the natural scrolling setting (see testScrollingMovesTheViewport); toward
        // the first tab nothing moves, so try both.
        let width = Double(terminal.frame.width)
        var delta = -width
        try await expect("the swipe to select the second tab", times: 6) {
            terminal.hover()
            terminal.scroll(byDeltaX: delta, deltaY: 0)
            delta = -delta
            try await Task.sleep(for: .milliseconds(700))
            return element("tab.w1:t2").isSelected
        }
        keepScreenshot("after the swipe")
        XCTAssertTrue(app.windows.firstMatch.has(\.title, "second - \(one)", within: 2))
        try await expectPTYSize("w1:p4")
    }

    func testCommandDigitSelectsATab() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        keepScreenshot("command 2")
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("tab.w1:t1").has(\.isSelected, true, within: 2))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))

        // ⌘1 picks a tab of the workspace shown now, and leaves the other one's selection alone.
        element("workspace.w2").click()
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        element("workspace.w1").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        XCTAssertTrue(element("tab.w1:t2").isSelected)
    }

    func testSwitchingTabsKeepsTheLastTabAttached() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let old = try await terminalID("w1:p1"), new = try await terminalID("w1:p4")
        // The app controls p1 (its PTY has the card's size), so a second controller is refused. A
        // probe before the app attached would win, and the app would only watch.
        try await expectPTYSize("w1:p1")
        try await waitForControl(old)
        let rows = try await viewportRows("w1:p1")

        element("tab.w1:t2").click()
        XCTAssertTrue(element("terminal.w1:p4").exists(within: 2))
        try await expectPTYSize("w1:p4")
        try await waitForControl(new)
        // The last tab stays attached at its size, so coming back to it resizes nothing.
        try await waitForControl(old)
        let away = try await viewportRows("w1:p1")
        XCTAssertEqual(away, rows)

        element("tab.w1:t1").click()
        XCTAssertTrue(element("terminal.w1:p1").exists(within: 2))
        try await waitForControl(old)
        let back = try await viewportRows("w1:p1")
        XCTAssertEqual(back, rows)
    }

    func testEachTabKeepsItsKeyboardCard() async throws {
        let terminal = element("terminal.w1:p2")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p2")
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        element("tab.w1:t2").click()
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p4")))
        element("tab.w1:t1").click()
        // Back on t1, the keyboard is on p2 again, not on herdr's focused p1.
        XCTAssertTrue(hasKeyboard(terminal))
        app.typeText("echo oriel-$((40+3))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.contains("\noriel-43") }
        let other = try await read("w1:p1")
        XCTAssertFalse(other.contains("oriel-43"))

        // Up arrow (a herdr key) brings the command back.
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.components(separatedBy: "\noriel-43").count == 3 }
    }

    func testTakenOverCardOffersTakeBack() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("taken")
        element("tab.\(tab)").click()
        // The app controls the pane (its PTY has the card's size) before the probe: a probe that came first would
        // win, and the app would only watch.
        try await expectPTYSize(pane)
        let terminal = try await terminalID(pane)
        try await waitForControl(terminal)

        // Another client takes the pane (and lets go at once): the card watches and offers it back.
        try await Self.post("\(one)/takeover", Data(terminal.utf8))
        let takeBack = element("pane.\(pane).take-back")
        XCTAssertTrue(takeBack.exists(within: 3))
        XCTAssertEqual(takeBack.label, "In use elsewhere · Take Back")
        keepScreenshot("in use elsewhere")
        takeBack.click()
        XCTAssertTrue(takeBack.vanishes(within: 3))
        try await waitForControl(terminal)
        element("terminal.\(pane)").click()
        try await typeAndRead(pane)
    }

    // MARK: Helpers

    private func viewportRows(_ pane: String) async throws -> Int {
        try await field((self.pane(pane)["scroll"] as? [String: Any])?["viewport_rows"], "\(pane)'s rows")
    }

    /// A `control` stream from the helper, let go at once, until herdr refuses it: another client controls the
    /// terminal.
    private func waitForControl(_ terminal: String) async throws {
        try await expect("herdr to refuse a second control of \(terminal)", times: 20) {
            try await String(decoding: Self.post("\(one)/control", Data(terminal.utf8)), as: UTF8.self)
                .contains("already has an attached client")
        }
    }
}
