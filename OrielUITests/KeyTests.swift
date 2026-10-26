import XCTest

/// Each level's keys (phase 25): `T` new, `W` close, `[` `]` step, 1–9 jump, the modifier names the level (⌘ tabs,
/// ⌃⌘ workspaces, ⌥⌘ sessions); the Keyboard Shortcuts panel on ⌘/.
extension OrielUITests {
    func testWorkspaceAndSessionKeysStepAndJump() async throws {
        let alpha = element("workspace.w1"), beta = element("workspace.w2")
        XCTAssertTrue(beta.exists(within: connect))
        XCTAssertTrue(alpha.isSelected)
        app.typeKey("]", modifierFlags: [.command, .control])
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))
        app.typeKey("[", modifierFlags: [.command, .control])
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 2))
        // Round the ends, as tabs.
        app.typeKey("[", modifierFlags: [.command, .control])
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))
        app.typeKey("1", modifierFlags: [.command, .control])
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 2))
        app.typeKey("2", modifierFlags: [.command, .control])
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))

        // ⌃⌘T: a new workspace, shown.
        let before = try await Self.ids("workspace", in: one)
        closeNew("workspace", besides: before)
        app.typeKey("t", modifierFlags: [.command, .control])
        let made = try await poll("the new workspace") {
            try await Self.ids("workspace", in: one).first { !before.contains($0) }
        }
        XCTAssertTrue(element("workspace.\(made)").has(\.isSelected, true, within: 3))
        // ⌃⌘W closes it: only its shell runs, so it does not ask.
        let tabs = try await snapshot()["panes"] as? [[String: Any]] ?? []
        try await settle(tabs.filter { $0["workspace_id"] as? String == made }.compactMap { $0["tab_id"] as? String })
        app.typeKey("w", modifierFlags: [.command, .control])
        XCTAssertTrue(element("workspace.\(made)").vanishes(within: 3))

        // A second page; ⌥⌘ steps and jumps between the window's sessions.
        openSessionPanel()
        element("open-session.session.\(two)").click()
        let header = element("sidebar.header")
        XCTAssertTrue(header.has(\.stringValue, two, within: 3))
        app.typeKey("[", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        app.typeKey("]", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, two, within: 3))
        app.typeKey("1", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        app.typeKey("2", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, two, within: 3))
        // ⌥⌘W detaches it: the window shows the other.
        app.typeKey("w", modifierFlags: [.command, .option])
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        XCTAssertTrue(element("sidebar.dot.\(two)").vanishes(within: 2))
    }

    /// The menu bar acts on the key window: two floating windows of one session each detach their own pane with ⌘W
    /// (spec review: a command list that read the same kept the first window's actions).
    func testEachFloatingWindowsKeysActOnItsOwnPane() async throws {
        let (tab, first) = try await newTab("float-keys")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let firstWindow = try float(first)
        let secondWindow = try float(second)
        // Show Window sits in the card's middle, under the floating windows: the main window comes forward first.
        element("tab.\(tab)").click()
        element("pane.\(second).show").click()
        XCTAssertTrue(hasKeyboard("terminal.\(second)", in: secondWindow))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(secondWindow.vanishes(within: 3))
        XCTAssertTrue(firstWindow.exists)
        element("tab.\(tab)").click()
        element("pane.\(first).show").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)", in: firstWindow))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(firstWindow.vanishes(within: 3))
    }

    /// ⌃⇥ and ⌃⇧⇥ step the tabs, never the panes (user, phase 31): in a tab of three panes, also with one tab, where
    /// they do nothing (AppKit's key view loop stepped the terminals).
    func testControlTabStepsTabsNeverPanes() async throws {
        let first = element("tab.w1:t1"), second = element("tab.w1:t2")
        XCTAssertTrue(first.has(\.isSelected, true, within: connect))
        let card = element("terminal.w1:p2")
        card.click()
        XCTAssertTrue(hasKeyboard(card))
        for _ in 0 ..< 3 {
            app.typeKey(.tab, modifierFlags: .control)
            XCTAssertTrue(second.has(\.isSelected, true, within: 2))
            app.typeKey(.tab, modifierFlags: [.control, .shift])
            XCTAssertTrue(first.has(\.isSelected, true, within: 2))
            XCTAssertTrue(hasKeyboard(card))
        }
        // A workspace of one tab and two panes: nothing moves.
        let (tab, pane) = try await createWorkspace("one-tab")
        let other = try await split(pane)
        element("workspace.\(workspace(of: tab))").click()
        XCTAssertTrue(element("terminal.\(other)").exists(within: 3))
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        // Each way on its own: with two panes, a step and a step back would land on the first again.
        for flags: XCUIElement.KeyModifierFlags in [.control, [.control, .shift]] {
            app.typeKey(.tab, modifierFlags: flags)
            XCTAssertFalse(hasKeyboard("terminal.\(other)"))
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        }
    }

    /// A key acts on the key window (user, phase 31): with two windows on different tabs, ⌘D right after switching
    /// splits the key window's tab only, each time.
    func testCommandDSplitsInTheKeyWindowOnly() async throws {
        let (first, second) = try newWindow()
        var tabs: [String] = []
        for (window, label) in [(first, "key-first"), (second, "key-second")] {
            let tab = try await createTab(in: "w2", label: label).tab
            closeAfter("tab", tab)
            raise(window)
            element("workspace.w2", in: window).click()
            element("tab.\(tab)", in: window).click()
            XCTAssertTrue(element("tab.\(tab)", in: window).has(\.isSelected, true, within: 3))
            tabs.append(tab)
        }
        func count(_ tab: String) async throws -> Int {
            try await (snapshot()["panes"] as? [[String: Any]] ?? []).count { $0["tab_id"] as? String == tab }
        }
        var counts = [1, 1]
        // Then right after the switch, with no wait: a window just made key.
        for round in 0 ..< 4 {
            for (index, window) in [first, second].enumerated() {
                if round < 2 {
                    raise(window)
                } else {
                    app.typeKey("`", modifierFlags: .command)
                }
                app.typeKey("d", modifierFlags: .command)
                counts[index] += 1
                try await expect("round \(round): \(tabs[index]) split, the other not") {
                    try await [count(tabs[0]), count(tabs[1])] == counts
                }
            }
        }
    }

    /// Holding ⌃⌘ shows the workspaces' jump keys at the end of their rows, as ⌘ does on the tabs.
    func testHoldingControlCommandShowsWorkspaceKeycaps() {
        let row = element("workspace.w2"), keycap = element("workspace.w2.keycap")
        XCTAssertTrue(row.exists(within: connect))
        XCTAssertFalse(keycap.exists)
        XCUIElement.perform(withKeyModifiers: [.command, .control]) {
            XCTAssertTrue(keycap.exists(within: 3))
            XCTAssertEqual(keycap.stringValue, "⌃⌘2")
            XCTAssertEqual(element("workspace.w1.keycap").stringValue, "⌃⌘1")
            // At the row's end, clear of the name.
            XCTAssertEqual(keycap.frame.maxX, row.frame.maxX - 8, accuracy: 2)
            XCTAssertGreaterThan(keycap.frame.minX, row.frame.midX)
            // Not the tabs': those are ⌘'s.
            XCTAssertFalse(element("tab.w1:t1.keycap").exists)
            keepScreenshot("workspace keycaps")
        }
        XCTAssertTrue(keycap.vanishes(within: 2))
    }

    func testKeyboardShortcutsPanelListsTheCommandsKeys() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let panel = element("shortcuts")
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(panel.exists(within: 2))
        for section in ["Panes", "Tabs", "Workspaces", "Sessions", "View", "Edit"] {
            XCTAssertTrue(element("shortcuts.section.\(section)").exists, section)
        }
        // A family is one row; a second key is on its first's row. One pattern (phase 25): the key says the action,
        // the modifier the level.
        let rows = [
            "Split Right": "⌘D", "Select Pane": "⌥⌘←→↑↓", "Show Tab 1–9": "⌘1–9", "New Workspace": "⌃⌘T",
            "Show Workspace 1–9": "⌃⌘1–9", "Show Session 1–9": "⌥⌘1–9", "Show Previous Tab": "⇧⌘[ or ⌃⇧⇥",
            "Show Next Tab": "⇧⌘] or ⌃⇥",
            "Command Palette": "⌘K or ⇧⌘P", "Find": "⌘F", "Reset Font Size": "⌘0", "Open Session": "⌥⌘T",
            "Close Tab": "⇧⌘W", "Close Workspace": "⌃⌘W", "Detach Session": "⌥⌘W", "Balance Splits": "⌥⌘=",
            "Insert Path": "⇧⌘I", "Zoom Pane": "⇧⌘↩", "Move Tab Left": "⇧⌘←", "Move Tab Right": "⇧⌘→",
        ]
        for (title, keys) in rows {
            XCTAssertEqual(element("shortcuts.\(title)").value as? String, keys, title)
        }
        // Keys that went.
        XCTAssertFalse(element("shortcuts.Resize Pane").exists)
        XCTAssertFalse(element("shortcuts.Close Window").exists)
        // Two columns.
        XCTAssertGreaterThan(element("shortcuts.section.Sessions").frame.minX,
                             element("shortcuts.section.Panes").frame.maxX)
        keepScreenshot("keyboard shortcuts")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2))
        // The keyboard is back on the card.
        XCTAssertTrue(hasKeyboard("terminal.w1:p1"))

        // Help ▸ Keyboard Shortcuts; ⌘/ closes it.
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Keyboard Shortcuts"].click()
        XCTAssertTrue(panel.exists(within: 2))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(panel.vanishes(within: 2))

        // The palette has it too.
        openPalette()
        app.typeText("keyboard shortcuts")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(panel.exists(within: 2))

        // Glass like the palette in the other look too (for the screenshot).
        relaunch(one, ["-appearance", "light", "-interfaceStyle", "classic"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(panel.exists(within: 2))
        keepScreenshot("keyboard shortcuts, light classic")
        // A click outside closes it (beside it: in CI's short window it reaches the bottom).
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.6)).click()
        XCTAssertTrue(panel.vanishes(within: 2))
    }
}
