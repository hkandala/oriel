import XCTest

/// The text size (View ▸ Bigger, Smaller and Actual Size) and the Option key (phase 11). The size persists in the
/// app's own defaults, so the test puts it back.
extension OrielUITests {
    /// ⌘+ and ⌘= make the text bigger, ⌘- smaller, ⌘0 brings back the default size. A shown card's grid follows,
    /// herdr's PTY follows it, and the stream stays open.
    func testFontSizeKeys() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.waitForExistence(timeout: connect))
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        app.typeKey("0", modifierFlags: .command)
        try await expectPTYSize("w1:p1")
        let actual = try XCTUnwrap(terminal.value as? String)
        let stream = try await pid(of: "w1:p1")

        app.typeKey("+", modifierFlags: .command)
        let bigger = try await expectGrid(terminal, smallerThan: actual)
        try await expectPTYSize("w1:p1")
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
        let after = try await pid(of: "w1:p1")
        XCTAssertEqual(after, stream, "the stream was not opened again")
    }

    /// Option types the macOS characters on every keyboard layout (libghostty sent Alt on CI's by default).
    func testOptionTypesCharacters() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.waitForExistence(timeout: connect))
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

    func testDebugKeys() async throws {
        XCTAssertTrue(element("terminal.w1:p1").waitForExistence(timeout: connect))
        var out: [String] = []
        for (key, flags) in [
            ("=", XCUIElement.KeyModifierFlags.command),
            ("+", .command),
            ("-", .command),
            ("0", .command),
        ] {
            app.typeKey(key, modifierFlags: flags)
            try await Task.sleep(for: .milliseconds(300))
            out.append("\(key): \(app.windows.firstMatch.title)")
        }
        try await Self.call(one, "pane.send_text", ["pane_id": "w1:p1", "text": "clear; cat -v\r"])
        try await Task.sleep(for: .milliseconds(500))
        element("terminal.w1:p1").click()
        app.typeKey("=", modifierFlags: [])
        app.typeKey("+", modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        try await Task.sleep(for: .milliseconds(500))
        try await out.append(read("w1:p1"))
        _ = try? await Self.call(one, "pane.send_keys", ["pane_id": "w1:p1", "keys": ["ctrl+c"]])
        XCTFail("DEBUG " + out.joined(separator: " | "))
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
