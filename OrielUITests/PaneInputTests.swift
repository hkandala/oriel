import XCTest

/// Right clicks in a terminal (phase 24).
extension OrielUITests {
    /// A right click opens the card's menu, also in a mouse app, as herdr opens its pane menu; ⌥ sends it to the app.
    func testRightClickInATerminalOpensThePaneMenu() async throws {
        let (tab, pane) = try await newTab("menu")
        element("tab.\(tab)").click()
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)

        let command = "echo oriel-$((6*4))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        terminal.rightClick()
        let menu = app.windows.firstMatch.menuItems
        for item in ["Copy", "Paste", "Select All", "Split Right", "Zoom Pane", "Move Pane to Tab", "Close Pane"] {
            XCTAssertTrue(menu[item].exists(within: 2), item)
        }
        keepScreenshot("terminal menu")
        // Paste goes into the clicked terminal.
        menu["Paste"].click()
        try await waitFor(pane) { $0.contains(command) }
        try await send("\r", to: pane)
        try await waitFor(pane) { $0.contains("\noriel-24") }

        // A program that reads clicks (SGR mouse mode) sees the ⌥-right click as a plain right press: button 2, not
        // 10 (Alt adds 8).
        try await send("clear; printf '\\033[?1000h\\033[?1006h'; cat -v\r", to: pane)
        try await expect("cat to run") { try await foreground(pane).contains("cat") }
        XCUIElement.perform(withKeyModifiers: .option) { terminal.rightClick() }
        try await waitFor(pane) { $0.contains("[<2;") }
        XCTAssertFalse(menu["Copy"].exists)

        // Without ⌥ the menu opens over the mouse app too, and its pane commands act on the pane.
        terminal.rightClick()
        XCTAssertTrue(menu["Split Right"].exists(within: 2))
        menu["Split Right"].click()
        try await expect("a second pane in \(tab)") {
            try await (snapshot()["panes"] as? [[String: Any]])?.count { $0["tab_id"] as? String == tab } == 2
        }
    }
}
