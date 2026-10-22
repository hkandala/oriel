import XCTest

/// Pane cards and the layout (phase 17): dividers, equal splits, keys, the header's context menu, zoom and the fade.
/// Each test makes its own tab in w2 (closed after) and checks herdr's tree, except the fade test, which only reads
/// session one's t1 (p1 | (p2 / p3)).
extension OrielUITests {
    func testDividersDragDoubleClickAndBalance() async throws {
        let (tab, first) = try await newTab("dividers")
        // herdr halves the pane it splits: 50 / 25 / 25.
        let second = try await split(first), third = try await split(second)
        element("tab.\(tab)").click()
        let divider = element("divider.\(tab).root")
        // The second split's divider: the app has all three panes.
        XCTAssertTrue(element("divider.\(tab).1").exists(within: 3))

        // ⌃⌘= through its menu item: a global hotkey on this Mac takes the key before the app sees it.
        pick("Pane", "Balance Splits")
        try await expectWidths(tab, [first: 1 / 3, second: 1 / 3, third: 1 / 3])
        expectValue(divider, "33%")

        // The row less the page's two edges and the root's gap.
        let total = element("page.\(tab)").frame.width - 3 * 8
        let center = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.hover()
        keepScreenshot("three panes, grip")
        center.click(forDuration: 0.2, thenDragTo: center.withOffset(CGVector(dx: total * 0.15, dy: 0)))
        try await expectRatio(tab, at: [], 1 / 3 + 0.15)

        divider.doubleClick()
        try await expectRatio(tab, at: [], 0.5)
        expectValue(divider, "50%")
    }

