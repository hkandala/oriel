import XCTest

/// The title row (phase 13): sidebar toggle, machine and workspace buttons, the tab bar and its menus. Session
/// one's w1 "alpha" has t1 (three panes) and t2 "second"; w2 "beta" has one tab.
extension OrielUITests {
    func testTabsStayInTheTitleRowWithTheSidebarOpenOrCollapsed() {
        let window = app.windows.firstMatch, toggle = element("titlebar.sidebar")
        let tab = element("tab.w1:t2"), workspace = element("titlebar.workspace")
        XCTAssertTrue(tab.waitForExistence(timeout: connect))
        XCTAssertEqual(toggle.value as? String, "open")
        XCTAssertLessThan(tab.frame.maxY, window.frame.minY + 40)
        XCTAssertFalse(workspace.exists)
        // The capsule alone: the sidebar lists no tabs.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tab.w1:t2").count, 1)
        keepScreenshot("sidebar open")

        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("sidebar.filter").waitForNonExistence(timeout: 2))
        XCTAssertEqual(toggle.value as? String, "closed")
        XCTAssertTrue(workspace.waitForExistence(timeout: 2))
        XCTAssertEqual(workspace.value as? String, "\(one) | alpha")
        XCTAssertLessThan(tab.frame.maxY, window.frame.minY + 40)
        XCTAssertGreaterThan(tab.frame.minX, workspace.frame.maxX)
        keepScreenshot("sidebar collapsed")

