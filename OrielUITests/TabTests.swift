import XCTest

/// Tab switches, closes and drags the user asked for.
extension OrielUITests {
    /// A click, +, ⌘T, ⌘1…⌘9, ⇧⌘], the palette and a close show the tab's page, and only it; a sideways swipe over a
    /// card leaves the tab as it is.
    func testSwitchingTabsShowsOnlyTheirPage() async throws {
        let first = element("tab.w1:t1"), second = element("tab.w1:t2")
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let pages = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'page.'"))
        let shows = { (tab: String) in
            until(2) { pages.allElementsBoundByIndex.map(\.identifier) == ["page.\(tab)"] }
        }

        second.click()
        XCTAssertTrue(shows("w1:t2"))
        first.click()
        XCTAssertTrue(shows("w1:t1"))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(shows("w1:t2"))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(shows("w1:t1"))
        openPalette()
        element("palette.tab.w1:t2").click()
        XCTAssertTrue(shows("w1:t2"))
        XCTAssertTrue(second.isSelected)

        // A new tab from +, closed from the menu: back to the tab used before it.
        element("titlebar.new-tab").click()
        let plus = try await newTabID(after: before)
        XCTAssertTrue(shows(plus))
        try await settle([plus])
        // Only its shell runs: no dialog.
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("tab.\(plus)").vanishes(within: 3))
        XCTAssertTrue(shows("w1:t2"))
        // One from ⌘T, closed by herdr.
        app.typeKey("t", modifierFlags: .command)
        let made = try await newTabID(after: before)
        XCTAssertTrue(shows(made))
        try await Self.call(one, "tab.close", ["tab_id": made])
        XCTAssertTrue(shows("w1:t2"))

