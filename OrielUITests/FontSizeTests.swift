import XCTest

/// The text size (View ▸ Bigger, Smaller and Actual Size) and the Option key (phase 11). The size persists in the
/// app's own defaults, so the test puts it back.
extension OrielUITests {
    /// ⌘+ makes the text bigger, ⌘- smaller, ⌘0 brings back the default size. A shown card's grid follows, herdr's
    /// PTY follows it, and the stream stays open. ⌘= is not here: on CI a 1 pt step after ⌘+ did not change the grid
    /// (1x display), and the step was checked by hand instead.
    func testFontSizeKeys() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        app.typeKey("0", modifierFlags: .command)
        try await expectPTYSize("w1:p1")
        let actual = try XCTUnwrap(terminal.value as? String)
        let stream = try await pid(of: "w1:p1")

        app.typeKey("+", modifierFlags: .command)
        let bigger = try await expectGrid(terminal, smallerThan: actual)
        try await expectPTYSize("w1:p1")
        app.typeKey("0", modifierFlags: .command)
        try await expectGrid(terminal, actual)
        app.typeKey("+", modifierFlags: .command)
        try await expectGrid(terminal, bigger)
        app.typeKey("-", modifierFlags: .command)
        try await expectGrid(terminal, actual)
        try await expectPTYSize("w1:p1")
        let after = try await pid(of: "w1:p1")
        XCTAssertEqual(after, stream, "the stream was not opened again")
    }

    /// Option types the macOS characters on every keyboard layout (libghostty sent Alt on CI's by default).
    func testOptionTypesCharacters() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p1")
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_keys", ["pane_id": "w1:p1", "keys": ["ctrl+c"]])
        }
        try await Self.call(one, "pane.send_text", ["pane_id": "w1:p1", "text": "clear; cat -v\r"])
        try await poll("cat to run") { () async throws -> Bool? in
            try await foreground("w1:p1").contains("cat") ? true : nil
        }
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        // Not ⌥⇧ chords or ⌥.: launchers (Raycast) take some as global keys.
        app.typeKey("b", modifierFlags: .option)
        app.typeKey("1", modifierFlags: .option)
        app.typeKey(.return, modifierFlags: [])
        // The tty's echo of the typed line (cat -v prints its own escaped copy under it).
        try await waitFor("w1:p1") { $0.split(separator: "\n").contains("∫¡") }
    }

    /// The grid shrinks below `grid` (a bigger font); the new grid. On a 1x display a 1 pt step can keep the cell
    /// width (CI: 14 and 15 pt both 48 columns), so one side may stay.
    @discardableResult
    private func expectGrid(_ terminal: XCUIElement, smallerThan grid: String) async throws -> String {
        let size = { (grid: String) in grid.split(separator: " ").compactMap { Int($0) } }
        return try await poll("the grid to shrink below \(grid)") { () -> String? in
            guard let now = terminal.value as? String, size(now).count == 2, now != grid else { return nil }
            return size(now)[0] <= size(grid)[0] && size(now)[1] <= size(grid)[1] ? now : nil
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
