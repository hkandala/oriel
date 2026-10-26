import XCTest

/// The overview (phase 27, D70): every tab of the session as a live miniature, grouped by workspace.
extension OrielUITests {
    /// ⌃⌘O hides the sidebar, the tab bar and every title-row button but one ×, and shows a tile per tab under its
    /// workspace, two a row on CI's window, with wide margins; a tab never shown draws live in its tile; × closes a
    /// tab; a click shows that tab, its terminals at their size; Esc and the title row's × leave too.
    func testOverviewShowsEveryTabLiveAndOpensOne() async throws {
        // The zoom runs, for the recording, and its miniature's sizes are counted.
        relaunch(nil, ["-forceMotion", "YES", "-recordMotion", "YES", "-recordLatency", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (closing, _) = try await newTab("closing", in: "w1")
        let made = sidebarsMade
        // A white block in w2's pane, which no card showed yet.
        let block = "clear; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await send("\(block); echo block-$((6*7))\r", to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\nblock-42") }

        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview")
        XCTAssertTrue(overview.exists(within: 2))
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        XCTAssertFalse(element("tab.w1:t1").exists)
        // × on hover closes the tab, as on the tab bar (an idle shell: no question).
        element("overview.tab.\(closing)").hover()
        element("overview.tab.\(closing).close").click()
        XCTAssertTrue(element("overview.tab.\(closing)").vanishes(within: 3))
        try await expect("herdr closed \(closing)") { try await !Self.ids("tab", in: one).contains(closing) }
        for id in ["overview.workspace.w1", "overview.workspace.w2", "overview.tab.w1:t1", "overview.tab.w1:t2"] {
            XCTAssertTrue(element(id).exists(within: 2), id)
        }
        // The session's title, then each workspace's name over its tiles, two a row.
        XCTAssertEqual(element("overview.title").stringValue, one)
        let first = element("overview.tab.w1:t1").frame, second = element("overview.tab.w1:t2").frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertEqual(second.minX - first.maxX, 16, accuracy: 1)
        expectOverviewChrome(first: first, second: second)
        XCTAssertEqual(element("overview.tab.w1:t1").stringValue, "selected")
        keepScreenshot("overview")
        // w2's row is below CI's window: the lazy rows make it as it scrolls in, and it turns live.
        let tile = element("overview.tab.w2:t1")
        scrollOverview(to: tile)
        XCTAssertLessThan(element("overview.workspace.w2").frame.maxY, tile.frame.minY)
        XCTAssertTrue(until(3) { mean(tile) > 60 }, "\(mean(tile))")

        tile.click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(element("sidebar").exists(within: 2))
        // The sidebar stayed under the overview and faded in with the zoom; made after it, it came late (phase 30).
        XCTAssertEqual(sidebarsMade, made)
        XCTAssertTrue(element("tab.w2:t1").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.w2:p1")))
        try await expectPTYSize("w2:p1")

        element("titlebar.overview").click()
        XCTAssertTrue(overview.exists(within: 2))
        scrollOverview(to: tile)
        XCTAssertEqual(tile.stringValue, "selected")
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

    /// Tiles with nothing to show yet show a loader, and each tile in view gets its picture in turn (phase 30): two
    /// never shown tabs of 9 panes each, side by side, more than the 16 live cards together. Before, the one past the
    /// cap stayed blank as long as it was in view.
    func testOverviewLoadsEveryTileInTurn() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (first, root) = try await createWorkspace("loads")
        let second = try await Self.call(one, "tab.create", ["workspace_id": workspace(of: first), "cwd": "/tmp",
                                                             "focus": false])
        var panes: [String] = []
        for pane in try [root, id(second, "root_pane")] {
            var last = pane
            panes.append(last)
            for index in 0 ..< 8 {
                last = try await split(last, index.isMultiple(of: 2) ? "right" : "down")
                panes.append(last)
            }
        }
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = try element("overview.tab.\(id(second, "tab"))")
        scrollOverview(to: tile)
        // The second waits for the first's cards to draw, with a loader meanwhile.
        XCTAssertTrue(try element("overview.tab.\(id(second, "tab")).loading").exists(within: 2))
        let cards = panes.map { element("overview.card.\($0)") }
        try await poll("every card to draw", times: 150) { () -> Bool? in
            cards.allSatisfy { !$0.stringValue.hasPrefix("loading") } ? true : nil
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
        let side = max(48, canvas.width * 0.08), columns = CGFloat(min(
            4,
            max(2, Int((canvas.width - 2 * side + 16) / 356)),
        ))
        XCTAssertEqual(first.minX - canvas.minX, side, accuracy: 1)
        // The grid's right edge: as many tiles as fit a row, full or not.
        XCTAssertEqual(canvas.maxX - (first.minX + columns * second.width + (columns - 1) * 16), side, accuracy: 2)
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
    /// first tab shown. Open, the cards of the tiles it lays out stream and draw; closed, the ones only it showed let
    /// go (no visits, D46). Footprint and CPU of each step are in the result bundle.
    func testOverviewCostsAndLetsGoAfter() async throws {
        let (tabs, _) = try await newWorkspace("usage", tabs: 6)
        var panes: [String] = []
        for (index, tab) in tabs.enumerated() {
            var last = try await pane(of: tab)
            panes.append(last)
            // The second tab's one card is wide enough to tell its snapshot's size at 1x (below).
            for _ in 0 ..< (index + 2) % 3 {
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
        // The tiles laid out (in or near view: the grid is lazy) stream their cards too.
        try await poll("the tiles' cards to stream") { () async throws -> Int? in
            let count = try await helpers(measure("overview", seconds: 1))
            return count > helpers(strip) ? count : nil
        }
        let open = try await measure("overview")
        // Down to the new workspace's tiles: those in view stream, the ones scrolled away let go. Either way: the
        // sign follows the natural scrolling setting.
        let last = element("overview.tab.\(tabs[5])")
        for delta in [-3000.0, 3000, -3000] where !(last.exists && last.isHittable) {
            element("overview").scroll(byDeltaX: 0, deltaY: delta)
            _ = last.has(\.isHittable, true, within: 1)
        }
        XCTAssertTrue(last.isHittable)
        keepScreenshot("overview of 6 tabs")
        let scrolled = try await measure("overview, scrolled")
        // The strip's kept terminals, at most 16 cards, and a run or two ending.
        XCTAssertLessThanOrEqual(helpers(scrolled), helpers(strip) + 16 + 2, scrolled)
        // Back up: the second tab's card, live on the way down, shows its snapshot or its terminal at once, never the
        // bare fill.
        let card = element("overview.card.\(panes[3])")
        scrollOverview(to: element("overview.tab.\(tabs[1])"), step: 3000, steps: 1)
        XCTAssertTrue(card.exists)
        XCTAssertFalse(card.stringValue.hasPrefix("loading"), card.stringValue)
        // Its snapshot at the tile's pixel size (phase 30): "‹live or snapshot› ‹its width in pixels›".
        let width = Double(card.stringValue.split(separator: " ").last ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(width, card.frame.width * (NSScreen.main?.backingScaleFactor ?? 1) - 2,
                                    card.stringValue)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        try await poll("the overview's streams to end") { () async throws -> Int? in
            let count = try await helpers(measure("after", seconds: 1))
            return count == helpers(strip) ? count : nil
        }
        _ = try await measure("after the overview")
        print("overview cost: strip\n\(strip)\nopen\n\(open)\nscrolled\n\(scrolled)")
    }

    /// The overview of 200 tabs over 8 workspaces, 272 panes, 50 of them agents and half the rest printing
    /// (`scripts/stress.py`, phase 28): while trackpad scrolls go through it, at most 16 cards stream beside the
    /// strip's, the tiles that were live keep a snapshot, and the footprint stays bounded. Footprint, CPU, the frames
    /// dropped while scrolling (`app.latency`) and the main thread's profile are in the result bundle.
    func testOverviewOfManyTabsStaysBounded() async throws {
        executionTimeAllowance = 600
        let eight = try env("ORIEL_SESSION8")
        addTeardownBlock { _ = try? await Self.post("\(eight)/stress") }
        _ = try await Self.post("\(eight)/stress", Data("200 8 272 50".utf8))
        relaunch(eight, ["-recordMotion", "YES", "-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("pane.w1:p1").exists(within: 120))
        try await Task.sleep(for: .seconds(5))
        let strip = try await measure("strip, 200 tabs", seconds: 5, session: eight)
        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview")
        XCTAssertTrue(overview.exists(within: 5))
        _ = try await measure("overview, 200 tabs", seconds: 5, session: eight)
        let frame = overview.frame
        // Down, the sign following the natural scrolling setting: 20 swipes of 600 pt and their momentum, each a
        // "scroll ‹frames› ‹hitches›" record in `app.latency`.
        var sign = -1.0, most = 0
        for index in 0 ..< 20 {
            try await Self.post("\(one)/swipe", Data("\(frame.midX) \(frame.midY) \(30 * sign) 20 0 1".utf8))
            if index == 0, element("overview.title").isHittable {
                sign = -sign
            }
            most = try await max(most, streams(eight).count)
        }
        // The main thread's profile while it scrolls back.
        async let profile = Self.post("\(eight)/sample", Data("3".utf8))
        for _ in 0 ..< 4 {
            try await Self.post("\(one)/swipe", Data("\(frame.midX) \(frame.midY) \(-30 * sign) 20 0 1".utf8))
        }
        let sampled = try await XCTAttachment(string: String(decoding: profile, as: UTF8.self))
        sampled.name = "sample, overview scrolling"
        sampled.lifetime = .keepAlways
        add(sampled)
        let scrolled = try await measure("overview, 200 tabs, scrolled", seconds: 5, session: eight)
        // "‹live cards› ‹snapshots›".
        let snapshots = element("overview.snapshots").stringValue
        note("overview: most runs \(most), live and snapshots \(snapshots)")
        // The strip's kept terminals, at most 16 cards, and a run or two ending.
        XCTAssertLessThanOrEqual(most, helpers(strip) + 16 + 2, "\(most) runs")
        XCTAssertGreaterThan(Int(snapshots.split(separator: " ").last ?? "") ?? 0, 8, snapshots)
        // Bounded by the live cap, whatever the tab count: 16 full-window cards are about 1.1 GB on Retina.
        XCTAssertLessThan(footprint(scrolled), footprint(strip) + 1600, scrolled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
    }

    /// How many times the sidebar was made (`-recordLatency`).
    var sidebarsMade: Int {
        element("app.latency").stringValue.components(separatedBy: "sidebar made").count
    }

    /// The footprint in a `usage` report, in MB.
    func footprint(_ usage: String) -> Int {
        usage.firstMatch(of: /Footprint: (\d+) MB/).flatMap { Int($0.1) } ?? .max
    }

    /// Scrolls the overview until the element is hittable, `step` at a time; either way, as the sign follows the
    /// natural scrolling setting.
    func scrollOverview(to target: XCUIElement, step: Double = 300, steps: Int = 10) {
        for delta in [-step, step, -step] {
            for _ in 0 ..< steps where !(target.exists && target.isHittable) {
                element("overview").scroll(byDeltaX: 0, deltaY: delta)
            }
        }
    }

    /// The mean brightness of an element's pixels.
    func mean(_ element: XCUIElement) -> Int {
        let brightness = Self.brightness(element.screenshot().image)
        return brightness.isEmpty ? 0 : brightness.reduce(0, +) / brightness.count
    }
}