        // A trackpad's sideways swipe over a card, both ways, goes to the card: no tab changes.
        let card = element("terminal.w1:p4").frame
        for step in [30, -30] {
            try await Self.post("\(one)/swipe", Data("\(card.midX) \(card.midY) \(step) 14".utf8))
            XCTAssertFalse(until(1) { !second.isSelected }, "a swipe of \(step) changed the tab")
        }
        XCTAssertTrue(shows("w1:t2"))
    }

    /// A sideways scroll over a browser page wider than its card scrolls the page and changes no tab: a trackpad's
    /// two-finger swipe and a wheel turned sideways (XCUITest's scroll).
    func testSidewaysScrollsReachAWidePage() async throws {
        let (tab, pane) = try await newTab("wide")
        element("tab.\(tab)").click()
        try await waitForPrompt(pane)
        // The title tells the page's sideways scroll.
        let file = "/tmp/oriel-e2e-wide.html"
        try await send("printf '<title>x 0</title><body style=\"margin:0\"><div style=\"width:6000px;"
            + "height:200px;background:linear-gradient(90deg,red,blue)\"></div><script>onscroll = () => "
            + "document.title = \\x27x \\x27 + scrollX</script>' >\(file) && clear\r", to: pane)
        try await waitFor(pane) { !$0.contains("printf") }
        let iid = String(format: "e2e%03x", Int.random(in: 0 ..< 4096)), title = element("pane.\(pane).title")
        try await Self.call(one, "pane.rename", ["pane_id": pane, "label": "oriel:browser#\(iid) file://\(file)"])
        XCTAssertTrue(title.has(\.stringValue, "x 0", within: connect))
        let page = element("browser.\(pane)"), capsule = element("tab.\(tab)")
        XCTAssertTrue(page.has(\.isHittable, true, within: 5))
        // Fingers right to left move the page to the right, or the other way if natural scrolling is off.
        let swipe = "\(page.frame.midX) \(page.frame.midY)"
        for step in [-30, 30] where title.stringValue == "x 0" {
            try await Self.post("\(one)/swipe", Data("\(swipe) \(step) 14".utf8))
            _ = until(2) { title.stringValue != "x 0" }
        }
        let swiped = title.stringValue
        XCTAssertNotEqual(swiped, "x 0", "a swipe did not scroll the page")
        // One wheel: the swipe left the page between its edges, so either way moves it. A wheel back would undo it.
        page.scroll(byDeltaX: -200, deltaY: 0)
        XCTAssertTrue(until(2) { title.stringValue != swiped }, "a sideways wheel left the page at \(swiped)")
        XCTAssertTrue(capsule.isSelected)
    }

    /// A closed selected tab gives way to the tab used before it, else to the one on its left.
    func testClosingTheSelectedTabGoesToTheOneUsedBefore() async throws {
        let tabs = try await newWorkspace("used", tabs: 5).tabs
        let capsules = tabs.map { element("tab.\($0)") }
        XCTAssertTrue(capsules[0].has(\.isSelected, true, within: 2))
        // ⌘ keys: only 3 tabs fit on CI's window.
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(capsules[4].has(\.isSelected, true, within: 2))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(capsules[2].has(\.isSelected, true, within: 2))

        // Not the left one (1) or the first (0).
        try await Self.call(one, "tab.close", ["tab_id": tabs[2]])
        XCTAssertTrue(capsules[4].has(\.isSelected, true, within: 3))
        // Every tab used before is gone: the left one (3), not the first (1).
        try await Self.call(one, "tab.close", ["tab_id": tabs[0]])
        XCTAssertTrue(capsules[0].vanishes(within: 3))
        try await Self.call(one, "tab.close", ["tab_id": tabs[4]])
        XCTAssertTrue(capsules[3].has(\.isSelected, true, within: 3))
    }

    /// Quick ⌘T three times, then quick ⌘W: each closes the shown tab and goes to the one used before it, one step
    /// back each time, while the new tabs are still stand-ins or their shells start. The old code lost a
    /// stand-in from the history once herdr's tab took its place, and waited for a starting shell, so it jumped back
    /// to the first tab.
    func testQuickNewTabsThenClosesStepBackOneTabEach() async throws {
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let first = element("tab.w1:t1")
        XCTAssertTrue(first.has(\.isSelected, true, within: connect))
        for _ in 0 ..< 3 {
            app.typeKey("t", modifierFlags: .command)
        }
        // w1's capsules, left to right: t1, t2 and the three new ones; the selected one's place.
        let selected = { () -> Int? in
            let capsules = self.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'"))
                .allElementsBoundByIndex.filter { capsule in
                    ![".close", ".keycap", ".state", ".rename"].contains { capsule.identifier.hasSuffix($0) }
                }.sorted { $0.frame.minX < $1.frame.minX }
            return capsules.firstIndex { $0.isSelected }
        }
        XCTAssertTrue(until(3) { selected() == 4 })
        for place in [3, 2, 0] {
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(until(2) { selected() == place }, "after ⌘W: \(String(describing: selected()))")
        }
        // herdr closed the three, and only them; no dialog.
        try await expect("herdr's tabs as before") { try await tabIDs().sorted() == before.sorted() }
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    /// Close Tabs to the Right, from a capsule's menu and from the palette, keeps the tabs on the left; it asks once
    /// while a program runs in them, else not at all.
    func testCloseTabsToTheRightKeepsTheTabsOnTheLeft() async throws {
        let tabs = try await newWorkspace("right", tabs: 4).tabs
        let workspace = workspace(of: tabs[0])
        let order: () async throws -> [String] = { try await self.tabIDs().filter { $0.hasPrefix("\(workspace):") } }
        try await settle(tabs)
        try await runSleep(pane(of: tabs[3]))
        let confirm = app.sheets.buttons["Close Tabs"]
        element("tab.\(tabs[1])").rightClick()
        // The capsule's menu, not the File menu's item.
        app.windows.firstMatch.menuItems["Close Tabs to the Right"].click()
        XCTAssertTrue(sheetText("Close the 2 tabs to the right?").exists(within: 2))
        XCTAssertTrue(sheetText("sleep is running in them. Their 2 panes and everything running in them will end, "
                + "here and in every herdr client. This cannot be undone.").exists)
        confirm.click()
        try await expect("the two tabs on the left") { try await order() == [tabs[0], tabs[1]] }
        XCTAssertTrue(element("tab.\(tabs[2])").vanishes(within: 2))

        // The selected tab's (the first); only a shell runs to its right.
        openPalette()
        app.typeText("close tabs to the right")
        app.typeKey(.return, modifierFlags: [])
        try await expect("the first tab alone") { try await order() == [tabs[0]] }
        XCTAssertFalse(confirm.exists)
    }

    /// A tab dragged to the end of an overflowing row and held there scrolls the row (the scroll view's own drop
    /// scroll), so it goes past the tabs that were in view.
    func testHoldingADraggedTabAtTheRowsEndScrollsTheRow() async throws {
        let tabs = try await newWorkspace("far", tabs: 8).tabs
        let first = element("tab.\(tabs[0])"), last = element("tab.\(tabs[7])")
        let rowEnd = element("titlebar.agents").frame.minX - 8
        XCTAssertTrue(last.exists(within: 3))
        XCTAssertGreaterThan(last.frame.minX, rowEnd)
        let from = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // 5 pt inside the row's end. Without a scroll it lands third.
        during(from, to: from.withOffset(CGVector(dx: rowEnd - 5 - first.frame.midX, dy: 0)), hold: 6)
        try await expect("the first tab past the third") {
            try await tabIDs().filter { $0.hasPrefix("\(workspace(of: tabs[0])):") }.firstIndex(of: tabs[0]) ?? 0 > 3
        }
    }

    /// A workspace of 5 tabs on its 4th and one of 1, clicked back and forth, then a session shown and left: each
    /// shows its selected tab.
    func testEachWorkspaceShowsItsTabClickedBackAndForth() async throws {
        var shown: [(workspace: String, tab: String)] = []
        for (index, count) in [5, 1].enumerated() {
            let tabs = try await newWorkspace("order\(index)", tabs: count).tabs
            shown.append((workspace(of: tabs[0]), tabs[count == 5 ? 3 : 0]))
        }
        element("workspace.\(shown[0].workspace)").click()
        app.typeKey("4", modifierFlags: .command)
        try await expectShown(shown[0].tab, "the 4th tab")
        for (workspace, tab) in shown.dropFirst() + shown.reversed().dropFirst() {
            element("workspace.\(workspace)").click()
            try await expectShown(tab, "then \(workspace)")
        }
        openSessionPanel()
        element("open-session.session.\(two)").click()
        XCTAssertTrue(element("pane.w1:p1").has(\.isHittable, true, within: connect), "the other session")
        element("sidebar.dot.\(one)").click()
        try await expectShown(shown[0].tab, "back from the other session")
    }

    /// The tab's page is in view: its card takes clicks and its capsule alone is lit.
    private func expectShown(_ tab: String, _ step: String) async throws {
        let pane = try await pane(of: tab)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.' AND selected == true"))
        var lit: [String] = []
        let shown = until(3) {
            lit = selected.allElementsBoundByIndex.map(\.identifier)
            return element("pane.\(pane)").exists && element("pane.\(pane)").isHittable && lit == ["tab.\(tab)"]
        }
        keepScreenshot(step)
        XCTAssertTrue(shown, "\(step): \(tab)'s page is not in view, lit: \(lit)")
    }

    /// The dialog's text, in its label or its value.
    func sheetText(_ text: String) -> XCUIElement {
        app.sheets.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", text, text)).firstMatch
    }

    /// A row of one tab that grows to two while shown: each capsule's accessibility frame is its own, not the row's.
    func testCapsulesKeepTheirFramesWhenARowOfOneGrows() async throws {
        let row = element("workspace.w2")
        XCTAssertTrue(row.exists(within: connect))
        row.click()
        let first = element("tab.w2:t1")
        XCTAssertTrue(first.has(\.isHittable, true, within: 3))
        let (tab, _) = try await createTab(in: "w2", label: "grown")
        closeAfter("tab", tab)
        let second = element("tab.\(tab)")
        XCTAssertTrue(second.has(\.isHittable, true, within: 3))
        XCTAssertTrue(until(2) { first.frame.width == second.frame.width }, "\(first.frame) \(second.frame)")
        XCTAssertEqual(first.frame.maxX + 1, second.frame.minX, "\(first.frame) \(second.frame)")
    }

    /// A tab's "claude needs you" stays on its session's tab: session two's w1:t1 has the same id, and its capsule
    /// showed the other session's announcement.
    func testAnnouncementStaysInItsSession() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let created = try await Self.call(two, "tab.create", ["workspace_id": "w1", "label": "delta", "cwd": "/tmp",
                                                              "focus": false])
        let tab = try id(created, "tab")
        addTeardownBlock { [two] in _ = try? await Self.call(two, "tab.close", ["tab_id": tab]) }
        // The agent in a pane of its own, closed after: a released agent on w1:p1 still counted as needing you.
        let agent = try await split("w1:p1", "down")
        closeAfter("pane", agent)
        // Session two on its new tab, session one on t2: both w1:t1 capsules show, unselected.
        openPage(two)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        element("sidebar.dot.\(one)").click()
        element("tab.w1:t2").click()
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))

        try await report(agent, "blocked", agent: "claude")
        let capsule = element("tab.w1:t1")
        XCTAssertTrue(until(3) { capsule.label.contains("claude needs you") }, capsule.label)
        // Within its 3 s.
        element("sidebar.dot.\(two)").click()
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, two, within: 2))
        XCTAssertFalse(capsule.label.contains("needs you"), capsule.label)
    }
}
