import XCTest

/// The whole UI at scale (phase 29, item 14): a session of 30 workspaces, 300 tabs and 400 panes (600 took CI two
/// minutes to make; a Mac gives all its programs 511 terminals), 100 of them agents that print, retitle and change
/// state, and half the others printing (`scripts/stress.py`). It records the main keys' time to their frame, the
/// frames while the sidebar, the tab bar and the Agents view scroll, the app's CPU and memory, and the main thread's
/// work every 5 s: all in the result bundle ("stress", "usage, …", "sample").
extension OrielUITests {
    func testHundredsOfPanesStayQuick() async throws {
        executionTimeAllowance = 600
        let eight = try env("ORIEL_SESSION8")
        addTeardownBlock { _ = try? await Self.post("\(eight)/stress") }
        let made = try await String(decoding: Self.post("\(eight)/stress", Data("300 30 400 100".utf8)), as: UTF8.self)
        print(made)
        // From the launch to the first card drawn: 7–8 s on CI; before phase 29 it stayed blank past 30 s (400 program
        // asks at once).
        let launched = Date.now
        relaunch(eight, ["-recordLatency", "YES"])
        // Also after a failed step.
        addTeardownBlock { @MainActor in self.note(self.element("app.latency").stringValue) }
        XCTAssertTrue(element("pane.w1:p1").exists(within: 20))
        note("connect \(Int(Date.now.timeIntervalSince(launched) * 1000))ms")
        // The first snapshot's program asks (one per pane), and the agents' first states.
        try await Task.sleep(for: .seconds(10))

        let palette = element("palette.filter"), openSession = element("open-session.filter")
        let escape = XCUIKeyboardKey.escape.rawValue
        quietKey("k", .command) { palette.exists }
        quietKey(escape, []) { !palette.exists }
        quietKey("t", [.command, .option]) { openSession.exists }
        quietKey(escape, []) { !openSession.exists }
        quietKey("2", .command) { self.element("tab.w1:t2").isSelected }
        quietKey("1", .command) { self.element("tab.w1:t1").isSelected }
        quietKey("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        quietKey("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        quietKey("s", [.command, .control]) { !self.element("sidebar").exists }
        quietKey("s", [.command, .control]) { self.element("sidebar").exists }
        quietKey(".", .command) { self.element("agents.sort").exists }

        // Frames while lists scroll: the Agents view's 100 rows, the sidebar's 30, the tab bar's 10 capsules.
        try await scroll(over: element("sidebar").frame, vertical: true)
        quietKey(".", .command) { !self.element("agents.sort").exists }
        try await scroll(over: element("sidebar").frame, vertical: true)
        try await scroll(over: element("tab.w1:t1").frame, vertical: false)

        try await newTabSplitAndCloses(in: eight)

        // A busy tab: an agent and a printing pane, in view.
        quietKey("1", .command) { self.element("tab.w1:t1").isSelected }
        let busy = try await measure("busy tab", seconds: 5, session: eight)
        // 15 % on CI; over 100 % before phase 29 (snapshot reads back to back, an O(n²) line split).
        let cpu = busy.split(separator: "\n")[0].split(separator: " ")
        XCTAssertLessThan(Double(cpu[1].dropLast()) ?? 100, 50, busy)
        try await sample("busy tab", in: eight)

        // Another session's page and back (its own snapshots stop mattering while it is out of view).
        openPage(one)
        quietKey("[", [.command, .option]) { self.header == eight }
        quietKey("]", [.command, .option]) { self.header == self.one }
        quietKey("[", [.command, .option]) { self.header == eight }

        let keys = recorded().filter { $0.name.first.map("⌘⌃⇧⌥".contains) == true }
        // Every key drew its change in its own turn, or the next for herdr's writes (lane S of phase 25).
        for entry in keys {
            XCTAssertLessThanOrEqual(entry.turns, 1, entry.name)
        }
        // A snapshot's apply on the main thread ("main … <snapshots> <their ms>"): about 6 ms on CI, 75 ms before
        // phase 29 (a set of every tab's focused pane made again for each pane).
        let main = element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("main ") }
            .map { $0.split(separator: " ") }
        let applies = main.reduce(0) { $0 + (Int($1[3]) ?? 0) }
        let applied = main.reduce(0) { $0 + (Int($1[4].dropLast(2)) ?? 0) }
        XCTAssertLessThan(applied, 25 * max(applies, 1), "\(applied) ms for \(applies) snapshots")
    }

    /// ⌘T, a quiet tab of its own (measured while 100 agents work in others), ⌘D, ⌘W and ⇧⌘W.
    private func newTabSplitAndCloses(in eight: String) async throws {
        let before = try await tabIDs(in: eight)
        quietKey("t", .command) { !self.element("tab.w1:t1").isSelected }
        let new = try await newTabID(after: before, in: eight)
        XCTAssertTrue(element("tab.\(new)").has(\.isSelected, true, within: 10))
        _ = try await measure("quiet tab, 100 agents elsewhere", seconds: 5, session: eight)
        try await sample("quiet tab", in: eight)
        let cards = element("page.\(new)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        quietKey("d", .command) { cards.count == 2 }
        // The new pane's first program answer, so the close does not wait for herdr's.
        try await Task.sleep(for: .seconds(2.5))
        quietKey("w", .command) { cards.count == 1 }
        quietKey("w", [.command, .shift]) { !self.element("tab.\(new)").exists }
    }

    /// The key, then 1.5 s with no accessibility query before its change is checked: XCUITest's queries take the main
    /// thread, for seconds at this size, and would be counted as the key's time.
    private func quietKey(_ key: String, _ flags: XCUIElement.KeyModifierFlags, until done: () -> Bool) {
        app.typeKey(key, modifierFlags: flags)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(until(5, done), "after \(key)")
    }

    /// A line in the result bundle and the log.
    func note(_ text: String) {
        print(text)
        keep(text, as: "stress")
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
        keep(String(decoding: profile, as: UTF8.self), as: "sample, \(name)")
    }
}
