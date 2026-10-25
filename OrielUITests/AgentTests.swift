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
        XCTAssertEqual(element("agents.popover.empty").value as? String, "All caught up")
        XCTAssertFalse(element("agents.popover.header").exists)
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
        XCTAssertTrue(element("agents.popover.header").exists)
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
        try await expect("the badge to count the other page") { element("app.badge").value as? String == "1" }
        XCTAssertEqual(element("titlebar.agents").value as? String, "0 need you")
        element("sidebar.dot.\(two)").click()
        try await waitForValue("titlebar.agents", containing: "1 need you")
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("agents.sort").exists(within: 2))
        XCTAssertEqual(element("sidebar.header").value as? String, two)
        try await waitForValue("agent.w1:p1", containing: "Needs you")
    }

    func testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let idle = try await newTab("review", in: "w1").pane
        try await report(idle, "idle", agent: "pi")
        // A split, not a fourth tab in w1: 220 pt tabs, and only 3 fit on CI's window.
        let working = try await split(idle)
        try await report(working, "working")
        try await Self.call(one, "pane.rename", ["pane_id": working, "label": "fixer"])
        let blocked = try await newTab("deploy").pane
        try await report(blocked, "blocked", agent: "claude")
        let done = try await finish(newTab("docs"))

        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("agents.sort").exists(within: 2))
        // The session's name alone.
        XCTAssertEqual(element("sidebar.header").value as? String, one)
        let rows = [blocked, working, done, idle].map { element("agent.\($0)") }
        XCTAssertTrue(rows[3].exists(within: 2))
        XCTAssertEqual(rows.map { $0.value as? String }, ["Needs you", "Working", "Done", "Idle"])
        // The pane's name, else the agent's; line 2 names the workspace.
        try await expect("the pane's name as the title") { rows[1].label.hasPrefix("fixer, alpha · ") }
        XCTAssertTrue(rows[3].label.hasPrefix("pi, alpha · "), rows[3].label)
        // Each group's header, with its count, sits above its row and below the row before.
        let groups = ["Needs you", "Working", "Done", "Idle"].map { element("agents.group.\($0)") }
        XCTAssertEqual(groups.map { $0.value as? String }, ["Needs you 1", "Working 1", "Done 1", "Idle 1"])
        let tops = zip(groups, rows).flatMap { [$0.frame.minY, $1.frame.minY] }
        XCTAssertEqual(tops, tops.sorted())
        // One leading edge: the header's text, the group labels and the row icons (8 pt into each row); the sort
        // label's text (6 pt into its button) ends where the rows' times do (8 pt before each row's end).
        let header = element("sidebar.header").frame, sort = element("agents.sort").frame
        let frames = "header \(header), sort \(sort), group \(groups[0].frame), row \(rows[0].frame)"
        XCTAssertEqual(header.minX, rows[0].frame.minX + 8, accuracy: 0.5, frames)
        XCTAssertEqual(groups[0].frame.minX, header.minX, accuracy: 0.5, frames)
        XCTAssertEqual(sort.maxX - 6, rows[0].frame.maxX - 8, accuracy: 0.5, frames)
        keepScreenshot("agents view by priority")

        // The footer filter keeps the rows of one workspace, or of a pane's name.
        filter("beta", keeps: rows, [true, false, true, false])
        filter("fixer", keeps: rows, [false, true, false, false])

        element("agents.sort").click()
        app.menuItems["Workspace order"].click()
        try await waitForValue("agents.sort", containing: "workspace")
        XCTAssertTrue(element("agents.group.Idle").vanishes(within: 2))
        // Each workspace's name above its rows, whose line 2 drops it.
        let alpha = element("agents.workspace.w1"), beta = element("agents.workspace.w2")
        try await expect("rows in workspace order under their workspaces") {
            let order = [alpha, rows[3], rows[1], beta, rows[0], rows[2]].map(\.frame.minY)
            return order == order.sorted()
        }
        XCTAssertEqual([alpha, beta].map { $0.value as? String }, ["alpha", "beta"])
        XCTAssertEqual(alpha.frame.minX, header.minX, accuracy: 0.5)
        XCTAssertFalse(rows.contains { $0.label.contains("alpha") || $0.label.contains("beta") },
                       rows.map(\.label).joined(separator: "; "))
        keepScreenshot("agents view in workspace order")

        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("workspace.w1").exists(within: 2))
        XCTAssertEqual(element("sidebar.header").value as? String, one)
    }

    /// The shown tab's keyboard card lights its agent's row, as the selected workspace row.
    func testTheKeyboardCardsAgentIsLitInTheAgentsView() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let first = try await newTab("deploy").pane
        try await report(first, "blocked", agent: "claude")
        let second = try await split(first)
        try await report(second, "working")
        app.typeKey(".", modifierFlags: .command)
        let rows = [first, second].map { element("agent.\($0)") }
        XCTAssertTrue(rows[1].exists(within: 2))
        rows[1].click()
        XCTAssertTrue(rows[1].has(\.isSelected, true, within: 2))
        XCTAssertFalse(rows[0].isSelected)
        // The keyboard moves to the other card without the list.
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(rows[0].has(\.isSelected, true, within: 2))
        XCTAssertFalse(rows[1].isSelected)
        keepScreenshot("lit agent row")
        // beta's first tab shown: neither is its keyboard card.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(rows[0].has(\.isSelected, false, within: 2))
        XCTAssertFalse(rows[1].isSelected)
    }

    func testAFinishShowsDoneUntilItsRowIsClicked() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let created = try await newTab("docs")
        let pane = try await finish(created)
        // The title says so for 3 s.
        let capsule = element("tab.\(created.tab)")
        XCTAssertTrue(until(3) { capsule.label.contains("codex finished") }, capsule.label)
        try await waitForValue("tab.\(created.tab)", containing: "codex, finished")
        try await waitForValue("workspace.w2", containing: "finished")
        keepScreenshot("finished badge")
        XCTAssertTrue(until(5) { !capsule.label.contains("codex finished") }, capsule.label)

        // From a collapsed sidebar, the button opens it in the Agents view.
        element("titlebar.sidebar").click()
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        element("titlebar.agents").click()
        XCTAssertTrue(element("agents.sort").exists(within: 2))
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

    /// Types in the footer filter, checks which rows stay, then clears it with Esc.
    private func filter(_ text: String, keeps rows: [XCUIElement], _ kept: [Bool]) {
        element("sidebar.filter").click()
        element("sidebar.filter").typeText(text)
        XCTAssertTrue(until(2) { rows.map(\.exists) == kept }, text)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(until(2) { rows.allSatisfy(\.exists) }, text)
    }

    /// Reports the agent's state with an increasing `seq` (herdr drops an older one).
    func report(_ pane: String, _ state: String, agent: String = "codex", session: String? = nil) async throws {
        try await Self.call(session ?? one, "pane.report_agent", [
            "pane_id": pane, "source": "oriel-e2e", "agent": agent, "state": state,
            "seq": Int(Date.now.timeIntervalSince1970 * 1000),
        ])
    }

    /// The agent works, the app sees it, then it finishes: an unseen finish. Gives back the pane.
    private func finish(_ created: (tab: String, pane: String)) async throws -> String {
        try await report(created.pane, "working")
        try await waitForValue("tab.\(created.tab)", containing: "working")
        try await report(created.pane, "idle")
        return created.pane
    }

    func waitForValue(_ identifier: String, containing text: String) async throws {
        try await expect("\(identifier) to say \(text)") { element(identifier).stringValue.contains(text) }
    }
}
