import XCTest

/// Failure paths: a session that stops, a pane closed in herdr, a page that closes and quit. A takeover is
/// in TerminalTests.
/// Streams are counted through the helper (`pgrep` on the session's `terminal session` runs).
extension OrielUITests {
    func testStoppedSessionSaysSoAndComesBackWhenStartedAgain() async throws {
        let five = try env("ORIEL_SESSION5")
        let (workspace, pane) = try await shown(running(five))
        relaunch(five)
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.exists(within: connect))
        try await expect("its stream") { try await streams(five).count == 1 }

        try await Self.post("\(five)/stop")
        // The "not running" page: its Start button.
        XCTAssertTrue(element("detail.start").exists(within: 10))
        XCTAssertFalse(terminal.exists)
        // Its last rows stay, without writes.
        // The button: its open context menu carries the same identifier.
        let row = app.buttons["workspace.\(workspace)"]
        row.rightClick()
        XCTAssertFalse(app.menuItems["Rename Workspace"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Rename Workspace"].vanishes(within: 2))
        row.doubleClick()
        XCTAssertFalse(element("workspace.\(workspace).rename").exists(within: 1))
        keepScreenshot("not running")
        try await expect("no stream") { try await streams(five).isEmpty }

        // Started in a terminal, not by the app: the app finds it again within seconds, with one stream.
        try await Self.post("\(five)/start")
        XCTAssertTrue(terminal.exists(within: 10))
        try await expect("one stream again") { try await streams(five).count == 1 }
        // Live updates are back: a tab made in herdr shows up.
        let tab = try await createTab(in: workspace, label: "back", session: five).tab
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
    }

    /// A launch on a stopped session starts it: the window's first page always runs.
    func testLaunchOnAStoppedSessionStartsIt() async throws {
        let five = try env("ORIEL_SESSION5")
        let workspace = try await shown(running(five)).workspace
        try await Self.post("\(five)/stop")
        try await expect("five to stop") { await (try? Self.snapshot(five)) == nil }
        relaunch(five)
        XCTAssertTrue(element("workspace.\(workspace)").exists(within: connect))
        try await Self.snapshot(five)
    }

    func testPaneClosedInHerdrDropsItsCardAndStream() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, first) = try await newTab("gone")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let doomed = try await terminalID(second)
        try await expect("its stream") { try await streams(one).contains { $0.contains(doomed) } }

        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 3))
        try await expect("its stream to end") { try await !streams(one).contains { $0.contains(doomed) } }
        XCTAssertTrue(element("pane.\(first)").exists)
    }

    func testClosingAPageAndQuittingLeaveNoStreams() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        XCTAssertTrue(element("tab.w1:t1").isSelected)
        // t1's three cards stream; the other session's one card once its page shows. The first page's stay in the
        // window's cache of recent terminals.
        try await expectStreams(3, 0)
        for _ in 0 ..< 2 {
            openPage(two)
            try await expectStreams(3, 1)
            closePage(two)
            // Its events stream and bridges end too.
            try await expect("no herdr runs on two") { try await runs(two).isEmpty }
            try await expectStreams(3, 0)
        }

        // No herdr run outlives the app: each ends when its stdin closes.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await expect("no herdr runs left") {
            let left = try await (runs(one), runs(two))
            return left.0.isEmpty && left.1.isEmpty
        }
    }

    private func expectStreams(_ inOne: Int, _ inTwo: Int) async throws {
        try await expect("\(inOne) streams on one, \(inTwo) on two") {
            let counts = try await (streams(one).count, streams(two).count)
            return counts == (inOne, inTwo)
        }
    }
}
