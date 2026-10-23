import XCTest

/// Phase 21: the find bar, links, the not running and failed start states, and programs of panes never shown.
extension OrielUITests {
    func testSecondPagesServerStopsAndStartsAloneOnItsPage() async throws {
        let five = try env("ORIEL_SESSION5")
        let (workspace, pane) = try await shown(running(five))
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openPage(five)
        XCTAssertTrue(element("workspace.\(workspace)").exists(within: connect))

        try await Self.post("\(five)/stop")
        let start = element("detail.start")
        XCTAssertTrue(start.exists(within: 10))
        // The first page is not touched: its cards and streams stay.
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(element("terminal.w1:p1").exists(within: 3))
        XCTAssertFalse(start.exists)
        try await expect("one's three streams") { try await streams(one).count == 3 }

        element("sidebar.dot.\(five)").click()
        XCTAssertTrue(start.exists(within: 3))
        start.click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: connect))
        XCTAssertFalse(start.exists)
        try await Self.snapshot(five)
    }

    func testAFailedStartKeepsTheSheetOpenWithRetry() async throws {
        let six = try env("ORIEL_SESSION6")
        // No time to answer: every start the app makes fails, though launchd starts the server.
        relaunch(one, ["-startTimeout", "0"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        app.typeKey("n", modifierFlags: [.command, .shift])
        let filter = element("open-session.filter")
        XCTAssertTrue(hasKeyboard(filter))
        app.typeText(six)
        XCTAssertTrue(element("open-session.new.\(six)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])

        let notice = element("open-session.notice")
        XCTAssertTrue(notice.exists(within: 10))
        let text = "Could not start \(six)."
        let said = notice.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", text,
                                                           text)).firstMatch
        XCTAssertTrue(said.exists, notice.debugDescription)
        XCTAssertEqual(notice.images["notice.symbol"].label, "Error")
        // The panel stays open and its row's start is over (its spinner gone).
        XCTAssertTrue(filter.exists)
        XCTAssertTrue(element("open-session.new.\(six)").exists)
        keepScreenshot("could not start")

        // The server came up after all: Retry finds it running and opens its page.
        try await running(six, start: false)
        notice.buttons["notice.retry"].click()
        XCTAssertTrue(filter.vanishes(within: connect))
        XCTAssertTrue(until(connect) { element("sidebar.header").value as? String == six })
    }

    func testFindScrollsHerdrsViewportToTheMatch() async throws {
        let pane = try await twoHundredLines("find")

        app.typeKey("f", modifierFlags: .command)
        let field = element("find.field"), count = element("find.count")
        XCTAssertTrue(hasKeyboard(field))
        // "line 4" and 40–49; the last one, nearest the bottom, first.
        field.typeText("line 4")
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        app.typeKey(.return, modifierFlags: .shift)
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        element("find.previous").click()
        XCTAssertTrue(count.has(\.stringValue, "11 of 11", within: 2), count.stringValue)
        element("find.next").click()
        XCTAssertTrue(count.has(\.stringValue, "1 of 11", within: 2), count.stringValue)
        // A fixed width (the Window menu has an item named "find" too: the bar is the group).
        XCTAssertEqual(app.groups.matching(identifier: "find").firstMatch.frame.width, 320, accuracy: 1)
        field.click()
        app.typeKey("a", modifierFlags: .command)

        app.typeText("line 42")
        XCTAssertTrue(count.has(\.stringValue, "1 of 1", within: 2), count.stringValue)
        // line 42 sits 158 lines above the bottom line: herdr's viewport scrolled to it.
        try await expect("herdr to scroll") { try await scrollOffset(pane) > 100 }
        // Its highlight is on the row herdr shows it on.
        try await expectHighlight("line 42", in: pane)
        keepScreenshot("find bar")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        try await expect("herdr back at the bottom") { try await scrollOffset(pane) == 0 }
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
        // Its ✕ closes it too.
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(field))
        element("find.close").click()
        XCTAssertTrue(field.vanishes(within: 2))
    }

    func testFindCountsTheBlankRowsUnderTheText() async throws {
        let pane = try await twoHundredLines("blank")
        let field = element("find.field"), count = element("find.count")
        // The screen cleared (its text goes to the scrollback) and two more matches under it: the blank rows under the
        // prompt count too, and the selected match is the lower one.
        try await send("printf '\\033[2J\\033[H'\r", to: pane)
        try await waitFor(pane) { !$0.contains("line 199") }
        try await send("for i in 42 42; do echo line $i; done\r", to: pane)
        try await waitFor(pane) { $0.contains("line 42\nline 42\n") }
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(field))
        app.typeText("line 42")
        XCTAssertTrue(count.has(\.stringValue, "3 of 3", within: 2), count.stringValue)
        try await expectHighlight("line 42", in: pane)
        // Centered, it sits rows above herdr's last row: herdr scrolled up to it.
        try await expect("herdr to center the match") { try await scrollOffset(pane) > 0 }
        // Its card leaving view closes it, and herdr's shared viewport goes back to the bottom.
        element("tab.w2:t1").click()
        XCTAssertTrue(field.vanishes(within: 2))
        try await expect("herdr back at the bottom") { try await scrollOffset(pane) == 0 }
    }

    /// A new tab in view, its card with the keyboard, after `line 1` to `line 200`: its pane.
    private func twoHundredLines(_ label: String) async throws -> String {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab(label)
        element("tab.\(tab)").click()
        try await send("for i in $(seq 1 200); do echo line $i; done\r", to: pane)
        try await waitFor(pane) { $0.contains("\nline 200\n") }
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)")))
        return pane
    }

    /// The rows herdr shows the text on are highlighted, the lowest one as the selected match.
    private func expectHighlight(_ text: String, in pane: String) async throws {
        let lit = element("find.highlights")
        var expected = ""
        do {
            try await expect("the highlights") {
                let rows = try await read(pane).split(separator: "\n", omittingEmptySubsequences: false)
                let last = rows.lastIndex { $0 == text }.map(String.init) ?? "none"
                expected = "\(rows.count { $0 == text }) shown, current row \(last)"
                return lit.stringValue == expected
            }
        } catch is Waited {
            throw Waited(description: "expected \(expected); the highlights say \(lit.stringValue)")
        }
    }

    func testCommandClickOnALinkOpensIt() async throws {
        relaunch(one, ["-recordLinks", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("link")
        element("tab.\(tab)").click()
        try await send("clear; echo ftp://example.com/x; echo https://example.com/oriel\r", to: pane)
        try await waitFor(pane) { $0.hasPrefix("ftp://example.com/x\nhttps://example.com/oriel\n") }

        // ⌘-click the sixth cell of each line: only the https link opens.
        let terminal = element("terminal.\(pane)")
        let grid = try XCTUnwrap(terminal.value as? String).split(separator: " ").compactMap { Double($0) }
        let cell = CGSize(width: terminal.frame.width / grid[1], height: terminal.frame.height / grid[0])
        for row in [0.5, 1.5] {
            let link = terminal.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: cell.width * 5.5, dy: cell.height * row))
            link.hover()
            XCUIElement.perform(withKeyModifiers: .command) { link.click() }
        }
        XCTAssertTrue(element("app.links").has(\.stringValue, "https://example.com/oriel", within: 2))
    }

    /// A card opened for the first time shows its terminal only once herdr's frames settled at the card's size: the
    /// program's redraw for the resize is in by then (no flicker of herdr's resize).
    func testCardShowsItsTerminalOnceHerdrDrewItAtItsSize() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("ready")
        // An 80 × 24 PTY (another client's attach), and a shell that prints its size when it changes.
        let terminal = try await terminalID(pane)
        try await Self.post("\(one)/control", Data(terminal.utf8))
        try await send("trap 'echo resized $(stty size)' WINCH\r", to: pane)
        try await waitFor(pane) { $0.contains("WINCH") }

        element("tab.\(tab)").click()
        let card = element("pane.\(pane)")
        XCTAssertTrue(card.exists(within: 3))
        try await expect("\(pane) ready, it says \(card.stringValue)", times: 100) {
            card.stringValue.hasPrefix("content") && !card.stringValue.hasSuffix(", loading")
        }
        // At once: the redraw at the card's grid was in before the card showed.
        let grid = try XCTUnwrap(element("terminal.\(pane)").value as? String)
        let screen = try await read(pane)
        XCTAssertTrue(screen.contains("resized \(grid)"), "card \(grid), screen:\n\(screen)")
    }

    /// herdr is asked what every pane runs on the first snapshot, also in tabs never shown.
    func testNeverShownTabsCardNamesItsProgram() async throws {
        let capsule = element("tab.w1:t2")
        XCTAssertTrue(capsule.exists(within: connect))
        XCTAssertFalse(capsule.isSelected)
        let names = try await foreground("w1:p4")
        let program = try XCTUnwrap(names.first)
        capsule.hover()
        let row = element("hovercard.w1:p4")
        XCTAssertTrue(row.exists(within: 2))
        XCTAssertTrue(until(3) { row.label.hasPrefix("\(program), ") }, "\(row.label), not \(program)")
    }

    func testFoldersDroppedOnTheDockOpenWorkspaces() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // The app beside the test runner, as the Dock opens it.
        let oriel = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Oriel.app").path
        let warm = try await dropFolder(oriel)
        let opened = try await workspace(in: warm)
        XCTAssertTrue(element("workspace.\(opened)").has(\.isSelected, true, within: 3))
        XCTAssertEqual(app.windows.count, 1)

        // A drop that starts the app opens one window and the workspace in it.
        app.terminate()
        let cold = try await dropFolder(oriel)
        let relaunched = XCUIApplication(bundleIdentifier: "dev.hkandala.oriel")
        addTeardownBlock { relaunched.terminate() }
        // The launch connects first (login shell, herdr checks): slow on CI.
        let started = try await workspace(in: cold, times: Int(connect * 10))
        XCTAssertTrue(relaunched.descendants(matching: .any)["workspace.\(started)"].has(\.isSelected, true,
                                                                                         within: connect))
        XCTAssertEqual(relaunched.windows.count, 1)
    }

    /// The helper opens a new folder with the app, as a drop on the Dock icon does: its path.
    private func dropFolder(_ oriel: String) async throws -> String {
        try await String(decoding: Self.post("\(one)/open-folder", Data(oriel.utf8)), as: UTF8.self)
    }

    /// The workspace herdr made in the folder (its pane's cwd), closed after the test.
    private func workspace(in folder: String, times: Int = 50) async throws -> String {
        let name = (folder as NSString).lastPathComponent
        let id = try await poll("a workspace in \(name)", times: times) { () async throws -> String? in
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            return panes.first { ($0["cwd"] as? String)?.hasSuffix(name) == true }?["workspace_id"] as? String
        }
        closeAfter("workspace", id)
        return id
    }

    /// herdr's viewport of the pane, in lines from the bottom.
    private func scrollOffset(_ pane: String) async throws -> Int {
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        let scroll = panes.first { $0["pane_id"] as? String == pane }?["scroll"] as? [String: Any]
        return try field(scroll?["offset_from_bottom"], "\(pane)'s scroll offset")
    }
}
