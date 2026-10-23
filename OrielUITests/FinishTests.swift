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
