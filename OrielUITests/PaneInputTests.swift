import XCTest

/// Right clicks and drops in a terminal (phase 24).
extension OrielUITests {
    /// A right click opens the card's menu, also in a mouse app, as herdr opens its pane menu; ⌥ sends it to the app.
    func testRightClickInATerminalOpensThePaneMenu() async throws {
        let (tab, first) = try await newTab("menu")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").has(\.isHittable, true, within: 3))
        try await waitForPrompt(first)

        element("terminal.\(first)").rightClick()
        let menu = app.windows.firstMatch.menuItems
        for item in ["Copy", "Select All", "Split Right", "Close Pane"] {
            XCTAssertTrue(menu[item].exists(within: 2), item)
        }
        keepScreenshot("terminal menu")
        menu["Split Right"].click()
        let second = try await poll("a second pane in \(tab)") { () async throws -> String? in
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            return panes.first { $0["tab_id"] as? String == tab && $0["pane_id"] as? String != first }?["pane_id"]
                as? String
        }
        try await waitForPrompt(second)

        // Paste goes into the clicked terminal, not the one with the keyboard.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let (pane, other) = focused.evaluate(with: element("terminal.\(first)")) ? (second, first) : (first, second)
        let terminal = element("terminal.\(pane)")
        let command = "echo oriel-$((6*4))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        terminal.rightClick()
        XCTAssertTrue(menu["Paste"].exists(within: 2))
        menu["Paste"].click()
        // pane.read wraps lines at the pane's width.
        try await waitFor(pane) { $0.replacing("\n", with: "").contains(command) }
        let elsewhere = try await read(other)
        XCTAssertFalse(elsewhere.replacing("\n", with: "").contains(command))

        // A program that reads clicks (SGR mouse mode) sees the ⌥-right click as a plain right press: button 2, not
        // 10 (Alt adds 8). Without ⌥ the menu opens over it.
        try await send("\u{15}clear; printf '\\033[?1000h\\033[?1006h'; cat -v\r", to: pane)
        try await expect("cat to run") { try await foreground(pane).contains("cat") }
        XCUIElement.perform(withKeyModifiers: .option) { terminal.rightClick() }
        try await waitFor(pane) { $0.contains("[<2;") }
        XCTAssertFalse(menu["Copy"].exists)
        terminal.rightClick()
        XCTAssertTrue(menu["Copy"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A file dragged from Finder pastes its shell-escaped path, as a drop on Ghostty (herdr's usual terminal) does.
    func testDroppingAFileFromFinderPastesItsPath() async throws {
        let (tab, pane) = try await newTab("drop")
        element("tab.\(tab)").click()
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)

        let path = try await String(decoding: Self.post("\(one)/reveal-file"), as: UTF8.self)
        // Its windows close, or they would cover the app in the next tests.
        addTeardownBlock { @MainActor in
            let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
            finder.activate()
            finder.typeKey("w", modifierFlags: [.command, .option])
        }
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let name = URL(filePath: path).lastPathComponent
        let file = finder.windows.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@", name, name)).firstMatch
        XCTAssertTrue(file.exists(within: 10))

        // Finder's window opens over the app (920 × 436 pt on CI): the drop goes on the terminal below it.
        let card = terminal.frame, finderFrame = finder.windows.firstMatch.frame
        let drop = CGPoint(x: card.midX, y: (finderFrame.maxY + card.maxY) / 2)
        XCTAssertGreaterThan(card.maxY - finderFrame.maxY, 40, "\(finderFrame) covers \(card)")
        let start = file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), from = file.frame
        let folder = URL(filePath: path).deletingLastPathComponent().lastPathComponent
        // Now and then Finder starts no drag from the press, and nothing drops (no drag image in the recordings of CI
        // 40172264488 and 40173000382, in full shards only): drag again.
        for attempt in 1 ... 3 {
            start.click(
                forDuration: 0.5,
                thenDragTo: start.withOffset(CGVector(dx: drop.x - from.midX, dy: drop.y - from.midY)),
                withVelocity: .slow,
                thenHoldForDuration: 0.5,
            )
            do {
                try await waitFor(pane, times: 30) {
                    $0.replacing("\n", with: "").contains(#"\#(folder)/drop\ me\'s\ \(1\).txt"#)
                }
                break
            } catch where attempt < 3 {}
        }
    }
}
