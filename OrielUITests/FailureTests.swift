import XCTest

/// Failure paths (phase 6): a session that stops, a pane closed in herdr, a page that closes and quit. A takeover is
/// in TerminalTests.
/// Streams are counted through the helper (`pgrep` on the session's `terminal session` runs).
extension OrielUITests {
    func testStoppedSessionSaysSoAndComesBackWhenStartedAgain() async throws {
        let five = try XCTUnwrap(ProcessInfo.processInfo.environment["ORIEL_SESSION5"])
        let snapshot = try await Self.call(five, "session.snapshot", [:])["snapshot"] as? [String: Any]
        if (snapshot?["workspaces"] as? [Any] ?? []).isEmpty {
            try await Self.call(five, "workspace.create", ["label": "five", "cwd": "/tmp", "focus": false])
        }
        app.terminate()
        app.launchArguments = ["-session", five, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await poll("its stream") { () async throws -> Bool? in try await streams(five).count == 1 ? true : nil }

        let stopped = try await Self.post("\(five)/stop", Data())
        XCTAssertEqual(stopped.status, 200, String(decoding: stopped.data, as: UTF8.self))
        // The "not running" page: its Start button.
        XCTAssertTrue(element("detail.start").exists(within: 10))
        XCTAssertFalse(terminal.exists)
        // Its last rows stay, without writes.
        // The button: its open context menu carries the same identifier.
        let row = app.buttons["workspace.w1"]
        row.rightClick()
        XCTAssertFalse(app.menuItems["Rename Workspace"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuItems["Rename Workspace"].vanishes(within: 2))
        row.doubleClick()
        XCTAssertFalse(element("workspace.w1.rename").exists(within: 1))
        keepScreenshot("not running")
        try await poll("no stream") { () async throws -> Bool? in try await streams(five).isEmpty ? true : nil }

        // Started in a terminal, not by the app: the app finds it again within seconds, with one stream.
        let started = try await Self.post("\(five)/start", Data())
        XCTAssertEqual(started.status, 200)
        XCTAssertTrue(terminal.exists(within: 10))
        try await poll("one stream again") { () async throws -> Bool? in
            try await streams(five).count == 1 ? true : nil
        }
        // Live updates are back: a tab made in herdr shows up.
        let created = try await Self.call(five, "tab.create", ["workspace_id": "w1", "label": "back", "cwd": "/tmp",
                                                               "focus": false])
        let tab = try XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String)
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
    }

    func testPaneClosedInHerdrDropsItsCardAndStream() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, first) = try await newTab("gone")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let doomed = try await terminalID(second)
        try await poll("its stream") { () async throws -> Bool? in
            try await streams(one).contains { $0.contains(doomed) } ? true : nil
        }

        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 3))
        try await poll("its stream to end") { () async throws -> Bool? in
            try await streams(one).contains { $0.contains(doomed) } ? nil : true
        }
        XCTAssertTrue(element("pane.\(first)").exists)
    }

    func testClosingAPageAndQuittingLeaveNoStreams() async throws {
        let two = try XCTUnwrap(ProcessInfo.processInfo.environment["ORIEL_SESSION2"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        XCTAssertTrue(element("tab.w1:t1").isSelected)
        // t1's three cards stream; the other session's one card once its page shows. The first page's stay in the
        // window's cache of recent terminals.
        try await expectStreams(3, 0, two)
        for _ in 0 ..< 2 {
            openPage(two)
            try await expectStreams(3, 1, two)
            element("sidebar.header").rightClick()
            app.windows.firstMatch.menuItems["Close Page"].click()
            XCTAssertTrue(element("sidebar.dot.\(two)").vanishes(within: 2))
            // Its events stream and bridges end too.
            try await poll("no herdr runs on two") { () async throws -> Bool? in
                try await Self.post("\(two)/children", Data()).data.isEmpty ? true : nil
            }
            try await expectStreams(3, 0, two)
        }

        // No herdr run outlives the app: each ends when its stdin closes.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await poll("no herdr runs left") { () async throws -> Bool? in
            let left = try await (Self.post("\(one)/children", Data()), Self.post("\(two)/children", Data()))
            return left.0.data.isEmpty && left.1.data.isEmpty ? true : nil
        }
    }

    private func expectStreams(_ inOne: Int, _ inTwo: Int, _ two: String) async throws {
        try await poll("\(inOne) streams on one, \(inTwo) on two") { () async throws -> Bool? in
            let counts = try await (streams(one).count, streams(two).count)
            return counts == (inOne, inTwo) ? true : nil
        }
    }
}
