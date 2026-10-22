import XCTest

/// The Settings window and the terminal options (phase 11). Settings persist in the app's own defaults, so each
/// test puts back what it changes.
extension OrielUITests {
    /// Settings ▸ Terminal ▸ Font Size changes the grid of a shown card, herdr's PTY follows, and the stream stays.
    func testSettingsFontSizeResizesTheGrid() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.waitForExistence(timeout: connect))
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        // From the default size: at 32 pt the arrow would be disabled.
        app.typeKey("0", modifierFlags: .command)
        try await expectPTYSize("w1:p1")
        let before = try XCTUnwrap(terminal.value as? String)
        let stream = try await pid(of: "w1:p1")

        app.typeKey(",", modifierFlags: .command)
        let tab = app.toolbars.buttons["Terminal"]
        XCTAssertTrue(tab.waitForExistence(timeout: 2))
        tab.click()
        app.steppers["settings.fontSize"].incrementArrows.firstMatch.click()

        try await expectGrid(terminal, smallerThan: before)
        try await expectPTYSize("w1:p1")
        let after = try await pid(of: "w1:p1")
        XCTAssertEqual(after, stream, "the stream was not opened again")
        // ⌘W closes Settings, which has no pane to close.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(tab.waitForNonExistence(timeout: 2))
    }

    /// ⌘+ and ⌘= make the text bigger, ⌘- smaller, and ⌘0 brings back the grid of the default size.
    func testFontSizeKeys() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.waitForExistence(timeout: connect))
        app.typeKey("0", modifierFlags: .command)
        try await expectPTYSize("w1:p1")
        let actual = try XCTUnwrap(terminal.value as? String)
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }

        app.typeKey("+", modifierFlags: .command)
        let bigger = try await expectGrid(terminal, smallerThan: actual)
        app.typeKey("=", modifierFlags: .command)
        try await expectGrid(terminal, smallerThan: bigger)
        app.typeKey("0", modifierFlags: .command)
        try await expectGrid(terminal, actual)
        // ⌘= again, from the size another key set: one step bigger than actual.
        app.typeKey("=", modifierFlags: .command)
        try await expectGrid(terminal, bigger)
        app.typeKey("-", modifierFlags: .command)
        try await expectGrid(terminal, actual)
        try await expectPTYSize("w1:p1")
    }

    /// With Option as Alt (a launch argument, so nothing persists) ⌥ chords reach the program as Alt; without it
    /// they type macOS's Option characters. Not ⌥⇧ chords or ⌥.: launchers (Raycast) take some as global keys.
    func testOptionKeyActsAsAlt() async throws {
        let base = app.launchArguments
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_keys", ["pane_id": "w1:p1", "keys": ["ctrl+c"]])
        }
        for (alt, expected) in [("YES", "^[b^[1"), ("NO", "∫¡")] {
            app.terminate()
            app.launchArguments = base + ["-optionAsAlt", alt]
            app.launch()
            let terminal = element("terminal.w1:p1")
            XCTAssertTrue(terminal.waitForExistence(timeout: connect))
            try await waitForPrompt("w1:p1")
            try await Self.call(one, "pane.send_text", ["pane_id": "w1:p1", "text": "clear; cat -v\r"])
            try await poll("cat to run") { () async throws -> Bool? in
                try await foreground("w1:p1").contains("cat") ? true : nil
            }
            terminal.click()
            XCTAssertTrue(hasKeyboard(terminal))
            app.typeKey("b", modifierFlags: .option)
            app.typeKey("1", modifierFlags: .option)
            app.typeKey(.return, modifierFlags: [])
            try await waitFor("w1:p1") { $0.split(separator: "\n").contains { $0 == expected } }
            try await Self.call(one, "pane.send_keys", ["pane_id": "w1:p1", "keys": ["ctrl+c"]])
        }
    }

    /// The grid shrinks below `grid` (a bigger font); the new grid.
    @discardableResult
    private func expectGrid(_ terminal: XCUIElement, smallerThan grid: String) async throws -> String {
        let size = { (grid: String) in grid.split(separator: " ").compactMap { Int($0) } }
        return try await poll("the grid to shrink below \(grid)") { () -> String? in
            guard let now = terminal.value as? String, size(now).count == 2 else { return nil }
            return size(now)[0] < size(grid)[0] && size(now)[1] < size(grid)[1] ? now : nil
        }
    }

    private func expectGrid(_ terminal: XCUIElement, _ grid: String) async throws {
        try await poll("the grid \(grid)") { terminal.value as? String == grid ? true : nil }
    }

    /// The pid of the pane's `terminal session` run.
    private func pid(of pane: String) async throws -> String {
        let terminal = try await terminalID(pane)
        let line = try await streams(one).first { $0.contains(terminal) }
        return try String(XCTUnwrap(line?.split(separator: " ").first))
    }
}
