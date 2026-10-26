import XCTest

/// Pane cards and the layout (phase 17): dividers, equal splits, keys, the header's context menu and zoom. Each test
/// makes its own tab in w2 (closed after) and checks herdr's tree.
extension OrielUITests {
    func testDividersDragDoubleClickAndBalance() async throws {
        let (tab, first) = try await newTab("dividers")
        // herdr halves the pane it splits: 50 / 25 / 25.
        let second = try await split(first), third = try await split(second)
        element("tab.\(tab)").click()
        let divider = element("divider.\(tab).root")
        // The second split's divider: the app has all three panes.
        XCTAssertTrue(element("divider.\(tab).1").exists(within: 3))

        // ⌥⌘= through its menu item: a global hotkey on this Mac takes the key before the app sees it.
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
            try await expect("\(count) panes in herdr") { try await order(tab).count == count }
        }
        // Not herdr's 50 / 25 / 25.
        let panes = try await order(tab)
        try await expectWidths(tab, Dictionary(uniqueKeysWithValues: panes.map { ($0, 1.0 / 3) }))
        // After the motion each terminal fits its card again, 10 pt in from each side (it holds its size while cards
        // move).
        for pane in panes {
            try await expect("terminal \(pane) fits its card") {
                abs(element("terminal.\(pane)").frame.width - (element("pane.\(pane)").frame.width - 2 * 10)) <= 2
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

        // Resize Pane has no key (phase 25): ⌃⌘→ resizes nothing.
        app.typeKey(.rightArrow, modifierFlags: [.command, .control])
        pick("Pane", "Resize Pane Right")
        try await expectRatio(tab, at: [], 0.55)

        // ⌥⇧⌘→ through its menu item: global hotkeys of other apps take ⌥⇧ chords.
        pick("Pane", "Move Pane Right")
        try await expect("the two swapped") { try await order(tab) == [second, first] }
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        // Focus follows mouse: a pointer resting on the other card takes the keyboard there, also once a rename
        // that held it back ends (Esc gives the keyboard back to the first card first).
        pick("Pane", "Focus Follows Mouse")
        addTeardownBlock { @MainActor in self.pick("Pane", "Focus Follows Mouse") }
        paneMenu(first, "Rename Pane…")
        XCTAssertTrue(hasKeyboard(element("pane.\(first).rename")))
        hoverHeader(second)
        // For a second the rename keeps the keyboard: typing holds the move back.
        let rename = element("pane.\(first).rename")
        XCTAssertFalse(until(1) { !NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: rename) })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
    }

    /// Closing the keyboard card gives the keyboard to the card used before it in the tab, most recent first, not to
    /// herdr's focused pane or the neighbor (phase 27).
    func testClosingAPaneGivesTheKeyboardToThePaneUsedBefore() async throws {
        let (tab, first) = try await newTab("used-panes")
        let second = try await split(first), third = try await split(second), fourth = try await split(third)
        element("tab.\(tab)").click()
        try await settle([tab])
        // The second, the fourth, then the first (herdr's focused pane: splits pass focus:false). Closed, the old code
        // gave the first's neighbor, the second, which herdr focuses.
        for pane in [second, fourth, first] {
            element("terminal.\(pane)").click()
            XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")), pane)
        }
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(first)").vanishes(within: 3))
        XCTAssertTrue(hasKeyboard(element("terminal.\(fourth)")))
        // Two back: the second, not the fourth's neighbor, the third.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(fourth)").vanishes(within: 3))
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
    }

