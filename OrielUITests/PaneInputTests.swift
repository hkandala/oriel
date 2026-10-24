import XCTest

/// Right clicks and drops in a terminal (phase 24).
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
        for item in ["Copy", "Select All", "Split Right", "Close Pane"] {
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
            XCUIApplication(bundleIdentifier: "com.apple.finder").typeKey("w", modifierFlags: [.command, .option])
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
        // From the app's window, not Finder's element: a gesture on Finder's element moved nothing on CI.
        let origin = app.windows.firstMatch.frame.origin, from = file.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: from.midX - origin.x, dy: from.midY - origin.y))
        start.press(
            forDuration: 0.5,
            thenDragTo: start.withOffset(CGVector(dx: drop.x - from.midX, dy: drop.y - from.midY)),
            withVelocity: .slow,
            thenHoldForDuration: 1,
        )
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "after the drop"
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(filePath: path).deletingLastPathComponent().lastPathComponent
        try await waitFor(pane) { $0.contains(#"\#(folder)/drop\ me\'s\ \(1\).txt"#) }
    }
}
