import XCTest

/// Agents (phase 15): states in tabs and workspace rows, the Agents button, its popover and the Agents view. Every
/// status comes from `pane.report_agent` on a throwaway tab, closed after the test (its agent goes with it).
extension OrielUITests {
    func testWorkingAgentShowsInItsTabAndWorkspace() async throws {
        XCTAssertTrue(element("tab.w1:t2").waitForExistence(timeout: connect))
        let (tab, pane) = try await newTab("build", in: "w1")
        try await report(pane, "working")
        let dots = element("tab.\(tab).working")
        XCTAssertTrue(dots.waitForExistence(timeout: 3))
        try await waitForValue("tab.\(tab)", containing: "codex, working")
        try await waitForValue("workspace.w1", containing: "working")
        XCTAssertFalse((element("tab.w1:t1").value as? String ?? "").contains("working"))
        keepScreenshot("working dots")

        // The selected tab shows no dots.
        element("tab.\(tab)").click()
        XCTAssertTrue(dots.waitForNonExistence(timeout: 2))
    }

    func testBlockedAgentNeedsYouAndThePopoverGoesToIt() async throws {
        let button = element("titlebar.agents")
        XCTAssertTrue(button.waitForExistence(timeout: connect))
        button.hover()
        XCTAssertTrue(element("agents.popover.empty").waitForExistence(timeout: 2))
        XCTAssertEqual(element("agents.popover.empty").value as? String, "Nobody needs you")
        element("workspace.w1").hover()
        XCTAssertTrue(element("agents.popover").waitForNonExistence(timeout: 2))

        let (tab, pane) = try await newTab("deploy")
        try await report(pane, "blocked", agent: "claude")
        try await waitForValue("tab.\(tab)", containing: "claude, needs you")
        try await waitForValue("workspace.w2", containing: "needs you")
        try await waitForValue("titlebar.agents", containing: "1 need you")
        keepScreenshot("needs you badge")
        // The banner, when this Mac lets Oriel notify (no assertion: the permission is the user's).
        let banner = XCUIApplication(bundleIdentifier: "com.apple.notificationcenterui").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'claude needs you'")).firstMatch
        if banner.waitForExistence(timeout: 3) {
            keep(banner.screenshot(), "notification banner")
        }

        button.hover()
        let row = element("agents.popover").descendants(matching: .any)["agent.\(pane)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        keepScreenshot("needs-you popover")
        row.click()
        XCTAssertTrue(element("tab.\(tab)").wait(for: \.isSelected, toEqual: true, timeout: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
        XCTAssertTrue(element("agents.popover").waitForNonExistence(timeout: 2))
        XCTAssertEqual(element("sidebar.header").value as? String, one)
    }

    func testAnotherSessionsAgentCountsInTheDockBadgeOnly() async throws {
        let two = try XCTUnwrap(ProcessInfo.processInfo.environment["ORIEL_SESSION2"])
        XCTAssertTrue(element("workspace.w1").waitForExistence(timeout: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: 2))

        try await report("w1:p1", "blocked", session: two)
        addTeardownBlock {
            _ = try? await Self.call(two, "pane.release_agent", ["pane_id": "w1:p1", "source": "oriel-e2e",
                                                                 "agent": "codex"])
        }
        try await waitForValue("app.badge", containing: "1")
        let tile = XCUIApplication(bundleIdentifier: "com.apple.dock").icons["Oriel"]
        if tile.exists {
            keep(tile.screenshot(), "dock badge")
        }
        XCTAssertEqual(element("titlebar.agents").value as? String, "0 need you")
        element("sidebar.dot.\(two)").click()
        try await waitForValue("titlebar.agents", containing: "1 need you")
    }

    func testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder() async throws {
        XCTAssertTrue(element("workspace.w1").waitForExistence(timeout: connect))
        let idle = try await newTab("review", in: "w1").pane
        try await report(idle, "idle", agent: "pi")
        let working = try await newTab("api", in: "w1").pane
        try await report(working, "working")
        let blocked = try await newTab("deploy").pane
        try await report(blocked, "blocked", agent: "claude")
        let done = try await finish(newTab("docs"))

        app.typeKey(".", modifierFlags: .command)
        try await waitForValue("sidebar.header", containing: "\(one) · agents")
        let rows = [blocked, working, done, idle].map { element("agent.\($0)") }
        XCTAssertTrue(rows[3].waitForExistence(timeout: 2))
        XCTAssertEqual(rows.map { $0.value as? String }, ["Needs you", "Working", "Done", "Idle"])
        XCTAssertEqual(rows.map(\.frame.minY), rows.map(\.frame.minY).sorted())
        let groups = ["Needs you", "Working", "Done", "Idle"].map { element("agents.group.\($0)").frame.minY }
        XCTAssertEqual(zip(groups, rows).filter { $0 < $1.frame.minY }.count, 4)
        keepScreenshot("agents view by priority")

        element("agents.sort").click()
        app.menuItems["Workspace order"].click()
        try await waitForValue("agents.sort", containing: "workspace")
        let order = [idle, working, blocked, done].map { element("agent.\($0)").frame.minY }
        XCTAssertEqual(order, order.sorted())
        XCTAssertFalse(element("agents.group.Idle").exists)
        keepScreenshot("agents view in workspace order")

        app.typeKey(".", modifierFlags: .command)
        try await waitForValue("sidebar.header", containing: one)
        XCTAssertFalse((element("sidebar.header").value as? String ?? "").contains("agents"))
        XCTAssertTrue(element("workspace.w1").exists)
    }

    func testAFinishShowsDoneUntilItsRowIsClicked() async throws {
        XCTAssertTrue(element("workspace.w1").waitForExistence(timeout: connect))
        let created = try await newTab("docs")
        let pane = try await finish(created)
        try await waitForValue("tab.\(created.tab)", containing: "codex, finished")
        try await waitForValue("workspace.w2", containing: "finished")
        keepScreenshot("finished badge")

        element("titlebar.agents").click()
        let row = element("agent.\(pane)")
        try await waitForValue("agent.\(pane)", containing: "Done")
        row.click()
        try await waitForValue("agent.\(pane)", containing: "Idle")
        XCTAssertTrue(element("tab.\(created.tab)").isSelected)
    }

    func testRelaunchCountsAnOldFinishAsSeen() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        let pane = try await newTab("tests").pane
        try await report(pane, "working")
        try await waitForValue("workspace.w2", containing: "working")
        app.terminate()
        try await report(pane, "idle")
        app.launch()
        try await waitForValue("workspace.w2", containing: "idle")
        XCTAssertFalse((element("workspace.w2").value as? String ?? "").contains("finished"))
    }

    private func keep(_ screenshot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Reports the agent's state with an increasing `seq` (herdr drops an older one).
    func report(_ pane: String, _ state: String, agent: String = "codex", session: String? = nil) async throws {
        try await Self.call(session ?? one, "pane.report_agent", [
            "pane_id": pane, "source": "oriel-e2e", "agent": agent, "state": state,
            "seq": Int(Date.now.timeIntervalSince1970 * 1000),
        ])
    }

    /// The tab's agent works, the app sees it, then it finishes: a finish not seen. The pane.
    private func finish(_ created: (tab: String, pane: String)) async throws -> String {
        try await report(created.pane, "working")
        try await waitForValue("tab.\(created.tab)", containing: "working")
        try await report(created.pane, "idle")
        return created.pane
    }

    private func waitForValue(_ identifier: String, containing text: String) async throws {
        try await poll("\(identifier) to say \(text)") { () async throws -> Bool? in
            (element(identifier).value as? String)?.contains(text) == true ? true : nil
        }
    }
}