    func testSplitRightTwiceGivesThirds() async throws {
        let (tab, pane) = try await newTab("thirds")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("page.\(tab)").has(\.isHittable, true, within: 3))
        for count in [2, 3] {
            hoverHeader(pane)
            element("pane.\(pane).split-right").click()
            try await poll("\(count) panes in herdr") { () async throws -> Bool? in
                try await order(tab).count == count ? true : nil
            }
        }
        // Not herdr's 50 / 25 / 25.
        let panes = try await order(tab)
        try await expectWidths(tab, Dictionary(uniqueKeysWithValues: panes.map { ($0, 1.0 / 3) }))
        // After the motion each terminal fits its card again (it holds its size while cards move).
        for pane in panes {
            try await poll("terminal \(pane) fits its card") { () async throws -> Bool? in
                abs(element("terminal.\(pane)").frame.width - (element("pane.\(pane)").frame.width - 2 * 8)) <= 2
                    ? true : nil
            }
        }
    }

    func testKeysMoveTheKeyboardSwapAndResize() async throws {
        let (tab, first) = try await newTab("keys")
        let second = try await split(first)
        restoreHerdrFocusAfter()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        // Round the ends: after the last card is the first.
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        app.typeKey(.rightArrow, modifierFlags: [.command, .control])
        try await expectRatio(tab, at: [], 0.55)

        // ⌥⇧⌘→ through its menu item: global hotkeys of other apps take ⌥⇧ chords.
        pick("Pane", "Move Pane Right")
        try await poll("the two swapped") { () async throws -> Bool? in
            try await order(tab) == [second, first] ? true : nil
        }
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        // Focus follows mouse: a pointer resting on the other card takes the keyboard there, also once a rename
        // that held it back ends (Esc gives the keyboard back to the first card first).
        pick("Pane", "Focus Follows Mouse")
        addTeardownBlock { @MainActor in self.pick("Pane", "Focus Follows Mouse") }
        paneMenu(first, "Rename Pane…")
        XCTAssertTrue(hasKeyboard(element("pane.\(first).rename")))
        hoverHeader(second)
        // Two checks later the rename still has the keyboard: typing holds the move back.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(hasKeyboard(element("pane.\(first).rename")))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
    }

    func testContextMenuSplitsLeftRenamesAndMovesToNewTab() async throws {
        let (tab, pane) = try await newTab("menu")
        restoreHerdrFocusAfter()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 3))

        paneMenu(pane, "Split Left", screenshot: "context menu")
        try await poll("a new pane left of the first") { () async throws -> Bool? in
            let panes = try await order(tab)
            return panes.count == 2 && panes.last == pane ? true : nil
        }

        paneMenu(pane, "Rename Pane…")
        let field = element("pane.\(pane).rename")
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("renamed\r")
        try await poll("herdr's label") { () async throws -> Bool? in try await label(pane) == "renamed" ? true : nil }
        // An empty name clears it.
        paneMenu(pane, "Rename Pane…")
        XCTAssertTrue(hasKeyboard(field))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("\u{8}\r")
        try await poll("no label") { () async throws -> Bool? in try await label(pane) == nil ? true : nil }

        let before = try await tabIDs()
        paneMenu(pane, "Move to New Tab")
        let moved = try await newTabID(after: before)
        // Gone already after the move to a new workspace below, which takes its only pane.
        addTeardownBlock { [one] in
            let close = try JSONSerialization.data(withJSONObject: [
                "id": "1",
                "method": "tab.close",
                "params": ["tab_id": moved],
            ])
            _ = try? await Self.post(one, close + Data("\n".utf8))
        }
        try await poll("the pane in the new tab") { () async throws -> Bool? in
            try await order(moved) == [pane] ? true : nil
        }
        // The page follows the pane.
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))

        // To a new workspace: a new pane id, the same terminal, and it keeps the keyboard.
        let terminal = try await terminalID(pane)
        let workspaces = try await workspaceIDs()
        XCTAssertFalse(workspaces.isEmpty)
        addTeardownBlock { @MainActor in
            for id in try await self.workspaceIDs() where !workspaces.contains(id) {
                try await Self.call(self.one, "workspace.close", ["workspace_id": id, "close_group": false])
            }
        }
        paneMenu(pane, "Move to New Workspace")
        let away = try await poll("the pane in a new workspace") { () async throws -> String? in
            let panes = try await snapshot()?["panes"] as? [[String: Any]] ?? []
            return panes.first { $0["terminal_id"] as? String == terminal && $0["pane_id"] as? String != pane }?[
                "pane_id",
            ] as? String
        }
        XCTAssertTrue(hasKeyboard(element("terminal.\(away)")))
    }

    func testZoomIsDisabledAloneAndAZoomedCardShowsRestoreAndClose() async throws {
        let (tab, first) = try await newTab("zoom")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        hoverHeader(first)
        XCTAssertTrue(element("pane.\(first).zoom").exists(within: 2))
        XCTAssertFalse(element("pane.\(first).zoom").isEnabled)

        let second = try await split(first)
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        hoverHeader(first)
        XCTAssertTrue(element("pane.\(first).zoom").has(\.isEnabled, true, within: 2))
        element("pane.\(first).zoom").click()
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 2))
        XCTAssertEqual(element("pane.\(first).zoom").label, "Restore Pane ⇧⌘↩")
        XCTAssertTrue(element("pane.\(first).close").exists)
        XCTAssertFalse(element("pane.\(first).split-right").exists)
        XCTAssertFalse(element("pane.\(first).split-down").exists)
        keepScreenshot("zoomed card")

        // Its neighbor gone, the card is alone: the zoom ends.
        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(element("pane.\(first).split-right").exists(within: 3))
        XCTAssertEqual(element("pane.\(first).zoom").label, "Zoom Pane ⇧⌘↩")
        XCTAssertFalse(element("pane.\(first).zoom").isEnabled)
    }

    func testCardsWithoutTheKeyboardFade() throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("terminal.w1:p1").click()
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))
        let keyboard = element("pane.w1:p1"), other = element("pane.w1:p2")
        expectValue(keyboard, "content 100%")
        expectValue(other, "content 70%")
        keepScreenshot("faded cards, key window")

        // The setting turns the fade off; back on after a failure too (the app's defaults are the user's).
        addTeardownBlock { @MainActor in
            // Both cards unfaded: the setting is off.
            if [keyboard, other].allSatisfy({ $0.value as? String == "content 100%" }) {
                self.app.menuBars.menuBarItems["View"].click()
                self.app.menuBars.menuItems["Fade Inactive Panes"].click()
            }
        }
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Fade Inactive Panes"].click()
        expectValue(other, "content 100%")
        keepScreenshot("unfaded cards")
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Fade Inactive Panes"].click()
        expectValue(other, "content 70%")

        // A window that is not key: 0.5 for the others, 0.8 (0.85 in light) for the keyboard card.
        let (first, _) = try newWindow()
        let card = element("pane.w1:p1", in: first)
        expectValue(element("pane.w1:p2", in: first), "content 50%")
        expectValue(card, "content 80%", "content 85%")
        let shot = XCTAttachment(screenshot: first.screenshot())
        shot.name = "faded cards, window not key"
        shot.lifetime = .keepAlways
        add(shot)
        app.typeKey("w", modifierFlags: [.command, .shift])
        // Key again, the keyboard is still on the card it was on (phase 12 saw it move once after a re-activation).
        expectValue(card, "content 100%")
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))
    }
}

