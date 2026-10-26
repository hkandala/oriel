import XCTest

/// The overview (phase 27, D70): every tab of the session as a live miniature, grouped by workspace.
extension OrielUITests {
    /// ⌃⌘O hides the sidebar, the tab bar and every title-row button but one ×, and shows a tile per tab under its
    /// workspace, two a row on CI's window, with wide margins; a tab never shown draws live in its tile; × closes a
    /// tab; a click shows that tab, its terminals at their size; Esc and the title row's × leave too.
    func testOverviewShowsEveryTabLiveAndOpensOne() async throws {
        // The zoom runs, for the recording, and its miniature's sizes are counted.
        relaunch(nil, ["-forceMotion", "YES", "-recordMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (closing, _) = try await newTab("closing", in: "w1")
        // A white block in w2's pane, which no card showed yet.
        let block = "clear; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await send("\(block); echo block-$((6*7))\r", to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\nblock-42") }

        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview")
        XCTAssertTrue(overview.exists(within: 2))
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        XCTAssertFalse(element("tab.w1:t1").exists)
        // × on hover closes the tab, as on the tab bar (an idle shell: no question). First: its row pushed w2 below
        // CI's window.
        element("overview.tab.\(closing)").hover()
        element("overview.tab.\(closing).close").click()
        XCTAssertTrue(element("overview.tab.\(closing)").vanishes(within: 3))
        try await expect("herdr closed \(closing)") { try await !Self.ids("tab", in: one).contains(closing) }
        for id in ["overview.workspace.w1", "overview.workspace.w2", "overview.tab.w1:t1", "overview.tab.w1:t2",
                   "overview.tab.w2:t1"]
        {
            XCTAssertTrue(element(id).exists(within: 2), id)
        }
        // The session's title, then each workspace's name over its tiles, two a row.
        XCTAssertEqual(element("overview.title").stringValue, one)
        XCTAssertLessThan(element("overview.workspace.w2").frame.maxY, element("overview.tab.w2:t1").frame.minY)
        let first = element("overview.tab.w1:t1").frame, second = element("overview.tab.w1:t2").frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertEqual(second.minX - first.maxX, 16, accuracy: 1)
        expectOverviewChrome(first: first, second: second)
        XCTAssertEqual(element("overview.tab.w1:t1").stringValue, "selected")
        keepScreenshot("overview")
        let tile = element("overview.tab.w2:t1"), dark = element("overview.tab.w1:t2")
        XCTAssertTrue(until(3) { mean(tile) > mean(dark) + 30 }, "\(mean(tile)) \(mean(dark))")

        tile.click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(element("sidebar").exists(within: 2))
        XCTAssertTrue(element("tab.w2:t1").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.w2:p1")))
        try await expectPTYSize("w2:p1")

        element("titlebar.overview").click()
        XCTAssertTrue(overview.exists(within: 2))
        XCTAssertEqual(element("overview.tab.w2:t1").stringValue, "selected")
        // The zoom grew its miniature frame by frame (a jump takes one or two sizes).
        XCTAssertGreaterThanOrEqual(Int(element("overview.motion").stringValue) ?? 0, 4)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.w2:p1")))

        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(overview.exists(within: 2))
        element("overview.close").click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(element("titlebar.overview").exists(within: 2))
    }

    /// A zoom into a tab the strip never showed (phase 29 item 5), then into the shown one: once the zoom ends, its
    /// card shows at once and never goes back to loading (the user saw it flicker).
    func testOverviewZoomIntoAnUnshownTabShowsItSteadily() async throws {
        relaunch(nil, ["-forceMotion", "YES", "-recordMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("unshown", in: "w1")
        try await send("seq 1 40\r", to: pane)
        for round in ["unshown", "shown"] {
            app.typeKey("o", modifierFlags: [.command, .control])
            let overview = element("overview"), tile = element("overview.tab.\(tab)")
            XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
            tile.click()
            XCTAssertTrue(overview.vanishes(within: 2))
            let card = element("pane.\(pane)")
            var values: [String] = []
            let end = Date.now + 1.5
            while Date.now < end {
                values.append(card.stringValue)
            }
            print("zoom, \(round): \(values) host \(element("host.\(pane)").label)")
            XCTAssertFalse(values.contains { $0.contains("loading") }, "\(round): \(values)")
        }
    }

    /// The title row has the traffic lights and one × only; the grid (its first row's two tiles) is centered with wide
    /// margins all round: 8 % of the width, at least 48 pt, and 40 pt above.
    private func expectOverviewChrome(first: CGRect, second: CGRect) {
        for id in ["titlebar.sidebar", "titlebar.machine", "titlebar.agents", "titlebar.overview", "titlebar.palette",
                   "titlebar.new-tab"]
        {
            XCTAssertFalse(element(id).exists, id)
        }
        let canvas = element("overview").frame, title = element("overview.title").frame
        XCTAssertEqual(first.minX - canvas.minX, max(48, canvas.width * 0.08), accuracy: 1)
        XCTAssertEqual(canvas.maxX - second.maxX, first.minX - canvas.minX, accuracy: 1)
        XCTAssertEqual(title.minY - canvas.minY, 40, accuracy: 2)
    }

    /// Sideways, the overview pages through the window's sessions, and the page it lands on is the window's; a click
    /// there shows that session's tab.
    func testOverviewSwipesBetweenSessions() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        _ = openSessionPanel()
        app.typeText(two)
        element("open-session.session.\(two)").click()
        XCTAssertTrue(until(3) { header == two })
        app.typeKey("[", modifierFlags: [.command, .option])
        XCTAssertTrue(until(3) { header == one })
        // A tab of session two no card showed, with the id of one of session one's (w1:t2): it draws live there.
        let created = try await Self.call(two, "tab.create", ["workspace_id": "w1", "cwd": "/tmp", "focus": false])
        let tab = try id(created, "tab"), pane = try id(created, "root_pane")
        addTeardownBlock { [two] in _ = try? await Self.call(two, "tab.close", ["tab_id": tab]) }
        let block = "clear; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await Self.call(two, "pane.send_text", ["pane_id": pane, "text": "\(block)\r"])

        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview"), window = app.windows.firstMatch
        XCTAssertTrue(element("overview.page.\(one)").exists(within: 2))
        try await swipe(overview, until: element("overview.page.\(two)"), \.exists, true)
        XCTAssertTrue(until(3) { window.title.hasSuffix(" - \(two)") }, window.title)
        XCTAssertFalse(element("overview.page.\(one)").exists)
        keepScreenshot("overview of session two")
        let live = element("overview.tab.\(tab)"), dark = element("overview.tab.w1:t1")
        XCTAssertTrue(until(3) { mean(live) > mean(dark) + 30 }, "\(mean(live)) \(mean(dark))")
        dark.click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(until(3) { header == two })

        // Without motion (CI's Reduce Motion), Esc leaves at once and the keyboard is back in the card.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(overview.exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))
    }

    /// What the overview costs (phase 27): lane O's workspace of 6 tabs and 12 panes, 8 of them printing, only its
    /// first tab shown. Open, every tile's cards stream and draw, also those scrolled out of view, so scrolling shows
    /// them at once (phase 28); closed, the ones only it showed let go (no visits, D46). Footprint and CPU of each step
    /// are in the result bundle.
    func testOverviewCostsAndLetsGoAfter() async throws {
        let (tabs, _) = try await newWorkspace("usage", tabs: 6)
        var panes: [String] = []
        for (index, tab) in tabs.enumerated() {
            var last = try await pane(of: tab)
            panes.append(last)
            for _ in 0 ..< index % 3 {
                last = try await split(last)
                panes.append(last)
            }
        }
        for pane in panes.dropFirst(4) {
            try await waitForPrompt(pane)
            try await send("while :; do echo $RANDOM $RANDOM $RANDOM $RANDOM; sleep 0.1; done\r", to: pane)
        }
        let strip = try await measure("strip")
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 2))
        // Every card of the session streams, the tiles below the window's edge too.
        let cards = try await Self.ids("pane", in: one).count
        try await poll("every card to stream") { () async throws -> Int? in
            let count = try await helpers(measure("overview", seconds: 1))
            return count >= cards ? count : nil
        }
        let open = try await measure("overview")
        // The last tile, below the window's edge, already has its terminal drawing (a grid comes with its surface).
        let last = element("overview.tab.\(tabs[5])"), terminal = element("terminal.\(panes[panes.count - 1])")
        XCTAssertFalse(last.isHittable)
        XCTAssertTrue(until(3) { !terminal.stringValue.isEmpty }, "no surface below the edge")
        // Down to the new workspace's tiles: none lets go.
        // Either way: the sign follows the natural scrolling setting.
        for delta in [-3000.0, 3000, -3000] where !(last.exists && last.isHittable) {
            element("overview").scroll(byDeltaX: 0, deltaY: delta)
            _ = last.has(\.isHittable, true, within: 1)
        }
        XCTAssertTrue(last.isHittable)
        keepScreenshot("overview of 6 tabs")
        let scrolled = try await measure("overview, scrolled")
        XCTAssertGreaterThanOrEqual(helpers(scrolled), cards, scrolled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        try await poll("the overview's streams to end") { () async throws -> Int? in
            let count = try await helpers(measure("after", seconds: 1))
            return count == helpers(strip) ? count : nil
        }
        _ = try await measure("after the overview")
        print("overview cost: strip\n\(strip)\nopen\n\(open)\nscrolled\n\(scrolled)")
    }

    /// The mean brightness of an element's pixels.
    func mean(_ element: XCUIElement) -> Int {
        let brightness = Self.brightness(element.screenshot().image)
        return brightness.isEmpty ? 0 : brightness.reduce(0, +) / brightness.count
    }
}
