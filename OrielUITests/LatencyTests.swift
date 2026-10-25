import XCTest

/// The main interactions react at once (phase 25, item 14): `-recordLatency YES` gives, for each key, the time from
/// the key to the first frame that drew its change and how many run loop turns that took ("⌘T 12ms 0 …").
extension OrielUITests {
    func testPanelsAndSwitchesReactAtOnce() async throws {
        // The session slide's spring, as on a Mac without Reduce Motion.
        try launchRecordingLatency(["-forceMotion", "YES"])
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        let palette = element("palette.filter"), openSession = element("open-session.filter")
        let escape = XCUIKeyboardKey.escape.rawValue
        key("k", .command) { palette.exists }
        key(escape, []) { !palette.exists }
        key("k", .command) { palette.exists }
        key(escape, []) { !palette.exists }
        key("n", [.command, .shift]) { openSession.exists }
        key(escape, []) { !openSession.exists }
        key("2", .command) { self.element("tab.w1:t2").isSelected }
        key("1", .command) { self.element("tab.w1:t1").isSelected }
        key("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        key("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        key("]", [.command, .option]) { self.header == self.two }
        key("[", [.command, .option]) { self.header == self.one }
        // Half a page: the snap does the rest.
        let sidebar = element("sidebar"), name = element("sidebar.header")
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: name, \.stringValue, two)
        try await Task.sleep(for: .seconds(1))
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: name, \.stringValue, one)
        try await Task.sleep(for: .seconds(1))
        // Each drawn in the key's own turn.
        for entry in recorded() where ["⌘", "⌃", "⇧"].contains(entry.name.first.map(String.init)) {
            XCTAssertEqual(entry.turns, 0, entry.name)
        }
    }

    /// ⌘T, ⌘D, ⌘W and ⇧⌘W show their change in the key's turn: herdr catches up after (`Ahead`).
    func testNewTabSplitAndClosesShowAtOnce() async throws {
        try launchRecordingLatency()
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        // A new tab is "New Tab" until its program is known, never herdr's number (item 13).
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.' AND selected == true"))
            .firstMatch
        key("t", .command) { selected.label == "New Tab" && !self.element("tab.w1:t1").isSelected }
        var titles: [String] = []
        XCTAssertTrue(until(5) {
            titles.append(selected.label)
            return !["", "New Tab"].contains(titles.last)
        })
        XCTAssertFalse(titles.contains { !$0.isEmpty && $0.allSatisfy(\.isNumber) }, "\(titles)")
        let made = try await newTabID(after: before)
        try await settle([made])
        let cards = element("page.\(made)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        key("d", .command) { cards.count == 2 }
        try await settle([made])
        key("w", .command) { cards.count == 1 }
        key("w", [.command, .shift]) { !self.element("tab.\(made)").exists }
        for entry in recorded() where ["⌘T", "⌘D", "⌘W", "⇧⌘W"].contains(entry.name) {
            XCTAssertEqual(entry.turns, 0, entry.name)
        }
    }

    private func launchRecordingLatency(_ args: [String] = []) throws {
        relaunch(one, ["-recordLatency", "YES"] + args)
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        // Also after a failed step.
        addTeardownBlock { @MainActor in
            let attachment = XCTAttachment(string: self.element("app.latency").stringValue)
            attachment.name = "latency"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
    }

    /// The key, then its change; a pause, so the next key's record starts clean.
    private func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags, until done: () -> Bool) {
        app.typeKey(key, modifierFlags: flags)
        XCTAssertTrue(until(5, done), "after \(key)")
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func recorded() -> [(name: String, turns: Int)] {
        element("app.latency").stringValue.split(separator: "; ").map { entry in
            let words = entry.split(separator: " ")
            return (String(words.first ?? ""), Int(words.count > 2 ? words[2] : "") ?? -1)
        }
    }
}
