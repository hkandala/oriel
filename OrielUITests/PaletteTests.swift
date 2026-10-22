import XCTest

/// The command palette and the key map (phase 20).
extension OrielUITests {
    /// ⌘K lists the commands under headers; "split r" ranks Split Right first, and Enter splits the keyboard card.
    func testPaletteSplitsTheKeyboardCardRight() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("palette")
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
        openPalette()
        XCTAssertTrue(element("palette.section.Commands").exists)
        XCTAssertTrue(element("palette.command.Split Right").exists)
        keepScreenshot("palette root")
        app.typeText("split r")
        XCTAssertTrue(element("palette.command.Split Right").has(\.isSelected, true, within: 2))
        XCTAssertFalse(element("palette.section.Commands").exists)
        keepScreenshot("palette filtered")
        app.typeKey(.return, modifierFlags: [])
        let panes = try await poll("a second pane in the tab") { () async throws -> [[String: Any]]? in
            let panes = try await (snapshot()?["panes"] as? [[String: Any]] ?? [])
                .filter { $0["tab_id"] as? String == tab }
            return panes.count == 2 ? panes : nil
        }
        let other = try XCTUnwrap(panes.compactMap { $0["pane_id"] as? String }.first { $0 != pane })
        XCTAssertTrue(element("pane.\(other)").exists(within: 2))
        XCTAssertLessThan(element("pane.\(pane)").frame.maxX, element("pane.\(other)").frame.minX)
    }

    /// Rename Tab › holds the current name; Enter saves it to herdr. ⌫ on an empty field goes back to the root.
    func testPaletteRenamesTheTab() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, _) = try await newTab("before")
        element("tab.\(tab)").click()
        let filter = openPalette()
        app.typeText("rename tab")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "before", within: 2))
        XCTAssertFalse(element("palette.section.Commands").exists)
        keepScreenshot("palette rename")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("after")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        try await poll("herdr's label") { () async throws -> Bool? in
            let tabs = try await snapshot()?["tabs"] as? [[String: Any]] ?? []
            return tabs.contains { $0["tab_id"] as? String == tab && $0["label"] as? String == "after" } ? true : nil
        }

        openPalette()
        app.typeText("rename tab")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "after", within: 2))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(filter.has(\.stringValue, "", within: 2))
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(element("palette.section.Commands").exists(within: 2))
    }

    /// Appearance › previews a highlighted row on the window after 0.75 s; Esc puts the old one back.
    func testPaletteAppearancePreviewsAndEscRestores() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        // Settings persist (the app's own defaults): start dark, and end dark even when a step fails.
        pick("Appearance", "Dark")
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        let look = element("window.look")
        XCTAssertTrue(until(2) { look.stringValue.hasSuffix(" dark") })
        let dark = look.stringValue, light = dark.replacing("dark", with: "light")
        let filter = openPalette()
        app.typeText("dark")
        XCTAssertTrue(element("palette.command.Appearance").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("palette.title").has(\.stringValue, "Appearance", within: 2))
        // The current choice is lit first; ↑ lights Light, which shows after the delay.
        XCTAssertTrue(element("palette.choice.Dark").has(\.isSelected, true, within: 2))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(element("palette.choice.Light").has(\.isSelected, true, within: 2))
        XCTAssertTrue(look.has(\.stringValue, light, within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(look.has(\.stringValue, dark, within: 2))
        // Back on the root, still open; Esc there closes it.
        XCTAssertTrue(element("palette.command.Appearance").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    /// ⇧⌘P, Rex's key, also opens the palette; ⌃⇥ and ⌃⇧⇥ step the tabs (second shortcuts).
    func testSecondShortcuts() {
        XCTAssertTrue(element("tab.w1:t1").has(\.isSelected, true, within: connect))
        element("terminal.w1:p1").click()
        app.typeKey("p", modifierFlags: [.command, .shift])
        let filter = element("palette.filter")
        XCTAssertTrue(filter.exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(element("tab.w1:t2").has(\.isSelected, true, within: 2))
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(element("tab.w1:t1").has(\.isSelected, true, within: 2))
    }

    /// "open session" opens the Open Session sheet; "new window" opens a second window on the same session.
    func testPaletteOpensTheSheetAndANewWindow() throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPalette()
        app.typeText("open session")
        app.typeKey(.return, modifierFlags: [])
        let sheet = element("open-session.filter")
        XCTAssertTrue(sheet.exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(sheet.vanishes(within: 2))

        let identifier = app.windows.firstMatch.identifier
        openPalette()
        app.typeText("new window")
        app.typeKey(.return, modifierFlags: [])
        _ = try otherWindow(than: identifier)
    }

    /// The Sessions section lists the window's pages; Enter shows that page.
    func testPaletteShowsAnotherOpenPage() {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, one, within: 3))
        openPalette()
        app.typeText(two)
        XCTAssertTrue(element("palette.session.\(two)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("sidebar.header").has(\.stringValue, two, within: 3))
    }

    /// ⇧⌘G: the folder panel; the chosen folder is typed into the shell as a `cd`. ⌃⌘I types a chosen file's path,
    /// quoted, without Return.
    func testGoToDirectoryAndInsertPath() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, pane) = try await newTab("paths")
        let folder = "/private/tmp/oriel-e2e-go-\(Int.random(in: 1000 ... 9999))"
        try await waitForPrompt(pane)
        try await Self.call(
            one,
            "pane.send_text",
            ["pane_id": pane, "text": "mkdir -p \(folder) && touch '\(folder)/a b'; clear\r"],
        )
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "rm -rf \(folder)\r"])
        }
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
        app.typeKey("g", modifierFlags: [.command, .shift])
        choose(folder)
        // The line may wrap at the card's width.
        try await waitFor(pane, times: 100) { $0.replacing("\n", with: "").contains("cd -- '\(folder)'") }
        try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "clear; pwd\r"])
        try await waitFor(pane) { $0.split(separator: "\n").contains { $0 == folder } }

        try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "clear\r"])
        element("terminal.\(pane)").click()
        app.typeKey("i", modifierFlags: [.command, .control])
        choose("\(folder)/a b")
        try await waitFor(pane, times: 100) { $0.replacing("\n", with: "").contains("'\(folder)/a b'") }
    }

    /// In the open panel: Go to Folder with the path, then Open.
    private func choose(_ path: String) {
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.exists(within: 3))
        keepScreenshot("open panel")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
        panel.buttons["Open"].click()
        // The Go to Folder field looks up each typed letter: slow.
        XCTAssertTrue(panel.vanishes(within: 10))
    }

    /// Move Pane to Tab ▸ ‹tab› puts the pane right of the tab's last card, not beside herdr's focused pane.
    func testMoveToTabLandsBesideTheLastCard() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // Its tab goes with its only pane.
        let (mover, pane) = try await newTab("mover", closeAfter: false)
        addTeardownBlock { [one] in
            let close = try JSONSerialization.data(withJSONObject: ["id": "1", "method": "tab.close",
                                                                    "params": ["tab_id": mover]])
            _ = try? await Self.post(one, close + Data("\n".utf8))
        }
        let (target, first) = try await newTab("target")
        let last = try await split(first)
        // herdr's focus stays on the first card (focus: false).
        element("tab.\(target)").click()
        XCTAssertTrue(element("pane.\(last)").exists(within: 2))
        element("tab.\(mover)").click()
        XCTAssertTrue(element("pane.\(pane)").has(\.isHittable, true, within: 3))
        paneMenu(pane, "Move Pane to Tab", "target")
        try await poll("the pane right of the last card") { () async throws -> Bool? in
            try await order(target) == [first, last, pane] ? true : nil
        }
    }
}
