import XCTest

/// Replace Pane (⌘R): a fresh shell in the pane's place, size and folder, with the keyboard; it asks first, as Close
/// Pane does, when something besides the shell runs.
extension OrielUITests {
    func testReplacingAShellPaneTakesItsPlaceAndFolder() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace")
        let right = try await split(left)
        let below = try await split(right, "down")
        try await settle([tab])
        try await send("cd /usr/bin\r", to: right)
        try await expect("the pane in /usr/bin") { try await pane(right)["cwd"] as? String == "/usr/bin" }
        let card = element("pane.\(right)")
        XCTAssertTrue(card.exists(within: 3))
        let frame = card.frame
        element("terminal.\(right)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(right)"))

        app.typeKey("r", modifierFlags: .command)
        let new = try await poll("a new pane in the old one's place") { () async throws -> String? in
            let panes = try await (snapshot()["panes"] as? [[String: Any]] ?? [])
                .filter { $0["tab_id"] as? String == tab }.compactMap { $0["pane_id"] as? String }
            let new = panes.filter { ![left, right, below].contains($0) }
            return !panes.contains(right) && new.count == 1 ? new[0] : nil
        }
        // Only the shell ran: no question.
        XCTAssertFalse(app.sheets.buttons["Replace Pane"].exists)
        XCTAssertTrue(card.vanishes(within: 3))
        let replaced = element("pane.\(new)")
        // The old card's place and size, to the point.
        XCTAssertTrue(until(3) {
            replaced.exists && [replaced.frame.minX - frame.minX, replaced.frame.minY - frame.minY,
                                replaced.frame.width - frame.width, replaced.frame.height - frame.height]
                .allSatisfy { abs($0) <= 1 }
        }, "\(replaced.frame) is not \(frame)")
        try await expect("the new pane in the old one's folder") {
            try await pane(new)["cwd"] as? String == "/usr/bin"
        }
        try await waitForPrompt(new)
        try await typeAndRead(new)
    }

    /// Return confirms, Esc keeps the pane; from the palette too.
    func testReplacingAPaneRunningAProgramAsks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace ask")
        let pane = try await split(left)
        try await settle([tab])
        try await runSleep(pane)
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))

        app.typeKey("r", modifierFlags: .command)
        let confirm = app.sheets.buttons["Replace Pane"]
        XCTAssertTrue(confirm.exists(within: 3))
        XCTAssertTrue(app.sheets.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Replace “'"))
            .firstMatch.exists)
        XCTAssertTrue(sheetText("sleep is running in it and will end, here and in every herdr client. "
                + "This cannot be undone.").exists)
        keepScreenshot("replace pane dialog")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.vanishes(within: 2))
        await XCTAssertTrue(try foreground(pane).contains("sleep"))
        XCTAssertTrue(element("pane.\(pane)").exists)

        openPalette()
        app.typeText("replace pane")
        XCTAssertTrue(element("palette.command.Replace Pane").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.exists(within: 3))
        app.typeKey(.return, modifierFlags: [])
        let new = try await poll("a new pane in the old one's place") { () async throws -> String? in
            let panes = try await (snapshot()["panes"] as? [[String: Any]] ?? [])
                .filter { $0["tab_id"] as? String == tab }.compactMap { $0["pane_id"] as? String }
            return panes.count == 2 && !panes.contains(pane) ? panes.first { $0 != left } : nil
        }
        XCTAssertTrue(element("pane.\(pane)").vanishes(within: 3))
        XCTAssertTrue(element("pane.\(new)").exists(within: 3))
        try await waitForPrompt(new)
        try await typeAndRead(new)
    }
}
