import XCTest

/// Tab switches, closes and drags from the user's second round (phase 24, items 14, 16, 17, 18).
extension OrielUITests {
    /// A click, +, ⌘T, ⌘1…⌘9, ⇧⌘], the palette and a close show the tab's page at once; only a swipe slides.
    func testSwitchingTabsShowsTheirPageAtOnce() async throws {
        relaunch(one, ["-recordStrip", "YES"])
        let first = element("tab.w1:t1"), second = element("tab.w1:t2"), between = element("strip.between")
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        // Once the launch's layout has settled.
        var launched = ""
        XCTAssertTrue(until(5) {
            launched = between.stringValue
            Thread.sleep(forTimeInterval: 1)
            return between.stringValue == launched
        })
        let before = try await tabIDs()
        closeNew("tab", besides: before)

        second.click()
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        first.click()
        XCTAssertTrue(first.has(\.isSelected, true, within: 2))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(first.has(\.isSelected, true, within: 2))
        openPalette()
        element("palette.tab.w1:t2").click()
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))

        // A new tab from +, closed from the menu: back to the tab used before it.
        element("titlebar.new-tab").click()
        let plus = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(plus)").has(\.isSelected, true, within: 3))
        try await settle([plus])
        // Only its shell runs: no dialog.
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("tab.\(plus)").vanishes(within: 3))
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        // One from ⌘T, closed by herdr.
        app.typeKey("t", modifierFlags: .command)
        let made = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(made)").has(\.isSelected, true, within: 3))
        try await Self.call(one, "tab.close", ["tab_id": made])
        XCTAssertTrue(second.has(\.isSelected, true, within: 3))
        XCTAssertFalse(until(0.5) { between.stringValue != launched }, "the strip slid \(between.stringValue) times")

        // A swipe does slide: the count sees slides.
        try await swipe(element("terminal.w1:p4"), until: first, \.isSelected, true)
        XCTAssertNotEqual(between.stringValue, launched)
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

    /// The user's four workspaces (5 tabs, 1, 1, 3), clicked top to bottom and back from a middle tab of the first,
    /// while herdr's snapshots keep coming (the user's agents worked; here a tab is renamed again and again): every
    /// workspace shows its cards (phase 25, item 25: a one-tab one came up empty going down from the 4th tab), and so
    /// does a session shown and left in between.
    func testStripShowsEachWorkspaceClickedDownAndUp() async throws {
        var shown: [(workspace: String, tab: String)] = []
        for (index, count) in [5, 1, 1, 3].enumerated() {
            let tabs = try await newWorkspace("order\(index)", tabs: count).tabs
            shown.append((workspace(of: tabs[0]), tabs[0]))
        }
        let first = try await tabIDs().filter { workspace(of: $0) == shown[0].workspace }
        // Off the main actor, which the waits below block.
        let busy = Task.detached { [one, renamed = first[0]] in
            for count in 0... where !Task.isCancelled {
                _ = try? await Self.call(one, "tab.rename", ["tab_id": renamed, "label": "busy \(count)"])
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        defer { busy.cancel() }
        for middle in [1, 2, 3, 3, 3] {
            element("workspace.\(shown[0].workspace)").click()
            app.typeKey("\(middle + 1)", modifierFlags: .command)
            shown[0].tab = first[middle]
            try await expectShown(first[middle], "tab \(middle + 1)")
            for (workspace, tab) in shown.dropFirst() + shown.reversed().dropFirst() {
                element("workspace.\(workspace)").click()
                try await expectShown(tab, "tab \(middle + 1), then \(workspace)")
            }
        }
        openSessionPanel()
        element("open-session.session.\(two)").click()
        XCTAssertTrue(element("pane.w1:p1").has(\.isHittable, true, within: connect), "the other session")
        element("sidebar.dot.\(one)").click()
        try await expectShown(shown[0].tab, "back from the other session")
    }

    /// The tab's page is in view: its card takes clicks and its capsule is lit.
    private func expectShown(_ tab: String, _ step: String) async throws {
        let pane = try await pane(of: tab)
        let shown = until(3) {
            element("pane.\(pane)").exists && element("pane.\(pane)").isHittable
                && element("tab.\(tab)").stringValue.hasPrefix("in view")
        }
        keepScreenshot(step)
        XCTAssertTrue(shown, "\(step): \(tab)'s page is not in view")
    }

    /// The dialog's text, in its label or its value.
    private func sheetText(_ text: String) -> XCUIElement {
        app.sheets.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", text, text)).firstMatch
    }
}