    /// A split's new pane gets the keyboard (⌘D and the header's button); ⌘[ ⌘] step in the tree's order, not the
    /// order the panes were made; ⇧⌘↩ zooms the keyboard card (phase 25: the menu bar kept Zoom Pane disabled from
    /// before the split, so the key did nothing).
    func testSplitsGiveTheNewPaneTheKeyboardAndKeysFollowTheTree() async throws {
        let (tab, first) = try await newTab("split-keys")
        element("tab.\(tab)").click()
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))
        app.typeKey("d", modifierFlags: .command)
        let second = try await poll("a pane right of the first") { try await order(tab).last { $0 != first } }
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        // Below the first: the tree's order is first, third, second.
        hoverHeader(first)
        element("pane.\(first).split-down").click()
        let third = try await poll("a pane below the first") { () async throws -> String? in
            let panes = try await order(tab)
            return panes.count == 3 ? panes[1] : nil
        }
        let tree = try await order(tab)
        XCTAssertEqual(tree, [first, third, second])
        XCTAssertTrue(hasKeyboard(element("terminal.\(third)")))
        for (key, pane) in [("]", second), ("]", first), ("[", second), ("[", third)] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")), "⌘\(key) to \(pane)")
        }

        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(first)").vanishes(within: 2))
        XCTAssertEqual(element("pane.\(third).zoom").label, "Restore Pane ⇧⌘↩")
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(first)").exists(within: 2))
    }

    /// ⌘D pressed fast three times splits the newest card each time, as Ghostty does, and the last one made keeps the
    /// keyboard; ⌘W then steps back through them (phase 29: each split the old card, and the keyboard went to the pane
    /// whose terminal settled last). Each new card comes once: herdr's pane takes its stand-in's card (phase 30).
    func testQuickSplitsSplitTheNewestAndItKeepsTheKeyboard() async throws {
        relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (tab, first) = try await newTab("quick-splits")
        element("tab.\(tab)").click()
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))
        let cards = element("cards.\(tab)")
        XCTAssertTrue(cards.exists(within: 2))
        let before = cards.stringValue.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(before.count, 2, cards.stringValue)
        func counts(came: Int, went: Int) -> String {
            "\(before[0] + came) \(before[1] + went)"
        }
        // Back to back: the second and third ⌘D come while herdr makes the first's pane (a split is 4 herdr runs).
        for _ in 0 ..< 3 {
            app.typeKey("d", modifierFlags: .command)
        }
        let panes = try await poll("four panes") { () async throws -> [String]? in
            let panes = try await order(tab)
            return panes.count == 4 ? panes : nil
        }
        // The newest is the rightmost (the old code split the first card each time: the newest came right of it).
        XCTAssertEqual(panes.first, first)
        XCTAssertTrue(hasKeyboard(element("terminal.\(panes[3])")))
        // herdr's cards shown: three came, none went.
        XCTAssertTrue(cards.has(\.stringValue, counts(came: 3, went: 0), within: 2), "came went: \(cards.stringValue)")
        try await typeAndRead(panes[3])
        for (closed, next) in [(panes[3], panes[2]), (panes[2], panes[1])] {
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(element("pane.\(closed)").vanishes(within: 3))
            XCTAssertTrue(hasKeyboard(element("terminal.\(next)")), "after closing \(closed)")
        }
        XCTAssertTrue(cards.has(\.stringValue, counts(came: 3, went: 2), within: 2), "came went: \(cards.stringValue)")
    }

    /// ⌥⌘ arrows pick from the layout, at once, as Ghostty does (phase 29, the user's layout): three columns, the third
    /// in four rows. Of the cards along the edge, the one used last, else the one sharing most of it, the top one on a
    /// tie (herdr's `pane.neighbor` gave the second row).
    func testSelectPaneKeysPickTheLastUsedElseTheTopNeighbor() async throws {
        let (tab, first) = try await newTab("arrows")
        let second = try await split(first)
        var rows = try await [split(second)]
        for _ in 0 ..< 3 {
            try await rows.append(split(rows[rows.count - 1], "down"))
        }
        element("tab.\(tab)").click()
        pick("Pane", "Balance Splits")
        try await expectWidths(tab, Dictionary(uniqueKeysWithValues: ([first, second] + rows).map { ($0, 1.0 / 3) }))
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))
        let steps: [(XCUIKeyboardKey, String)] = [
            (.rightArrow, second), (.rightArrow, rows[0]), (.downArrow, rows[1]), (.downArrow, rows[2]),
            // Back to the row used last, not the top one.
            (.leftArrow, second), (.rightArrow, rows[2]),
            (.leftArrow, second), (.leftArrow, first), (.leftArrow, first), (.upArrow, first),
        ]
        for (index, (key, pane)) in steps.enumerated() {
            app.typeKey(key, modifierFlags: [.command, .option])
            XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")), "step \(index) to \(pane)")
        }
    }

    func testContextMenuSplitsLeftRenamesAndMovesToNewTab() async throws {
        let (tab, pane) = try await newTab("menu")
        restoreHerdrFocusAfter()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 3))

        paneMenu(pane, "Split Left", screenshot: "context menu")
        try await expect("a new pane left of the first") {
            let panes = try await order(tab)
            return panes.count == 2 && panes.last == pane
        }

        paneMenu(pane, "Rename Pane…")
        let field = element("pane.\(pane).rename")
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("renamed\r")
        try await expect("herdr's label") { try await label(pane) == "renamed" }
        XCTAssertTrue(element("pane.\(pane)").has(\.label, "renamed", within: 2))
        // Reset Pane Name clears it: the header shows the program again.
        paneMenu(pane, "Reset Pane Name")
        try await expect("no label") { try await label(pane) == nil }
        XCTAssertTrue(until(2) { element("pane.\(pane)").label != "renamed" })

        let before = try await tabIDs()
        paneMenu(pane, "Move Pane to Tab", "New Tab")
        let moved = try await newTabID(after: before)
        // Gone already after the move to a new workspace below, which takes its only pane.
        closeAfter("tab", moved)
        try await expect("the pane in the new tab") { try await order(moved) == [pane] }
        // The page follows the pane.
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))

        // To a new workspace: a new pane id, the same terminal, and it keeps the keyboard.
        let terminal = try await terminalID(pane)
        let workspaces = try await workspaceIDs()
        XCTAssertFalse(workspaces.isEmpty)
        closeNew("workspace", besides: workspaces)
        paneMenu(pane, "Move Pane to Tab", "New Workspace")
        let away = try await poll("the pane in a new workspace") { () async throws -> String? in
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
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
}

