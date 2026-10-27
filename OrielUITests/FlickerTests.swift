import XCTest

extension OrielUITests {
    /// A tab comes into view in every way: from the change on, each of its cards shows its last
    /// picture, then herdr's screen, and nothing between. The app records each commit (`-recordFrames`): no card gone,
    /// blank, fading, with a third picture or moved. Every tab is shown once first: a new card's first reveal fades in
    /// on purpose. w1's second tab is a middle one (of three), shown whenever a new strip comes (a workspace, a
    /// session, the overview): an empty strip drew its first page, then jumped there.
    func testATabComesIntoViewWithoutAFlicker() async throws {
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        _ = try await newTab("third", in: "w1")
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4", "w2:p1"] {
            try await fill(pane)
        }
        openPage(two)
        // Keys for the tabs: right after a session change a click went beside the capsule (CI).
        for (act, panes) in [(click("sidebar.dot.\(one)"), ["w1:p1"]), (key("2"), ["w1:p4"]),
                             (click("workspace.w2"), ["w2:p1"]), (click("workspace.w1"), ["w1:p4"]),
                             (key("1"), ["w1:p1", "w1:p2", "w1:p3"])]
        {
            act()
            try await expectText(panes, "warm-up")
        }
        // The last change's record is done.
        try await Task.sleep(for: .seconds(2))
        try await expectNoFlicker()
    }

    /// The flicker test's share in every run (it runs on demand, the Makefile's ON_DEMAND): a tab shown by its capsule
    /// and back, recorded.
    func testATabClickComesIntoViewWithoutAFlicker() async throws {
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4"] {
            try await fill(pane)
        }
        // Each tab shown once first: a new card's first reveal fades in on purpose.
        element("tab.w1:t2").click()
        try await expectText(["w1:p4"], "warm-up")
        element("tab.w1:t1").click()
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "warm-up")
        try await Task.sleep(for: .seconds(2))
        let records = try await [frames("tab click", click("tab.w1:t2")), frames("tab click back", click("tab.w1:t1"))]
        XCTAssertTrue(records.allSatisfy { !$0.contains(#/ [1-9][0-9]*\//#) }, "\(records)")
    }

    /// A card never shows a picture smaller than its pixels: a tab only the overview showed keeps
    /// the overview's small snapshot, and shown in the strip afterwards (by its capsule, or by the zoom right after its
    /// tile turned live again), it showed that blurred until it drew. Now it shows its fill and fades in.
    func testACardNeverShowsTheOverviewsSmallSnapshot() async throws {
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        var records: [String] = []
        for (name, zooms) in [("capsule after the overview", false), ("zoom after the overview", true)] {
            let (tab, pane) = try await newTab(name, in: "w1")
            try await fill(pane)
            // Its tile turns live and draws; Esc: it lets go and keeps its snapshot.
            app.typeKey("o", modifierFlags: [.command, .control])
            let card = element("overview.card.\(pane)"), tile = element("overview.tab.\(tab)")
            XCTAssertTrue(until(5) { card.stringValue.hasPrefix("live") }, "\(card.exists) '\(card.stringValue)'")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("overview").vanishes(within: 2))
            try await Task.sleep(for: .seconds(2))
            try await records.append(frames(name) {
                if zooms {
                    self.app.typeKey("o", modifierFlags: [.command, .control])
                    XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
                    tile.click()
                } else {
                    self.element("tab.\(tab)").click()
                }
            })
            element("tab.w1:t1").click()
        }
        keep(records.joined(separator: "\n"), as: "frames")
        // The codes of bad commits come last: `s`, a small still.
        let blurred = records.filter { $0.split(separator: " ").last?.contains("s") == true }
        XCTAssertTrue(blurred.isEmpty, "\(blurred) of \(records)")
    }

    /// Each way to show another tab, recorded (`frames`): none may flicker.
    private func expectNoFlicker() async throws {
        var records: [String] = []
        let option: XCUIElement.KeyModifierFlags = [.command, .option]
        for (name, act) in [
            ("tab click", click("tab.w1:t2")), ("tab click back", click("tab.w1:t1")), ("tab key", key("2")),
            ("workspace", click("workspace.w2")), ("workspace back", click("workspace.w1")),
            ("session dot", click("sidebar.dot.\(two)")), ("session dot back", click("sidebar.dot.\(one)")),
            ("next session key", key("]", option)), ("previous session key", key("[", option)),
        ] {
            try await records.append(frames(name, act))
        }
        let sidebar = element("sidebar"), swipe = "\(one)/swipe", center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        // Either way, by natural scrolling: a swipe that turns no page records nothing.
        for (name, step) in [("session swipe", -10), ("session swipe back", 10)] {
            try await records.append(frames(name, swiped: true) {
                try await Self.post(swipe, Data("\(center) \(step) 14".utf8))
            })
        }
        XCTAssertTrue(records.suffix(2).contains { $0.contains("/") }, "no swipe changed the session: \(records)")
        element("sidebar.dot.\(one)").click()
        try await Task.sleep(for: .seconds(2))
        try await records.append(frames("tab key back", key("1")))
        for name in ["overview zoom into another tab", "overview zoom into the shown tab"] {
            try await records.append(frames(name) {
                self.app.typeKey("o", modifierFlags: [.command, .control])
                let tile = self.element("overview.tab.w1:t2")
                XCTAssertTrue(tile.has(\.isHittable, true, within: 3))
                tile.click()
                // The zoom's 0.18 s, before the record's 1.5 s.
                try await Task.sleep(for: .seconds(0.5))
            })
        }
        // The tab's cards take the new size once shown: their terminals hold their grid and redraw at the new one.
        for (name, tab) in [("tab after the sidebar hid", "1"), ("tab after the sidebar showed", "2")] {
            element("titlebar.sidebar").click()
            try await Task.sleep(for: .seconds(1))
            try await records.append(frames(name, key(tab)))
        }
        keep(records.joined(separator: "\n"), as: "frames")
        let flickers = records.filter { $0.contains(#/ [1-9][0-9]*\//#) }
        XCTAssertTrue(flickers.isEmpty, "\(flickers) of \(records)")
    }

    /// The app's frame record (`-recordFrames`) of the change `act` makes, named: one, or none for a swipe that turned
    /// no page.
    private func frames(_ name: String, swiped: Bool = false, _ act: () async throws -> Void) async throws -> String {
        let probe = element("app.frames"), before = probe.stringValue.split(separator: "; ").count
        try await act()
        // No accessibility query until the record is done: each one holds the app's main thread (up to 240 ms), which
        // moves the commits' timing.
        try await Task.sleep(for: .seconds(2))
        let new = probe.stringValue.split(separator: "; ").dropFirst(before)
        XCTAssertTrue(new.count == 1 || swiped && new.isEmpty, "\(name): \(new)")
        return "\(name): " + new.joined(separator: ", ")
    }

    private func click(_ id: String) -> () -> Void {
        { self.element(id).click() }
    }

    private func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags = .command) -> () -> Void {
        { self.app.typeKey(key, modifierFlags: flags) }
    }
}
