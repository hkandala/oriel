import XCTest

/// Agents (phase 15): states in tabs and workspace rows, the Agents button, its popover and the Agents view. Every
/// status comes from `pane.report_agent` on a throwaway tab, closed after the test (its agent goes with it).
extension OrielUITests {
    func testWorkingAgentShowsInItsTabAndWorkspace() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let (tab, pane) = try await newTab("build", in: "w1")
        try await report(pane, "working")
        let dots = element("tab.\(tab).working")
        XCTAssertTrue(dots.exists(within: 3))
        try await waitForValue("tab.\(tab)", containing: "codex, working")
        try await waitForValue("workspace.w1", containing: "working")
        keepScreenshot("working dots")

        // The selected tab shows no dots.
        element("tab.\(tab)").click()
        XCTAssertTrue(dots.vanishes(within: 2))
    }

    func testBlockedAgentNeedsYouAndThePopoverGoesToIt() async throws {
        let button = element("titlebar.agents")
        XCTAssertTrue(button.exists(within: connect))
        button.hover()
        XCTAssertTrue(element("agents.popover.empty").exists(within: 2))
        XCTAssertEqual(element("agents.popover.empty").value as? String, "Nobody needs you")
        element("workspace.w1").hover()
        XCTAssertTrue(element("agents.popover").vanishes(within: 2))

        let (tab, pane) = try await newTab("deploy")
        try await report(pane, "blocked", agent: "claude")
        try await waitForValue("tab.\(tab)", containing: "claude, needs you")
        try await waitForValue("workspace.w2", containing: "needs you")
        try await waitForValue("titlebar.agents", containing: "1 need you")
        keepScreenshot("needs you badge")

        button.hover()
        let row = element("agents.popover").descendants(matching: .any)["agent.\(pane)"]
        XCTAssertTrue(row.exists(within: 2))
        keepScreenshot("needs-you popover")
        row.click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
        XCTAssertTrue(element("agents.popover").vanishes(within: 2))
        XCTAssertEqual(element("sidebar.header").value as? String, one)
    }

    func testAnotherSessionsAgentCountsInTheDockBadgeOnly() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(element("workspace.w2").exists(within: 2))

        addTeardownBlock { [two] in
            _ = try? await Self.call(two, "pane.release_agent", ["pane_id": "w1:p1", "source": "oriel-e2e",
                                                                 "agent": "codex"])
        }
        try await report("w1:p1", "blocked", session: two)
        try await poll("the badge to count the other page") { element("app.badge").value as? String == "1" ? true : nil
        }
        XCTAssertEqual(element("titlebar.agents").value as? String, "0 need you")
        element("sidebar.dot.\(two)").click()
        try await waitForValue("titlebar.agents", containing: "1 need you")
        // Its Agents view lists it.
        app.typeKey(".", modifierFlags: .command)
        try await waitForValue("sidebar.header", containing: "\(two) · agents")
        try await waitForValue("agent.w1:p1", containing: "Needs you")
    }

    func testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
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
        XCTAssertTrue(rows[3].exists(within: 2))
        XCTAssertEqual(rows.map { $0.value as? String }, ["Needs you", "Working", "Done", "Idle"])
        // Each group's header, with its count, sits above its row and below the row before.
        let groups = ["Needs you", "Working", "Done", "Idle"].map { element("agents.group.\($0)") }
        XCTAssertEqual(groups.map { $0.value as? String }, ["Needs you 1", "Working 1", "Done 1", "Idle 1"])
        let tops = zip(groups, rows).flatMap { [$0.frame.minY, $1.frame.minY] }
        XCTAssertEqual(tops, tops.sorted())
        keepScreenshot("agents view by priority")

        // The footer filter keeps the rows of one workspace.
        element("sidebar.filter").click()
        element("sidebar.filter").typeText("beta")
        XCTAssertTrue(rows[1].vanishes(within: 2))
        XCTAssertEqual(rows.map(\.exists), [true, false, true, false])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(rows[3].exists(within: 2))

        element("agents.sort").click()
        app.menuItems["Workspace order"].click()
        try await waitForValue("agents.sort", containing: "workspace")
        XCTAssertTrue(element("agents.group.Idle").vanishes(within: 2))
        try await poll("rows in workspace order") { () -> Bool? in
            let order = [idle, working, blocked, done].map { element("agent.\($0)").frame.minY }
            return order == order.sorted() ? true : nil
        }
        keepScreenshot("agents view in workspace order")

        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("workspace.w1").exists(within: 2))
        XCTAssertEqual(element("sidebar.header").value as? String, one)
    }

    func testAFinishShowsDoneUntilItsRowIsClicked() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let created = try await newTab("docs")
        let pane = try await finish(created)
        try await waitForValue("tab.\(created.tab)", containing: "codex, finished")
        try await waitForValue("workspace.w2", containing: "finished")
        keepScreenshot("finished badge")

        // From a collapsed sidebar, the button opens it in the Agents view.
        element("titlebar.sidebar").click()
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        element("titlebar.agents").click()
        try await waitForValue("sidebar.header", containing: "· agents")
        let row = element("agent.\(pane)")
        try await waitForValue("agent.\(pane)", containing: "Done")
        row.click()
        try await waitForValue("agent.\(pane)", containing: "Idle")
        XCTAssertTrue(element("tab.\(created.tab)").isSelected)
        // View ▸ Show Agents turns it off; the sidebar stays.
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Show Agents"].click()
        XCTAssertTrue(element("workspace.w2").exists(within: 2))
        XCTAssertTrue(element("sidebar").exists)
    }

    func testRelaunchCountsAnOldFinishAsSeen() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let pane = try await newTab("tests").pane
        try await report(pane, "working")
        try await waitForValue("workspace.w2", containing: "working")
        app.terminate()
        try await report(pane, "idle")
        app.launch()
        try await waitForValue("workspace.w2", containing: "idle")
        XCTAssertFalse((element("workspace.w2").value as? String ?? "").contains("finished"))
        keepScreenshot("idle ring")
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

    func waitForValue(_ identifier: String, containing text: String) async throws {
        try await poll("\(identifier) to say \(text)") { () async throws -> Bool? in
            (element(identifier).value as? String)?.contains(text) == true ? true : nil
        }
    }
}
