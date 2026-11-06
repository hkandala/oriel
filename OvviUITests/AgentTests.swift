import XCTest

/// Agents: states in tabs and workspace rows, the Agents button, its popover and the Agents view. Every
/// status comes from `pane.report_agent` on a throwaway tab, closed after the test (its agent goes with it).
extension OvviUITests {
    func testWorkingAgentShowsInItsTabAndWorkspace() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let (tab, pane) = try await newTab("build", in: "w1")
        try await report(pane, "working")
        let icon = element("tab.\(tab).state")
        XCTAssertTrue(icon.exists(within: 3))
        XCTAssertEqual(icon.stringValue, "Working")
        try await waitForValue("tab.\(tab)", containing: "codex, working")
        try await waitForValue("workspace.w1", containing: "working")
        keepScreenshot("working icon")
        // The state's icon (12 pt; its frame is the drawn circle's, 11 pt) at the end of the name's line, 8 pt in; no
        // word, no time. The page header's text on the names' edge, 8 pt into the row.
        let state = element("workspace.w1.state")
        XCTAssertTrue(state.exists(within: 2))
        XCTAssertEqual(state.stringValue, "Working")
        let row = element("workspace.w1").frame
        XCTAssertEqual(state.frame.width, 11, accuracy: 0.5, "\(state.frame)")
        XCTAssertEqual(state.frame.midX, row.maxX - 8 - 6, accuracy: 0.5, "\(state.frame) \(row)")
        XCTAssertEqual(state.frame.midY, row.minY + 15, accuracy: 0.5, "\(state.frame) \(row)")
        XCTAssertEqual(element("sidebar.header").frame.minX, row.minX + 8, accuracy: 0.5)

        // The selected tab shows it too; the × takes its place, centered on it, while hovered.
        let slot = icon.frame
        element("tab.\(tab)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(icon.vanishes(within: 2))
        XCTAssertEqual(element("tab.\(tab).close").frame.midX, slot.midX, accuracy: 0.5)
        element("workspace.w1").hover()
        XCTAssertTrue(icon.exists(within: 2))
        keepScreenshot("working icon, selected tab")
        // Another agent of the tab needs you: one icon, by priority.
        let other = try await split(pane)
        try await report(other, "blocked", agent: "claude")
        XCTAssertTrue(icon.has(\.stringValue, "Needs you", within: 3))
        try await report(other, "working", agent: "claude")
        XCTAssertTrue(icon.has(\.stringValue, "Working", within: 3))
        // A finish under the user's eyes (the keyboard card's) stays Done until they leave it.
        try await report(pane, "idle")
        XCTAssertTrue(icon.has(\.stringValue, "Done", within: 3))
        // Leaving it for another card of the same tab is leaving.
        element("terminal.\(other)").click()
        XCTAssertTrue(icon.has(\.stringValue, "Working", within: 3))
    }

    func testBlockedAgentNeedsYouAndThePopoverGoesToIt() async throws {
        let button = element("titlebar.agents")
        XCTAssertTrue(button.exists(within: connect))
        // Nobody needs you: no panel.
        button.hover()
        XCTAssertFalse(element("agents.popover").exists(within: 1))
        element("workspace.w1").hover()

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
        // Answered while it shows: the panel goes, and does not come back under the still pointer.
        try await report(pane, "working", agent: "claude")
        XCTAssertTrue(element("agents.popover").vanishes(within: 2))
        try await report(pane, "blocked", agent: "claude")
        try await waitForValue("titlebar.agents", containing: "1 need you")
        XCTAssertFalse(element("agents.popover").exists(within: 1))
        element("workspace.w1").hover()
        button.hover()
        XCTAssertTrue(row.exists(within: 2))
        row.click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        XCTAssertTrue(element("agents.popover").vanishes(within: 2))
        XCTAssertEqual(element("sidebar.header").value as? String, one)
    }