/// Helpers for the pane tests: herdr's tree of a tab, from `layout.export`.
extension OrielUITests {
    /// Right-clicks the card's header and picks the item of its context menu.
    func paneMenu(_ pane: String, _ item: String, screenshot: String? = nil) {
        element("pane.\(pane)").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: 18))
            .rightClick()
        // In the window, not the menu bar's View ▸ Pane, which has the same titles.
        let entry = app.windows.firstMatch.menuItems[item]
        XCTAssertTrue(entry.exists(within: 2))
        if let screenshot {
            keepScreenshot(screenshot)
        }
        entry.click()
    }

    /// `pane.swap` moves herdr's focus to the swapped pane (herdr 0.9.5 ignores `focus:false` there), and the app
    /// opens on herdr's focused workspace and tab. After the test, a swap of w1:p1 with w1:p2 and back puts the
    /// focus on w1:t1 and w1:p1 again, where the other tests expect it, without a focus call.
    func restoreHerdrFocusAfter() {
        addTeardownBlock { [one] in
            for _ in 0 ..< 2 {
                try await Self.call(one, "pane.swap", ["source_pane_id": "w1:p1", "target_pane_id": "w1:p2"])
            }
        }
    }

    func root(_ tab: String) async throws -> [String: Any] {
        let layout = try await Self.call(one, "layout.export", ["tab_id": tab])["layout"] as? [String: Any]
        return try XCTUnwrap(layout?["root"] as? [String: Any])
    }

    /// The tab's panes, first to last.
    func order(_ tab: String) async throws -> [String] {
        func leaves(_ node: [String: Any]) -> [String] {
            if let id = node["pane_id"] as? String {
                return [id]
            }
            return ["first", "second"].flatMap { leaves(node[$0] as? [String: Any] ?? [:]) }
        }
        return try await leaves(root(tab))
    }

    /// Each pane's share of the tab's width, within 0.02.
    func expectWidths(_ tab: String, _ widths: [String: Double]) async throws {
        func shares(_ node: [String: Any], _ share: Double) -> [String: Double] {
            if let id = node["pane_id"] as? String {
                return [id: share]
            }
            let ratio = node["ratio"] as? Double ?? 0, right = node["direction"] as? String == "right"
            let first = shares(node["first"] as? [String: Any] ?? [:], right ? share * ratio : share)
            return first.merging(shares(node["second"] as? [String: Any] ?? [:], right ? share * (1 - ratio) : share)) {
                $1
            }
        }
        try await poll("widths \(widths)") { () async throws -> Bool? in
            let found = try await shares(root(tab), 1)
            return found.count == widths.count && widths.allSatisfy { abs((found[$0.key] ?? -1) - $0.value) <= 0.02 }
                ? true : nil
        }
    }

    /// The ratio of the split at `path` (`false` = first child), within 0.02.
    func expectRatio(_ tab: String, at path: [Bool], _ ratio: Double) async throws {
        try await poll("ratio \(ratio)") { () async throws -> Bool? in
            var node = try await root(tab)
            for step in path {
                node = node[step ? "second" : "first"] as? [String: Any] ?? [:]
            }
            return abs((node["ratio"] as? Double ?? -1) - ratio) <= 0.02 ? true : nil
        }
    }

    /// Waits up to 3 s for the element's accessibility value to be one of these.
    func expectValue(_ element: XCUIElement, _ values: String...) {
        XCTAssertTrue(until(3) { values.contains(element.stringValue) },
                      "\(element.identifier) has \(element.value ?? "no value"), not \(values)")
    }

    func label(_ pane: String) async throws -> String? {
        try await (Self.call(one, "pane.get", ["pane_id": pane])["pane"] as? [String: Any])?["label"] as? String
    }
}
