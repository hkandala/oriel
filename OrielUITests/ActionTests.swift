import XCTest

/// Actions (phase 4b): close, zoom, new tab and workspace, the palette. Session one's t1 is
/// p1 | (p2 / p3), t2 "second" holds p4; w2 is "beta".
extension OrielUITests {
    func testClosingAPaneAsksUnlessOnlyItsShellRuns() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, first) = try await newTab("close")
        let second = try await split(first)
        element("tab.\(tab)").click()
        try await waitForPrompt(second)

        // Something besides the shell runs: the app asks, and Cancel keeps the pane.
        try await send("sleep 100\r", to: second)
        try await expect("sleep to run") { try await foreground(second).contains("sleep") }
        hoverHeader(second)
        element("pane.\(second).close").click()
        let confirm = app.sheets.buttons["Close Pane"]
        XCTAssertTrue(confirm.exists(within: 2))
        keepScreenshot("close pane dialog")
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(confirm.vanishes(within: 2))
        XCTAssertTrue(element("pane.\(second)").exists)

        // Only the shell: the card goes at once.
        try await Self.call(one, "pane.send_keys", ["pane_id": second, "keys": ["ctrl+c"]])
        try await expect("the shell to be back") { try await !foreground(second).contains("sleep") }
        hoverHeader(second)
        element("pane.\(second).close").click()
        XCTAssertTrue(element("pane.\(second)").vanishes(within: 3))
        XCTAssertFalse(confirm.exists)
        XCTAssertTrue(element("pane.\(first)").exists)
    }

    func testClosingTheKeyboardCardHandsKeysToItsNeighbor() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("handoff")
        let right = try await split(left)
        element("tab.\(tab)").click()
        try await waitForPrompt(left)
        try await waitForPrompt(right)
        element("terminal.\(left)").click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(left)").vanishes(within: 3))
        try await typeAndRead(right)
    }

    func testClosingATabAsksFirst() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("doomed")
        try await split(pane)
        let row = element("tab.\(tab)")
        row.hover()
        element("tab.\(tab).close").click()
        let confirm = app.sheets.buttons["Close Tab"]
        XCTAssertTrue(confirm.exists(within: 2))
        // The count follows the snapshot, which may not have the split yet.
        XCTAssertTrue(app.sheets.staticTexts
            .matching(NSPredicate(format: "value CONTAINS '2 panes' OR label CONTAINS '2 panes'")).firstMatch
            .exists(within: 2))
        keepScreenshot("close tab dialog")
        confirm.click()
        XCTAssertTrue(row.vanishes(within: 3))
        let tabs = try await tabIDs()
        XCTAssertFalse(tabs.contains(tab))
    }

    func testPlusMakesATabAndSelectsIt() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let before = try await tabIDs()
        element("titlebar.new-tab").click()
        let tab = try await newTabID(after: before)
        closeAfter("tab", tab)
        XCTAssertTrue(tab.hasPrefix("w1:"))
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("page.\(tab)").has(\.isHittable, true, within: 3))
    }

    func testCommandTOpensInTheKeyboardCardsDirectoryAndCommandWClosesIt() async throws {
        XCTAssertTrue(element("terminal.w1:p2").exists(within: connect))
        try await waitForPrompt("w1:p2")
        try await send("cd /usr\r", to: "w1:p2")
        element("terminal.w1:p2").click()

        // ⌘T: the new tab opens in /usr and has the keyboard; ⌘W there closes it (only its shell runs).
        var pane = try await commandT()
        try await waitForPrompt(pane)
        try await typeAndRead(pane)
        let tab = try await tabOf(pane)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").vanishes(within: 3))

        // After a zoom and a restore by double-click, ⌘T still knows the card.
        element("tab.w1:t1").click()
        let header = element("pane.w1:p2").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 17))
        header.doubleClick()
        XCTAssertTrue(element("pane.w1:p1").vanishes(within: 2))
        header.doubleClick()
        XCTAssertTrue(element("pane.w1:p1").exists(within: 2))
        pane = try await commandT()
        try await closeAfter("tab", tabOf(pane))
    }

    /// ⌘T, then the new tab's pane once herdr has it; its cwd must be /usr.
    private func commandT() async throws -> String {
        let before = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        let tab = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
        let panes = try await snapshot()["panes"] as? [[String: Any]]
        let pane = try XCTUnwrap(panes?.first { $0["tab_id"] as? String == tab })
        XCTAssertEqual(pane["cwd"] as? String, "/usr")
        return try XCTUnwrap(pane["pane_id"] as? String)
    }

    private func tabOf(_ pane: String) async throws -> String {
        try await field(self.pane(pane)["tab_id"], "\(pane)'s tab")
    }

    func testNewWorkspaceAppearsSelected() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // From the second tab, after the sidebar was hidden and shown: a new workspace once came up blank then.
        element("tab.w1:t2").click()
        element("titlebar.sidebar").click()
        XCTAssertTrue(element("sidebar.filter").vanishes(within: 2))
        element("titlebar.sidebar").click()
        XCTAssertTrue(element("sidebar.new-workspace").exists(within: 2))
        let before = try await tabIDs()
        element("sidebar.new-workspace").click()
        let tab = try await newTabID(after: before)
        let workspace = workspace(of: tab)
        closeAfter("workspace", workspace)
        XCTAssertTrue(element("workspace.\(workspace)").exists(within: 3))
        // Only the selected workspace's pages are in the strip.
        XCTAssertTrue(element("page.\(tab)").exists(within: 3))
        XCTAssertFalse(element("page.w1:t1").exists)
        let pane = "\(workspace):p1"
        XCTAssertTrue(element("pane.\(pane)").has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)
        try await typeAndRead(pane)
    }

    func testZoomFillsThePageAndRestores() async throws {
        let card = element("pane.w1:p2")
        XCTAssertTrue(element("terminal.w1:p2").exists(within: connect))
        try await expectPTYSize("w1:p2")
        let page = element("page.w1:t1").frame, before = card.frame
        let neighbor = try XCTUnwrap(element("terminal.w1:p3").value as? String)
        hoverHeader("w1:p2")
        element("pane.w1:p2.zoom").click()
        XCTAssertTrue(element("pane.w1:p1").vanishes(within: 2))
        XCTAssertTrue(element("pane.w1:p3").vanishes(within: 2))
        XCTAssertEqual(card.frame.width, page.width, accuracy: 2)
        try await expectPTYSize("w1:p2")
        keepScreenshot("zoom")
        // Clicks and keys reach the zoomed terminal, not a hidden one under it.
        element("terminal.w1:p2").click()
        app.typeText("echo oriel-zoom-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.contains("\noriel-zoom-42") }
        // The hidden cards keep their size: the same rows, and the columns within one (CI's 1x display rounds the
        // hidden card's width differently).
        try await send("clear; stty size\r", to: "w1:p3")
        let grid = neighbor.split(separator: " ").compactMap { Int($0) }
        try await waitFor("w1:p3") { text in
            text.split(separator: "\n").contains { line in
                let size = line.split(separator: " ").compactMap { Int($0) }
                return size.count == 2 && grid.count == 2 && size[0] == grid[0] && abs(size[1] - grid[1]) <= 1
            }
        }

        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.w1:p1").exists(within: 2))
        XCTAssertTrue(element("pane.w1:p3").exists)
        XCTAssertEqual(card.frame.width, before.width, accuracy: 2)
        try await expectPTYSize("w1:p2")
    }

    func testPaletteFiltersAndJumps() {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let filter = openPalette()
        app.typeText("seco")
        XCTAssertTrue(element("palette.tab.w1:t1").vanishes(within: 2))
        XCTAssertTrue(element("palette.tab.w1:t2").exists)
        keepScreenshot("palette")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))

        // A workspace of the window, from the title-row button.
        element("titlebar.palette").click()
        XCTAssertTrue(hasKeyboard(filter))
        app.typeText("beta")
        XCTAssertTrue(element("palette.workspace.\(one).w2").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("page.w2:t1").exists(within: 2))

        openPalette()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    func testPaletteTakesKeysTypedRightAfterCommandK() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("terminal.w1:p1").click()
        app.typeKey("k", modifierFlags: .command)
        app.typeText("seco")
        XCTAssertTrue(element("palette.tab.w1:t1").vanishes(within: 2))
        XCTAssertTrue(element("palette.tab.w1:t2").exists)
    }

    func testPaletteEnterTakesTheMovedRowAndKeysFollow() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPalette()
        // "show": Show Agents, then Show Previous Tab (the menu's order); ↓ moves to it, and t1 steps round to t2.
        app.typeText("show")
        XCTAssertTrue(element("palette.command.Show Agents").has(\.isSelected, true, within: 2))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(element("palette.command.Show Previous Tab").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))
        try await waitForPrompt("w1:p4")
        try await typeAndRead("w1:p4")
    }
}
