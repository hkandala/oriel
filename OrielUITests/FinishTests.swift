import XCTest

/// Phase 21: the find bar, links, the not running and failed start states, and programs of panes never shown.
extension OrielUITests {
    func testSecondPagesServerStopsAndStartsAloneOnItsPage() async throws {
        let five = try XCTUnwrap(ProcessInfo.processInfo.environment["ORIEL_SESSION5"])
        try await running(five)
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPage(five)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))

        let stopped = try await Self.post("\(five)/stop", Data())
        XCTAssertEqual(stopped.status, 200, String(decoding: stopped.data, as: UTF8.self))
        let start = element("detail.start")
        XCTAssertTrue(start.exists(within: 10))
        // The first page is not touched: its cards and streams stay.
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(element("terminal.w1:p1").exists(within: 3))
        XCTAssertFalse(start.exists)
        try await poll("one's three streams") { () async throws -> Bool? in
            try await streams(one).count == 3 ? true : nil
        }

        element("sidebar.dot.\(five)").click()
        XCTAssertTrue(start.exists(within: 3))
        start.click()
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        XCTAssertFalse(start.exists)
        try await Self.call(five, "session.snapshot", [:])
    }

    func testAFailedStartKeepsTheSheetOpenWithRetry() async throws {
        let six = try XCTUnwrap(ProcessInfo.processInfo.environment["ORIEL_SESSION6"])
        // No time to answer: every start the app makes fails, though launchd starts the server.
        app.terminate()
        app.launchArguments += ["-startTimeout", "0"]
        app.launch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        app.typeKey("n", modifierFlags: [.command, .shift])
        let filter = element("open-session.filter")
        XCTAssertTrue(hasKeyboard(filter))
        app.typeText(six)
        XCTAssertTrue(element("open-session.new.\(six)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])

        let notice = element("open-session.notice")
        XCTAssertTrue(notice.exists(within: 10))
        let text = "Could not start \(six)."
        let said = notice.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text,
                                                           text)).firstMatch
        XCTAssertTrue(said.exists, notice.debugDescription)
        XCTAssertEqual(notice.images["notice.symbol"].label, "Error")
        // The sheet stays open and its row's start is over.
        XCTAssertTrue(filter.exists)
        XCTAssertTrue(element("open-session.open").isEnabled)
        keepScreenshot("could not start")

        // The server came up after all: Retry finds it running and opens its page.
        try await running(six, start: false)
        notice.buttons["notice.retry"].click()
        XCTAssertTrue(filter.vanishes(within: connect))
        XCTAssertTrue(until(connect) { element("sidebar.header").value as? String == six })
    }

    func testFindScrollsHerdrsViewportToTheMatch() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("find")
        element("tab.\(tab)").click()
        try await Self.call(one, "pane.send_text", ["pane_id": pane,
                                                    "text": "for i in $(seq 1 200); do echo line $i; done\r"])
        try await waitFor(pane) { $0.contains("\nline 200\n") }
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))

        app.typeKey("f", modifierFlags: .command)
        let field = element("find.field"), count = element("find.count")
        XCTAssertTrue(hasKeyboard(field))
        // "line 4" and 40–49; the last one, nearest the bottom, first.
        field.typeText("line 4")
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        app.typeKey(.return, modifierFlags: .shift)
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)

        // Return left the field's text selected (AppKit's way): typing replaces it.
        app.typeText("line 42")
        XCTAssertTrue(count.has(\.stringValue, "1 of 1", within: 2), count.stringValue)
        // line 42 sits 158 lines above the bottom line: herdr's viewport scrolled to it.
        try await poll("herdr to scroll") { () async throws -> Bool? in
            try await scrollOffset(pane) > 100 ? true : nil
        }
        // Its highlight is on the row herdr shows it on.
        let screen = try await read(pane)
        let row = try XCTUnwrap(screen.split(separator: "\n", omittingEmptySubsequences: false)
            .firstIndex(of: "line 42"))
        let lit = element("find.highlights")
        XCTAssertTrue(lit.has(\.stringValue, "1 shown, current row \(row)", within: 2), lit.stringValue)
        keepScreenshot("find bar")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        try await poll("herdr back at the bottom") { () async throws -> Bool? in
            try await scrollOffset(pane) == 0 ? true : nil
        }
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
    }

    func testCommandClickOnALinkOpensIt() async throws {
        app.terminate()
        app.launchArguments += ["-recordLinks", "YES"]
        app.launch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("link")
        element("tab.\(tab)").click()
        try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "clear; echo https://example.com/oriel\r"])
        try await waitFor(pane) { $0.hasPrefix("https://example.com/oriel\n") }

        // The link is the first line: ⌘-click its sixth cell.
        let terminal = element("terminal.\(pane)")
        let grid = try XCTUnwrap(terminal.value as? String).split(separator: " ").compactMap { Double($0) }
        let cell = CGSize(width: terminal.frame.width / grid[1], height: terminal.frame.height / grid[0])
        let link = terminal.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cell.width * 5.5, dy: cell.height / 2))
        link.hover()
        XCUIElement.perform(withKeyModifiers: .command) { link.click() }
        XCTAssertTrue(element("app.links").has(\.stringValue, "https://example.com/oriel", within: 2))
    }

    /// herdr is asked what every pane runs on the first snapshot, also in tabs never shown.
    func testNeverShownTabsCardNamesItsProgram() {
        let capsule = element("tab.w1:t2")
        XCTAssertTrue(capsule.exists(within: connect))
        XCTAssertFalse(capsule.isSelected)
        capsule.hover()
        let row = element("hovercard.w1:p4")
        XCTAssertTrue(row.exists(within: 2))
        XCTAssertTrue(until(3) { !row.label.hasPrefix("terminal") }, row.label)
    }

    /// Waits until the session answers; `start` starts its server first when it does not, and gives it a workspace.
    private func running(_ session: String, start: Bool = true) async throws {
        if start, try await snapshot(of: session) == nil {
            try await Self.post("\(session)/start", Data())
        }
        let snapshot = try await poll("\(session) to answer") { try await snapshot(of: session) }
        if start, (snapshot["workspaces"] as? [Any] ?? []).isEmpty {
            try await Self.call(session, "workspace.create", ["label": "five", "cwd": "/tmp", "focus": false])
        }
    }

    /// herdr's viewport of the pane, in lines from the bottom.
    private func scrollOffset(_ pane: String) async throws -> Int {
        let panes = try await snapshot()?["panes"] as? [[String: Any]] ?? []
        let scroll = panes.first { $0["pane_id"] as? String == pane }?["scroll"] as? [String: Any]
        return try XCTUnwrap(scroll?["offset_from_bottom"] as? Int)
    }

    /// The session's snapshot, nil while it does not answer (`call` fails the test then).
    private func snapshot(of session: String) async throws -> [String: Any]? {
        let body = Data("{\"id\":\"1\",\"method\":\"session.snapshot\",\"params\":{}}\n".utf8)
        let (data, status) = try await Self.post(session, body)
        guard status == 200, let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (reply["result"] as? [String: Any])?["snapshot"] as? [String: Any]
    }
}