    /// The panel also lists unseen finishes, under the Agents view's labels, after needs you.
    func testTheAgentsPanelListsDoneAgentsAfterNeedsYou() async throws {
        let button = element("titlebar.agents"), panel = element("agents.popover")
        XCTAssertTrue(button.exists(within: connect))
        let docs = try await newTab("docs")
        let done = try await finish(docs)
        try await waitForValue("tab.\(docs.tab)", containing: "codex, finished")
        // Done alone opens the panel; the badge counts only needs you.
        XCTAssertEqual(button.value as? String, "0 need you")
        button.hover()
        let row = { (pane: String) in panel.descendants(matching: .any)["agent.\(pane)"] }
        let group = { (name: String) in panel.descendants(matching: .any)["agents.popover.group.\(name)"] }
        XCTAssertTrue(row(done).exists(within: 2))
        XCTAssertEqual(group("Done").stringValue, "Done · 1")
        XCTAssertFalse(group("Needs you").exists)
        element("workspace.w1").hover()
        XCTAssertTrue(panel.vanishes(within: 2))

        let blocked = try await newTab("deploy").pane
        try await report(blocked, "blocked", agent: "claude")
        try await waitForValue("titlebar.agents", containing: "1 need you")
        button.hover()
        XCTAssertTrue(row(blocked).exists(within: 2))
        XCTAssertEqual(group("Needs you").stringValue, "Needs you · 1")
        let tops = [group("Needs you"), row(blocked), group("Done"), row(done)].map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted())
        XCTAssertEqual(element("agents.popover.header").stringValue, "Agents · \(one)")
        keepScreenshot("agents panel, needs you and done")

        // A click shows the done agent's tab; leaving it clears it.
        row(done).click()
        XCTAssertTrue(element("tab.\(docs.tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(panel.vanishes(within: 2))
        XCTAssertTrue(element("tab.\(docs.tab)").stringValue.contains("finished"))
        app.typeKey("1", modifierFlags: .command)
        try await expect("the finish seen") { !element("tab.\(docs.tab)").stringValue.contains("finished") }
        element("workspace.w1").hover()
        button.hover()
        XCTAssertTrue(row(blocked).exists(within: 2))
        XCTAssertFalse(group("Done").exists)
        XCTAssertFalse(row(done).exists)
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

    func testAFinishShowsDoneUntilTheUserLeavesIt() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let other = try await newTab("review").pane
        try await report(other, "idle", agent: "pi")
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
        XCTAssertTrue(element("titlebar.agents").has(\.isSelected, true, within: 2))
        let row = element("agent.\(pane)")
        try await waitForValue("agent.\(pane)", containing: "Done")
        // Opened, it stays Done while the user looks at it, also with the app in the background.
        row.click()
        XCTAssertTrue(element("tab.\(created.tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        XCTAssertFalse(until(1) { row.value as? String != "Done" })
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        XCTAssertFalse(until(1) { row.value as? String != "Done" })
        app.activate()
        // Another agent opened: it is idle, and its row stays where it is (the finish was its last change).
        let place = row.frame
        element("agent.\(other)").click()
        try await waitForValue("agent.\(pane)", containing: "Idle")
        // Off the list, past the 1 s hold and the 0.2 s slide: a move would show.
        element("sidebar.header").hover()
        XCTAssertFalse(until(2.5) { row.frame != place }, "\(row.frame) \(place)")
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
        keepScreenshot("idle, no state")
    }

    /// Types in the footer filter, checks which rows stay, then clears it with Esc.
    func filter(_ text: String, keeps rows: [XCUIElement], _ kept: [Bool]) {
        element("sidebar.filter").click()
        element("sidebar.filter").typeText(text)
        XCTAssertTrue(until(2) { rows.map(\.exists) == kept }, text)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(until(2) { rows.allSatisfy(\.exists) }, text)
    }

    /// Reports the agent's state with an increasing `seq` (herdr drops an older one).
    func report(_ pane: String, _ state: String, agent: String = "codex", session: String? = nil) async throws {
        try await Self.call(session ?? one, "pane.report_agent", [
            "pane_id": pane, "source": "ovvi-e2e", "agent": agent, "state": state,
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
