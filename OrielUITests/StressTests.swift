import XCTest

/// The whole UI at scale (phase 29, item 14): a session of 30 workspaces, 300 tabs and 600 panes (400 on a Mac that is
/// not CI's, whose terminals the user's programs share), 100 of them agents that print, retitle and change state, and
/// half the others printing (`scripts/stress.py`). It records the main keys' time to their frame, the frames while the
/// sidebar, the tab bar and the Agents view scroll, the app's CPU and memory, and the main thread's work every 5 s:
/// all in the result bundle ("latency", "usage, …", "sample").
extension OrielUITests {
    func testHundredsOfPanesStayQuick() async throws {
        executionTimeAllowance = 600
        let eight = try env("ORIEL_SESSION8")
        addTeardownBlock { _ = try? await Self.post("\(eight)/stress") }
        let made = try await String(decoding: Self.post("\(eight)/stress", Data("300 30 600 100".utf8)), as: UTF8.self)
        print(made)
        // From the launch to the first card drawn: before phase 29 it stayed blank past 30 s on CI.
        let launched = Date.now
        relaunch(eight, ["-recordLatency", "YES"])
        // Also after a failed step.
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("pane.w1:p1").exists(within: 120))
        note("connect \(Int(Date.now.timeIntervalSince(launched) * 1000))ms")
        // The first snapshot's program asks (one per pane), and the agents' first states.
        try await Task.sleep(for: .seconds(10))

        let palette = element("palette.filter"), openSession = element("open-session.filter")
        let escape = XCUIKeyboardKey.escape.rawValue
        key("k", .command) { palette.exists }
        key(escape, []) { !palette.exists }
        key("t", [.command, .option]) { openSession.exists }
        key(escape, []) { !openSession.exists }
        key("2", .command) { self.element("tab.w1:t2").isSelected }
        key("1", .command) { self.element("tab.w1:t1").isSelected }
        key("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        key("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        key("s", [.command, .control]) { !self.element("sidebar").exists }
        key("s", [.command, .control]) { self.element("sidebar").exists }
        key(".", .command) { self.element("agents.sort").exists }

        // Frames while lists scroll: the Agents view's 100 rows, the sidebar's 30, the tab bar's 10 capsules.
        try await scroll(over: element("sidebar").frame, vertical: true)
        key(".", .command) { !self.element("agents.sort").exists }
        try await scroll(over: element("sidebar").frame, vertical: true)
        try await scroll(over: element("tab.w1:t1").frame, vertical: false)

        try await newTabSplitAndCloses(in: eight)

        // A busy tab: an agent and a printing pane, in view.
        key("1", .command) { self.element("tab.w1:t1").isSelected }
        _ = try await measure("busy tab", seconds: 5, session: eight)
        try await sample("busy tab", in: eight)

        // Another session's page and back (its own snapshots stop mattering while it is out of view).
        openPage(one)
        key("[", [.command, .option]) { self.header == eight }
        key("]", [.command, .option]) { self.header == self.one }
        key("[", [.command, .option]) { self.header == eight }

        let keys = recorded().filter { ["⌘", "⌃", "⇧", "⌥"].contains($0.name.first.map(String.init)) }
        print(keys.map { "\($0.name) \($0.time)ms \($0.turns)" }.joined(separator: "\n"))
        // Every key drew its change in its own turn, or the next for herdr's writes (lane S of phase 25).
        for entry in keys {
            XCTAssertLessThanOrEqual(entry.turns, 1, entry.name)
        }
    }

    /// ⌘T, a quiet tab of its own (measured while 100 agents work in others), ⌘D, ⌘W and ⇧⌘W.
    private func newTabSplitAndCloses(in eight: String) async throws {
        let before = try await tabIDs(in: eight)
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.' AND selected == true"))
            .firstMatch
        key("t", .command) { selected.label == "New Tab" && !self.element("tab.w1:t1").isSelected }
        let new = try await poll("the new tab") { try await self.tabIDs(in: eight).first { !before.contains($0) } }
        XCTAssertTrue(element("tab.\(new)").has(\.isSelected, true, within: 5))
        _ = try await measure("quiet tab, 100 agents elsewhere", seconds: 5, session: eight)
        try await sample("quiet tab", in: eight)
        let cards = element("page.\(new)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        key("d", .command) { cards.count == 2 }
        // The new pane's first program answer, so the close does not wait for herdr's.
        try await Task.sleep(for: .seconds(2.5))
        key("w", .command) { cards.count == 1 }
        key("w", [.command, .shift]) { !self.element("tab.\(new)").exists }
    }

    /// A line in the result bundle and the log.
    private func note(_ text: String) {
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.name = "stress"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// herdr's tab ids of the session.
    private func tabIDs(in session: String) async throws -> [String] {
        try await (Self.snapshot(session)["tabs"] as? [[String: Any]] ?? []).compactMap { $0["tab_id"] as? String }
    }

    /// A trackpad scroll of 30 steps of 20 pt there and the momentum after, then back: one "scroll" record each.
    private func scroll(over frame: CGRect, vertical: Bool) async throws {
        for sign in [-1.0, 1.0] {
            let body = "\(frame.midX) \(frame.midY) \(20 * sign) 30 0 \(vertical ? 1 : 0)"
            try await Self.post("\(one)/swipe", Data(body.utf8))
            try await Task.sleep(for: .seconds(0.5))
        }
    }

    /// `sample`'s profile of the app for 3 s, kept in the result bundle.
    private func sample(_ name: String, in session: String) async throws {
        let profile = try await Self.post("\(session)/sample", Data("3".utf8))
        let attachment = XCTAttachment(string: String(decoding: profile, as: UTF8.self))
        attachment.name = "sample, \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