        toggle.click()
        XCTAssertTrue(element("sidebar.filter").waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.value as? String, "open")
        XCTAssertTrue(workspace.waitForNonExistence(timeout: 2))
    }

    func testMachineMenuListsThisMac() {
        XCTAssertTrue(element("titlebar.machine").waitForExistence(timeout: connect))
        element("titlebar.machine").click()
        let thisMac = app.menuItems["This Mac"]
        XCTAssertTrue(thisMac.waitForExistence(timeout: 2))
        // Its checkmark is not in XCUITest's view of a menu item (phase 10); the screenshot shows it.
        XCTAssertTrue(app.menuItems["Add Remote Host…"].exists)
        keepScreenshot("machine menu")
        // The current machine: nothing changes.
        thisMac.click()
        XCTAssertTrue(thisMac.waitForNonExistence(timeout: 2))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(element("tab.w1:t2").exists)
    }

    func testWorkspaceMenuMakesAndPicksWorkspaces() async throws {
        XCTAssertTrue(element("tab.w1:t2").waitForExistence(timeout: connect))
        app.typeKey("s", modifierFlags: [.command, .control])
        let button = element("titlebar.workspace")
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        let filter = openWorkspaceMenu()
        XCTAssertTrue(element("workspaces.w1").isSelected)
        keepScreenshot("workspace menu")
        // Arrows move; Esc closes.
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(element("workspaces.w2").wait(for: \.isSelected, toEqual: true, timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.waitForNonExistence(timeout: 2))
        openWorkspaceMenu()

        // A name no workspace has: Enter makes it in herdr, and the app selects it.
        let name = "made-\(Int.random(in: 1000 ... 9999))"
        app.typeText(name)
        XCTAssertTrue(element("workspaces.create").wait(for: \.isSelected, toEqual: true, timeout: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.waitForNonExistence(timeout: 2))
        let made = try await poll("herdr to have \(name)") { () async throws -> String? in
            let snapshot = try await self.snapshot()
            let workspaces = snapshot?["workspaces"] as? [[String: Any]] ?? []
            return workspaces.first { $0["label"] as? String == name }?["workspace_id"] as? String
        }
        addTeardownBlock { [one] in _ = try? await Self.call(one, "workspace.close", ["workspace_id": made]) }
        // In home, not the server's cwd (the runner's own home is its sandbox container).
        let panes = try await snapshot()?["panes"] as? [[String: Any]] ?? []
        XCTAssertEqual(
            panes.first { $0["workspace_id"] as? String == made }?["cwd"] as? String,
            "/Users/\(NSUserName())",
        )
        try await poll("the button to show \(name)") { button.value as? String == "\(one) | \(name)" ? true : nil }
        XCTAssertTrue(element("tab.\(made):t1").waitForExistence(timeout: 2))

        // Picking another workspace shows its tabs.
        openWorkspaceMenu()
        element("workspaces.w2").click()
        XCTAssertTrue(element("tab.w2:t1").waitForExistence(timeout: 2))
        XCTAssertFalse(element("tab.w1:t1").exists)
        XCTAssertEqual(button.value as? String, "\(one) | beta")
        keepScreenshot("one tab")
    }

    func testCloseButtonShowsOnTheHoveredTabAndCloses() async throws {
        let (workspace, tabs) = try await newWorkspace(tabs: 3)
        let close = element("tab.\(tabs[1]).close")
        XCTAssertFalse(close.exists)
        element("tab.\(tabs[1])").hover()
        XCTAssertTrue(close.waitForExistence(timeout: 2))
        keepScreenshot("hover and close")
        element("tab.\(tabs[2])").hover()
        XCTAssertTrue(close.waitForNonExistence(timeout: 2))
        element("tab.\(tabs[1])").hover()
        close.click()
        let confirm = app.sheets.buttons["Close Tab"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.click()
        try await poll("herdr to close it") { () async throws -> Bool? in
            try await tabsOf(workspace).map(\.id) == [tabs[0], tabs[2]] ? true : nil
        }
        XCTAssertTrue(element("tab.\(tabs[1])").waitForNonExistence(timeout: 2))
    }

    func testTabContextMenuRenamesAndMoves() async throws {
        let (workspace, tabs) = try await newWorkspace(tabs: 3)
        keepScreenshot("three tabs")
        let field = element("tab.\(tabs[0]).rename")
        // A double-click on the title starts it too; Esc cancels.
        element("tab.\(tabs[0])").doubleClick()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))

        element("tab.\(tabs[0])").rightClick()
        app.menuItems["Rename Tab"].click()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        XCTAssertTrue(hasKeyboard(field))
        app.typeKey("a", modifierFlags: .command)
        app.typeText("renamed\r")
        try await poll("herdr's label") { () async throws -> Bool? in
            try await tabsOf(workspace).first?.label == "renamed" ? true : nil
        }
        XCTAssertTrue(field.waitForNonExistence(timeout: 2))

        element("tab.\(tabs[0])").rightClick()
        XCTAssertFalse(app.menuItems["Move Tab Left"].isEnabled)
        app.menuItems["Move Tab Right"].click()
        try await poll("the new order") { () async throws -> Bool? in
            try await tabsOf(workspace).map(\.id) == [tabs[1], tabs[0], tabs[2]] ? true : nil
        }
        // The moved tab stays selected, and the marker stays on it.
        let moved = element("tab.\(tabs[0])")
        XCTAssertTrue(moved.isSelected)
        try await poll("the marker on the moved tab") {
            (moved.value as? String)?.hasPrefix("in view") == true ? true : nil
        }
    }

    func testCloseOtherTabsAsksOnceAndLeavesOneTab() async throws {
        let (workspace, tabs) = try await newWorkspace(tabs: 3)
        try await split("\(workspace):p1")
        element("tab.\(tabs[1])").rightClick()
        app.menuItems["Close Other Tabs"].click()
        let confirm = app.sheets.buttons["Close Tabs"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        // t1's two panes and t3's one.
        XCTAssertTrue(app.sheets.staticTexts
            .matching(NSPredicate(format: "value CONTAINS '3 panes' OR label CONTAINS '3 panes'")).firstMatch
            .waitForExistence(timeout: 2))
        confirm.click()
        try await poll("one tab left") { () async throws -> Bool? in
            try await tabsOf(workspace).map(\.id) == [tabs[1]] ? true : nil
        }
        XCTAssertTrue(element("tab.\(tabs[0])").waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testTwelveTabsKeepTheirWidthAndTheSelectedOneInView() async throws {
        let (workspace, twelve) = try await newWorkspace(tabs: 12)
        app.typeKey("s", modifierFlags: [.command, .control])
        let button = element("titlebar.workspace"), palette = element("titlebar.palette")
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        // Enough tabs to pass 64 pt each on this display's window (12 on a 1200 pt one).
        let more = Int((palette.frame.minX - button.frame.maxX) / 65) + 2 - twelve.count
        for _ in 0 ..< max(more, 0) {
            try await Self.call(one, "tab.create", ["workspace_id": workspace, "cwd": "/tmp", "focus": false])
        }
        let tabs = try await tabsOf(workspace).map(\.id)
        let first = element("tab.\(tabs[0])"), last = element("tab.\(tabs[tabs.count - 1])")
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(first.frame.width, 64)
        // ⌘ and + keep their place in the window.
        XCTAssertLessThan(element("titlebar.new-tab").frame.maxX, app.windows.firstMatch.frame.maxX)
        // Past the bar's end: the bar scrolls.
        XCTAssertGreaterThan(last.frame.maxX, palette.frame.minX)
        keepScreenshot("twelve tabs")

        // ⇧⌘[ from the first goes round to the last: the bar scrolls to it.
        app.typeKey("[", modifierFlags: [.command, .shift])
        XCTAssertTrue(last.wait(for: \.isSelected, toEqual: true, timeout: 2))
        try await poll("the last tab in view") { last.frame.maxX < palette.frame.minX ? true : nil }
        XCTAssertGreaterThanOrEqual(last.frame.width, 64)
    }

    func testHoldingCommandShowsKeycaps() async throws {
        let tab = element("tab.w1:t2")
        XCTAssertTrue(tab.waitForExistence(timeout: connect))
        XCTAssertFalse(tab.label.contains("⌘2"))
        XCUIElement.perform(withKeyModifiers: .command) {
            for _ in 0 ..< 30 where !tab.label.contains("⌘2") {
                Thread.sleep(forTimeInterval: 0.1)
            }
            XCTAssertTrue(tab.label.contains("⌘2"))
            // Only the tabs: the sidebar shows none.
            XCTAssertFalse(element("workspace.w1").label.contains("⌘"))
            keepScreenshot("keycap hints")
        }
        try await poll("the keycaps to go") { tab.label.contains("⌘2") ? nil : true }
    }

    /// A labeled tab's title is its label (testShowsWorkspacesTabsAndSplits: "second - ‹session›").
    func testWindowTitleOfADefaultLabelIsTheProgramAndFolder() async throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(element("tab.w1:t2").waitForExistence(timeout: connect))
        // t1 keeps herdr's default label: the front card's program and folder name (/private/tmp).
        try await poll("the window title") { window.title == "zsh tmp - \(one)" ? true : nil }
    }

    /// Opens the workspace menu; its filter has the keyboard.
    @discardableResult
    private func openWorkspaceMenu() -> XCUIElement {
        element("titlebar.workspace").click()
        let filter = element("workspaces.filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 2))
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    /// A workspace of its own with this many tabs, closed after the test and selected: its id and the tab ids.
    private func newWorkspace(tabs count: Int) async throws -> (String, [String]) {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        let created = try await Self.call(one, "workspace.create", ["label": "row", "cwd": "/tmp", "focus": false])
        let workspace = try XCTUnwrap((created["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in _ = try? await Self.call(one, "workspace.close", ["workspace_id": workspace]) }
        for _ in 1 ..< count {
            try await Self.call(one, "tab.create", ["workspace_id": workspace, "cwd": "/tmp", "focus": false])
        }
        let tabs = try await tabsOf(workspace).map(\.id)
        XCTAssertTrue(element("workspace.\(workspace)").waitForExistence(timeout: 2))
        element("workspace.\(workspace)").click()
        XCTAssertTrue(element("tab.\(tabs[count - 1])").waitForExistence(timeout: 3))
        return (workspace, tabs)
    }

    /// The workspace's tabs in herdr's order.
    private func tabsOf(_ workspace: String) async throws -> [(id: String, label: String)] {
        let snapshot = try await snapshot()
        return (snapshot?["tabs"] as? [[String: Any]] ?? []).filter { $0["workspace_id"] as? String == workspace }
            .compactMap { tab in (tab["tab_id"] as? String).map { ($0, tab["label"] as? String ?? "") } }
    }
}
