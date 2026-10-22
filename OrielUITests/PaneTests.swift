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
        XCTAssertTrue(divider.waitForExistence(timeout: 3))

        app.typeKey("=", modifierFlags: [.command, .control])
        try await expectWidths(tab, [first: 1 / 3, second: 1 / 3, third: 1 / 3])
        XCTAssertTrue(hasValue(divider, "33%", timeout: 2))

        // The row less the page's two edges and the root's gap.
        let total = element("page.\(tab)").frame.width - 3 * 8
        let center = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.hover()
        keepScreenshot("three panes, grip")
        center.click(forDuration: 0.2, thenDragTo: center.withOffset(CGVector(dx: total * 0.15, dy: 0)))
        try await expectRatio(tab, at: [], 1 / 3 + 0.15)

        divider.doubleClick()
        try await expectRatio(tab, at: [], 0.5)
        XCTAssertTrue(hasValue(divider, "50%", timeout: 2))
    }

    func testSplitRightTwiceGivesThirds() async throws {
        let (tab, pane) = try await newTab("thirds")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("page.\(tab)").wait(for: \.isHittable, toEqual: true, timeout: 3))
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
    }

    func testKeysMoveTheKeyboardSwapAndResize() async throws {
        let (tab, first) = try await newTab("keys")
        let second = try await split(first)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").waitForExistence(timeout: 3))
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        app.typeKey(.rightArrow, modifierFlags: [.command, .control])
        try await expectRatio(tab, at: [], 0.55)

        // ⌥⇧⌘→ through its menu item: global hotkeys of other apps take ⌥⇧ chords.
        pick("Pane", "Move Pane Right")
        try await poll("the two swapped") { () async throws -> Bool? in
            try await order(tab) == [second, first] ? true : nil
        }
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))

        // Focus follows mouse: a pointer resting on the other card takes the keyboard there.
        pick("Pane", "Focus Follows Mouse")
        addTeardownBlock { @MainActor in self.pick("Pane", "Focus Follows Mouse") }
        hoverHeader(second)
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
    }

    func testContextMenuSplitsLeftRenamesAndMovesToNewTab() async throws {
        let (tab, pane) = try await newTab("menu")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(pane)").waitForExistence(timeout: 3))

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
        addTeardownBlock { [one] in _ = try? await Self.call(one, "tab.close", ["tab_id": moved]) }
        try await poll("the pane in the new tab") { () async throws -> Bool? in
            try await order(moved) == [pane] ? true : nil
        }
        // The page follows the pane.
        XCTAssertTrue(element("tab.\(moved)").wait(for: \.isSelected, toEqual: true, timeout: 3))
    }

    func testZoomIsDisabledAloneAndAZoomedCardShowsRestoreAndClose() async throws {
        let (tab, first) = try await newTab("zoom")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").waitForExistence(timeout: 3))
        hoverHeader(first)
        XCTAssertTrue(element("pane.\(first).zoom").waitForExistence(timeout: 2))
        XCTAssertFalse(element("pane.\(first).zoom").isEnabled)

        let second = try await split(first)
        XCTAssertTrue(element("pane.\(second)").waitForExistence(timeout: 3))
        hoverHeader(first)
        XCTAssertTrue(element("pane.\(first).zoom").wait(for: \.isEnabled, toEqual: true, timeout: 2))
        element("pane.\(first).zoom").click()
        XCTAssertTrue(element("pane.\(second)").waitForNonExistence(timeout: 2))
        XCTAssertEqual(element("pane.\(first).zoom").label, "Restore")
        XCTAssertTrue(element("pane.\(first).close").exists)
        XCTAssertFalse(element("pane.\(first).split-right").exists)
        XCTAssertFalse(element("pane.\(first).split-down").exists)
        keepScreenshot("zoomed card")
    }

    func testCardsWithoutTheKeyboardFade() throws {
        XCTAssertTrue(element("terminal.w1:p1").waitForExistence(timeout: connect))
        element("terminal.w1:p1").click()
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))
        let keyboard = element("pane.w1:p1"), other = element("pane.w1:p2")
        XCTAssertTrue(hasValue(keyboard, "content 100%", timeout: 2))
        XCTAssertTrue(hasValue(other, "content 70%", timeout: 2))
        keepScreenshot("faded cards, key window")

        // The setting turns the fade off.
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Fade Inactive Panes"].click()
        XCTAssertTrue(hasValue(other, "content 100%", timeout: 2))
        keepScreenshot("unfaded cards")
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Fade Inactive Panes"].click()
        XCTAssertTrue(hasValue(other, "content 70%", timeout: 2))

        // A window that is not key: 0.5 for the others, 0.8 (0.85 in light) for the keyboard card.
        let (first, _) = try newWindow()
        let card = element("pane.w1:p1", in: first)
        XCTAssertTrue(hasValue(element("pane.w1:p2", in: first), "content 50%", timeout: 3))
        XCTAssertTrue(["content 80%", "content 85%"].contains(card.value as? String ?? ""), "\(card.value ?? "")")
        let shot = XCTAttachment(screenshot: first.screenshot())
        shot.name = "faded cards, window not key"
        shot.lifetime = .keepAlways
        add(shot)
        app.typeKey("w", modifierFlags: [.command, .shift])
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
        XCTAssertTrue(entry.waitForExistence(timeout: 2))
        if let screenshot {
            keepScreenshot(screenshot)
        }
        entry.click()
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

    /// Polls the element's accessibility value every 100 ms.
    func hasValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 2) -> Bool {
        let end = Date.now.addingTimeInterval(timeout)
        while Date.now < end {
            if element.value as? String == value {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    func label(_ pane: String) async throws -> String? {
        try await (Self.call(one, "pane.get", ["pane_id": pane])["pane"] as? [String: Any])?["label"] as? String
    }
}
