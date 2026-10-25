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
        let keys = recorded().filter { ["⌘", "⌃", "⇧", "⌥"].contains($0.name.first.map(String.init)) }
        XCTAssertEqual(keys.map(\.name), ["⌘K", "⌘K", "⇧⌘N", "⌘2", "⌘1", "⌃⌘]", "⌃⌘[", "⌥⌘]", "⌥⌘["])
        for entry in keys {
            XCTAssertEqual(entry.turns, 0, entry.name)
        }
        // The session spring's slide after a lifted swipe; the system's paging snap took 217 ms on CI (phase 25).
        let swipes = recorded().filter { $0.name == "swipe" }
        XCTAssertEqual(swipes.count, 2)
        for swipe in swipes {
            XCTAssertLessThan(swipe.time, 150)
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
        // The new pane's program is asked a second late; until then a close waits for herdr's answer.
        try await Task.sleep(for: .seconds(2))
        key("w", .command) { cards.count == 1 }
        key("w", [.command, .shift]) { !self.element("tab.\(made)").exists }
        let keys = recorded().filter { ["⌘", "⇧"].contains($0.name.first.map(String.init)) }
        XCTAssertEqual(keys.map(\.name), ["⌘T", "⌘D", "⌘W", "⇧⌘W"])
        for entry in keys {
            XCTAssertEqual(entry.turns, 0, entry.name)
        }
        // herdr closed it, and it stays closed.
        try await expect("herdr closed the tab") { try await !tabIDs().contains(made) }
        XCTAssertFalse(element("tab.\(made)").exists)
    }

    /// Two quick ⌘T select the second new tab; ⌘T and a close before herdr answers close herdr's tab as it comes.
    func testQuickNewTabsAndAnEarlyClose() async throws {
        try launchRecordingLatency()
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("t", modifierFlags: .command)
        let two = try await poll("two new tabs") { () async throws -> [String]? in
            let new = try await tabIDs().filter { !before.contains($0) }
            return new.count == 2 ? new : nil
        }
        XCTAssertTrue(element("tab.\(two[1])").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("tab.\(two[0])").exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.new.'")).count, 0)

        let now = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("w", modifierFlags: [.command, .shift])
        // herdr makes the tab, and the app closes it: no dialog, no tab left.
        try await expect("the early-closed tab made and closed") {
            let tabs = try await tabIDs()
            return tabs.count == now.count && tabs.contains(two[1])
        }
        XCTAssertTrue(element("tab.\(two[1])").has(\.isSelected, true, within: 3))
        XCTAssertFalse(app.sheets.firstMatch.exists)
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

    /// "⌘T 12ms 0": the key, the time to its frame, the turns; "swipe 53ms".
    private struct Entry {
        let name: String, time: Int, turns: Int
    }

    private func recorded() -> [Entry] {
        element("app.latency").stringValue.split(separator: "; ").map { entry in
            let words = entry.split(separator: " ").map(String.init)
            return Entry(name: words.first ?? "", time: Int(words.count > 1 ? words[1].dropLast(2) : "") ?? -1,
                         turns: Int(words.count > 2 ? words[2] : "") ?? -1)
        }
    }
}