extension OrielUITests {
    /// Right-clicks the card's header and picks the item of its context menu.
    func paneMenu(_ pane: String, _ item: String, _ subitem: String? = nil, screenshot: String? = nil) {
        element("pane.\(pane)").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: 18))
            .rightClick()
        // In the window, not the menu bar's View ▸ Pane, which has the same titles.
        let entry = app.windows.firstMatch.menuItems[item]
        XCTAssertTrue(entry.exists(within: 2))
        if let screenshot {
            keepScreenshot(screenshot)
        }
        entry.click()
        if let subitem {
            let sub = entry.menuItems[subitem]
            XCTAssertTrue(sub.exists(within: 2))
            sub.click()
        }
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
        return try field(layout?["root"], "\(tab)'s layout")
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
        try await expect("widths \(widths)") {
            let found = try await shares(root(tab), 1)
            return found.count == widths.count && widths.allSatisfy { abs((found[$0.key] ?? -1) - $0.value) <= 0.02 }
        }
    }

    /// The ratio of the split at `path` (`false` = first child), within 0.02.
    func expectRatio(_ tab: String, at path: [Bool], _ ratio: Double) async throws {
        try await expect("ratio \(ratio)") {
            var node = try await root(tab)
            for step in path {
                node = node[step ? "second" : "first"] as? [String: Any] ?? [:]
            }
            return abs((node["ratio"] as? Double ?? -1) - ratio) <= 0.02
        }
    }

    /// Waits up to 3 s for the element's accessibility value to be one of these.
    func expectValue(_ element: XCUIElement, _ values: String...) {
        XCTAssertTrue(until(3) { values.contains(element.stringValue) },
                      "\(element.identifier) has \(element.value ?? "no value"), not \(values)")
    }

    func label(_ pane: String) async throws -> String? {
        try await self.pane(pane)["label"] as? String
    }
}
