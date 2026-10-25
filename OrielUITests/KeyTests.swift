import XCTest

/// Each level's keys (phase 25): `[` `]` step, 1–9 jump, the modifier names the level (⌘ tabs, ⌃⌘ workspaces,
/// ⌥⌘ sessions); the Keyboard Shortcuts panel on ⌘/.
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
    }

    func testKeyboardShortcutsPanelListsTheCommandsKeys() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let panel = element("shortcuts")
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(panel.exists(within: 2))
        for section in ["Panes", "Tabs", "Workspaces", "Sessions", "View", "Edit"] {
            XCTAssertTrue(element("shortcuts.section.\(section)").exists, section)
        }
        // A family is one row; a second key is on its first's row.
        let rows = [
            "Split Right": "⌘D", "Select Pane": "⌥⌘←→↑↓", "Show Tab 1–9": "⌘1–9", "New Workspace": "⌃⌘T",
            "Show Workspace 1–9": "⌃⌘1–9", "Show Session 1–9": "⌥⌘1–9", "Show Previous Tab": "⇧⌘[  ⌃⇧⇥",
            "Command Palette": "⌘K  ⇧⌘P", "Find": "⌘F", "Reset Font Size": "⌘0",
        ]
        for (title, keys) in rows {
            XCTAssertEqual(element("shortcuts.\(title)").value as? String, keys, title)
        }
        keepScreenshot("keyboard shortcuts")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.vanishes(within: 2))
        // The keyboard is back on the card.
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))

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
    }
}
