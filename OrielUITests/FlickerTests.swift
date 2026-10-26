import XCTest

/// A tab coming into view never flickers (phase 29, lane T), read from the app's own record of each display frame.
extension OrielUITests {
    /// A tab comes into view in every way (phase 29, lane T): from the change on, each of its cards shows its last
    /// picture, then herdr's screen, and nothing between. The app records each display frame (`-recordFrames`): no
    /// card gone, blank, fading, with a third picture or moved. Every tab is shown once first: a new card's first
    /// reveal fades in on purpose.
    func testATabComesIntoViewWithoutAFlicker() async throws {
        relaunch(one, ["-recordFrames", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4", "w2:p1"] {
            try await fill(pane)
        }
        openPage(two)
        // Each tab once; keys for the tabs: right after a session change a click went beside the capsule (CI).
        for (id, panes) in [("sidebar.dot.\(one)", ["w1:p1"]), ("2", ["w1:p4"]), ("workspace.w2", ["w2:p1"]),
                            ("workspace.w1", ["w1:p4"]), ("1", ["w1:p1", "w1:p2", "w1:p3"])]
        {
            if id.count == 1 {
                app.typeKey(id, modifierFlags: .command)
            } else {
                element(id).click()
            }
            try await expectText(panes, id)
        }
        try await expectNoFlicker()
    }

    /// Each way to show another tab, recorded (`frames`): none may flicker. The second tab is the one shown when a
    /// new strip comes (a workspace, a session, the overview): an empty strip drew its first page first.
    private func expectNoFlicker() async throws {
        var records: [String] = []
        let click = { (id: String) in { self.element(id).click() } }
        let key = { (key: String, flags: XCUIElement.KeyModifierFlags) in
            { self.app.typeKey(key, modifierFlags: flags) }
        }
        for (name, act) in [
            ("tab click", click("tab.w1:t2")), ("tab click back", click("tab.w1:t1")), ("tab key", key("2", .command)),
            ("workspace", click("workspace.w2")), ("workspace back", click("workspace.w1")),
            ("session dot", click("sidebar.dot.\(two)")), ("session dot back", click("sidebar.dot.\(one)")),
            ("next session key", key("]", [.command, .option])), (
                "previous session key",
                key("[", [.command, .option]),
            ),
        ] {
            try await records.append(frames(name, act))
        }
        let sidebar = element("sidebar"), center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        // Either way, by natural scrolling: a swipe that turns no page records nothing.
        for (name, step) in [("session swipe", -10), ("session swipe back", 10)] {
            try await records.append(frames(name) { try await Self.post(
                "\(self.one)/swipe",
                Data("\(center) \(step) 14".utf8),
            ) })
        }
        if header != one {
            element("sidebar.dot.\(one)").click()
        }
        try await records.append(frames("tab key back", key("1", .command)))
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
        for (name, key) in [("tab after the sidebar hid", "1"), ("tab after the sidebar showed", "2")] {
            element("titlebar.sidebar").click()
            try await Task.sleep(for: .seconds(1))
            try await records.append(frames(name) { self.app.typeKey(key, modifierFlags: .command) })
        }
        let attachment = XCTAttachment(string: records.joined(separator: "\n"))
        attachment.name = "frames"
        attachment.lifetime = .keepAlways
        add(attachment)
        let flickers = records.filter { $0.contains(#/ [1-9][0-9]*\//#) }
        XCTAssertTrue(flickers.isEmpty, "\(flickers) of \(records)")
    }

    /// The app's frame records (`-recordFrames`) of the changes `act` makes, named.
    private func frames(_ name: String, _ act: () async throws -> Void) async throws -> String {
        let probe = element("app.frames"), before = probe.stringValue.split(separator: "; ").count
        try await act()
        // No accessibility query until the record is done: each one holds the app's main thread (up to 240 ms), and
        // the frames meanwhile go unrecorded.
        try await Task.sleep(for: .seconds(2))
        return "\(name): " + probe.stringValue.split(separator: "; ").dropFirst(before).joined(separator: ", ")
    }
}
