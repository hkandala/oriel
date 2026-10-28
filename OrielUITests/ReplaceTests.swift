import XCTest

/// Replace Pane (⇧⌘R): a fresh shell in the pane's place, size and folder, with the keyboard; it asks first, as Close
/// Pane does, when something besides the shell runs.
extension OrielUITests {
    /// With motion (CI has Reduce Motion on): the new pane takes the old card in place, so no card comes into the
    /// page sliding from its side and none fades out.
    func testReplacingAShellPaneTakesItsPlaceAndFolder() async throws {
        relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace")
        let right = try await split(left)
        let below = try await split(right, "down")
        try await settle([tab])
        try await send("cd /usr/bin\r", to: right)
        try await expect("the pane in /usr/bin") { try await pane(right)["cwd"] as? String == "/usr/bin" }
        element("tab.\(tab)").click()
        // Where the card rests in its tab's page: the strip slides to the tab.
        let card = element("pane.\(right)"), page = element("page.\(tab)")
        func place(_ card: XCUIElement) -> CGRect {
            card.frame.offsetBy(dx: -page.frame.minX, dy: -page.frame.minY)
        }
        var frame = CGRect.null
        XCTAssertTrue(until(3) {
            defer { frame = card.exists ? place(card) : .null }
            return card.exists && place(card) == frame
        })
        element("terminal.\(right)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(right)"))
        let cards = element("cards.\(tab)"), came = cards.stringValue

        app.typeKey("r", modifierFlags: [.command, .shift])
        let new = try await replaced(right, in: tab, besides: [left, below])
        XCTAssertTrue(card.vanishes(within: 3))
        let replaced = element("pane.\(new)")
        XCTAssertTrue(replaced.exists(within: 3))
        XCTAssertFalse(until(1) { cards.stringValue != came }, "cards came, went: \(came), then \(cards.stringValue)")
        // The old card's place and size, to the point.
        XCTAssertTrue(until(3) {
            guard replaced.exists else { return false }
            let now = place(replaced)
            return [now.minX - frame.minX, now.minY - frame.minY, now.width - frame.width, now.height - frame.height]
                .allSatisfy { abs($0) <= 1 }
        }, "\(place(replaced)) is not \(frame)")
        try await expect("the new pane in the old one's folder") {
            try await pane(new)["cwd"] as? String == "/usr/bin"
        }
        try await waitForPrompt(new)
        try await typeAndRead(new)
    }

    /// A zoomed pane's new pane stays zoomed; a floated pane's new pane floats in a window where the old one was, with
    /// its Stay on Top.
    func testReplacingKeepsTheZoomAndTheFloatingWindow() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace zoom")
        let right = try await split(left)
        try await settle([tab])
        element("tab.\(tab)").click()
        hoverHeader(right)
        element("pane.\(right).zoom").click()
        XCTAssertTrue(element("pane.\(left)").vanishes(within: 2))
        element("terminal.\(right)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(right)"))
        app.typeKey("r", modifierFlags: [.command, .shift])
        let zoomed = try await replaced(right, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(zoomed)").exists(within: 3))
        XCTAssertFalse(element("pane.\(left)").exists)
        XCTAssertEqual(element("pane.\(zoomed)").frame.width, element("page.\(tab)").frame.width, accuracy: 2)
        try await waitForPrompt(zoomed)
        try await typeAndRead(zoomed)

        // The zoom is the new pane's: ⇧⌘↩ restores it.
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(left)").exists(within: 2))

        let window = try float(zoomed)
        element("float.\(zoomed).pin").click()
        XCTAssertTrue(hasKeyboard("terminal.\(zoomed)", in: window))
        let frame = window.frame
        app.typeKey("r", modifierFlags: [.command, .shift])
        let floated = try await replaced(zoomed, in: tab, besides: [left])
        XCTAssertTrue(window.vanishes(within: 3))
        let next = app.windows.containing(.any, identifier: "float.\(floated)").firstMatch
        XCTAssertTrue(next.exists(within: 3))
        XCTAssertEqual(next.frame, frame)
        XCTAssertEqual(element("float.\(floated).pin").stringValue, "on")
        try await waitForPrompt(floated)
        try await typeAndRead(floated)
    }

    /// The one new pane of the tab, once herdr closed the old one and the others stayed.
    func replaced(_ old: String, in tab: String, besides others: [String]) async throws -> String {
        try await poll("a new pane in \(old)'s place") { () async throws -> String? in
            let panes = try await (snapshot()["panes"] as? [[String: Any]] ?? [])
                .filter { $0["tab_id"] as? String == tab }.compactMap { $0["pane_id"] as? String }
            let new = panes.filter { !others.contains($0) }
            return Set(others).isSubset(of: panes) && new.count == 1 && new[0] != old ? new[0] : nil
        }
    }

    /// Return confirms, Esc keeps the pane; from the palette too.
    func testReplacingAPaneRunningAProgramAsks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("replace ask")
        let pane = try await split(left)
        try await settle([tab])
        try await runSleep(pane)
        element("tab.\(tab)").click()
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))

        app.typeKey("r", modifierFlags: [.command, .shift])
        let confirm = app.sheets.buttons["Replace Pane"]
        XCTAssertTrue(confirm.exists(within: 3))
        XCTAssertTrue(until(2) { isRed(confirm) })
        XCTAssertTrue(sheetText("Replace “/private/tmp”?").exists)
        XCTAssertTrue(sheetText("sleep is running in it and will end, here and in every herdr client. "
                + "This cannot be undone.").exists)
        keepScreenshot("replace pane dialog")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(confirm.vanishes(within: 2))
        let running = try await foreground(pane)
        XCTAssertTrue(running.contains("sleep"))
        XCTAssertTrue(element("pane.\(pane)").exists)

        openPalette()
        app.typeText("replace pane")
        XCTAssertTrue(element("palette.command.Replace Pane").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(confirm.exists(within: 3))
        app.typeKey(.return, modifierFlags: [])
        let new = try await replaced(pane, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(pane)").vanishes(within: 3))
        XCTAssertTrue(element("pane.\(new)").exists(within: 3))
        try await waitForPrompt(new)
        try await typeAndRead(new)
    }
}
