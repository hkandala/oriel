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
        key("t", [.command, .option]) { openSession.exists }
        // Its first draw lists the sessions the page read as it connected, not an empty list that fills a moment later
        // (user, phase 29).
        let first = element("app.latency").stringValue.split(separator: "; ").last { $0.hasPrefix("open-session") }
        XCTAssertTrue(first?.split(separator: " ").last?.split(separator: ",").contains { $0 == two } == true,
                      "\(first ?? "none")")
        key(escape, []) { !openSession.exists }
        key("2", .command) { self.element("tab.w1:t2").isSelected }
        key("1", .command) { self.element("tab.w1:t1").isSelected }
        key("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        key("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        key("]", [.command, .option]) { self.header == self.two }
        key("[", [.command, .option]) { self.header == self.one }
        // Half a page: XCUITest's scroll is a sideways wheel's, which turns a page.
        let sidebar = element("sidebar"), name = element("sidebar.header")
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: name, \.stringValue, two)
        try await Task.sleep(for: .seconds(1))
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: name, \.stringValue, one)
        try await Task.sleep(for: .seconds(1))
        // Each drawn in the key's own turn.
        let keys = recorded().filter { ["⌘", "⌃", "⇧", "⌥"].contains($0.name.first.map(String.init)) }
        XCTAssertEqual(keys.map(\.name), ["⌘K", "⌘K", "⌥⌘T", "⌘2", "⌘1", "⌃⌘]", "⌃⌘[", "⌥⌘]", "⌥⌘["])
        for entry in keys {
            XCTAssertEqual(entry.turns, 0, entry.name)
        }
    }

    /// ⌘T, ⌘D, ⌘W and ⇧⌘W show their change in the key's turn or the next: herdr catches up after (`Ahead`).
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
        // herdr's tab took the stand-in's place, still selected.
        XCTAssertTrue(element("tab.\(made)").has(\.isSelected, true, within: 3))
        try await settle([made])
        let cards = element("page.\(made)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        key("d", .command) { cards.count == 2 }
        try await settle([made])
        // The new pane (it has the keyboard) is asked for its program a second late: until its first answer a close
        // waits for herdr's.
        try await Task.sleep(for: .seconds(2.5))
        key("w", .command) { cards.count == 1 }
        key("w", [.command, .shift]) { !self.element("tab.\(made)").exists }
        let keys = recorded().filter { ["⌘", "⇧"].contains($0.name.first.map(String.init)) }
        XCTAssertEqual(keys.map(\.name), ["⌘T", "⌘D", "⌘W", "⇧⌘W"])
        // In the key's turn, or the next one (the action's task): herdr's answer takes 10 or more.
        for entry in keys {
            XCTAssertLessThanOrEqual(entry.turns, 1, entry.name)
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

    /// A two-finger swipe between sessions (phase 27): the page follows the fingers, and from their lift slides on
    /// to the next page with the session spring, from their speed: no jump or stall at the lift, no bounce, calmer
    /// than phase 25's 0.14 s spring. A trackpad's events at a known speed (`scripts/swipe.swift`): XCUITest's scroll
    /// is one flick, at the page before the fingers lift.
    func testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed() async throws {
        try launchRecordingLatency(["-forceMotion", "YES"])
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        let sidebar = element("sidebar"), width = sidebar.frame.width
        let center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        // 14 steps of 10 pt, 16 ms apart (625 pt/s), past half a page, then momentum; the other way if natural
        // scrolling is off.
        var forward = -1.0
        for sign in [-1.0, 1.0] {
            forward = sign
            try await Self.post("\(one)/swipe", Data("\(center) \(10 * sign) 14".utf8))
            // No accessibility query during the slide: XCUITest's snapshots take the main thread (a 240 ms stall).
            try await Task.sleep(for: .seconds(1))
            if header == two {
                break
            }
        }
        XCTAssertEqual(header, two)
        let (swipe, path, shown) = try XCTUnwrap(swipes().last, "no swipe moved")
        let speed = 10 / 0.016
        let times = path.map { $0[0] }, offsets = path.map { $0[1] }
        // The page went 140 pt with the fingers, give or take the system's own pace.
        XCTAssertEqual(offsets[0], 140, accuracy: 40, "\(swipe)")
        // The next page, one page width over (the sidebar's minus its 8 pt handle), never past it, never back.
        let target = offsets.last ?? 0
        XCTAssertEqual(target, width - 8, accuracy: 2, "\(swipe)")
        XCTAssertTrue(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "\(swipe)")
        // Within 2 pt of the page: 0.14 s from rest takes about 0.13 s; the 0.2 s spring from the fingers' speed 0.17
        // to 0.19 s here, the system's snap 0.33 s.
        let settled = path.first { abs($0[1] - target) <= 2 }?[0] ?? 0
        XCTAssertGreaterThan(settled, 150, "\(swipe)")
        XCTAssertLessThan(settled, 400, "\(swipe)")
        // The window shows the session as the pages look arrived, not in the spring's tail (150–200 ms later, phase
        // 28).
        XCTAssertGreaterThan(shown, 0, "\(swipe)")
        XCTAssertLessThan(shown - settled, 80, "\(swipe)")
        // A step at least every 100 ms until then: no stall (a slide started at the scroll view's own end stood still
        // 100–350 ms, then jumped). A debug build under XCUITest still drops a few frames at the start (about 50 ms).
        let steps = times.filter { $0 <= settled }
        XCTAssertLessThan(zip(steps, steps.dropFirst()).map { $1 - $0 }.max() ?? 1000, 100, "\(swipe)")
        // Its first 60 ms keep at least half the fingers' speed: no jump, no stall.
        let early = path.last { $0[0] <= 60 } ?? path[0]
        XCTAssertGreaterThan((early[1] - offsets[0]) / max(early[0], 1) * 1000, speed / 2, "\(swipe)")
        XCTAssertLessThan((early[1] - offsets[0]) / max(early[0], 1) * 1000, speed * 3, "\(swipe)")

        // 40 pt back, then the fingers stop 0.2 s before they lift: back to the same page (the session spring),
        // no session change.
        let name = element("sidebar.header"), place = name.frame.minX
        try await Self.post("\(one)/swipe", Data("\(center) \(-10 * forward) 4 200".utf8))
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(header, two)
        XCTAssertEqual(name.frame.minX, place, accuracy: 1)
    }

    /// A quick flick between sessions (phase 28): the fingers on the pad for 48 ms, then momentum. The pages slide on
    /// to the next page and rest there with the window on its session. A slide asked of the scroll view on such a
    /// flick stood still until a 0.6 s timeout; then the pages snapped back while the window showed the next session,
    /// and then the first again.
    func testQuickSessionFlickLandsOnTheNextPageInStep() async throws {
        try launchRecordingLatency(["-forceMotion", "YES"])
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        let sidebar = element("sidebar"), name = element("sidebar.header"), place = name.frame.minX
        let center = "\(sidebar.frame.midX) \(sidebar.frame.midY)"
        // The other way if natural scrolling is off.
        for sign in [-1.0, 1.0] {
            try await Self.post("\(one)/swipe", Data("\(center) \(20 * sign) 3".utf8))
            try await Task.sleep(for: .seconds(1.5))
            if header == two {
                break
            }
        }
        XCTAssertEqual(header, two)
        // The pages rest on the session the window shows.
        XCTAssertEqual(name.frame.minX, place, accuracy: 1)
        let (swipe, path, shown) = try XCTUnwrap(swipes().last, "no swipe moved")
        XCTAssertEqual(path.last?[1] ?? 0, sidebar.frame.width - 8, accuracy: 2, "\(swipe)")
        // A step at least every 100 ms until the page: no stall. The session shows with it.
        let settled = path.first { abs($0[1] - sidebar.frame.width + 8) <= 2 }?[0] ?? 1000
        XCTAssertLessThan(settled, 400, "\(swipe)")
        XCTAssertLessThan(shown - settled, 80, "\(swipe)")
        let steps = path.map { $0[0] }.filter { $0 <= settled }
        XCTAssertLessThan(zip(steps, steps.dropFirst()).map { $1 - $0 }.max() ?? 1000, 100, "\(swipe)")
    }

    /// The "swipe" records in which the pages moved (a swipe back to the page in view makes one that did not), each
    /// with its offsets: [ms, pt], and the ms to the session's show (-1: none).
    private func swipes() -> [(String, [[Double]], Double)] { // swiftlint:disable:this large_tuple
        element("app.latency").stringValue.split(separator: "; ").filter { $0.hasPrefix("swipe") }.map { swipe in
            let words = swipe.split(separator: " ")
            let path = words.count > 2
                ? words[2].split(separator: ",").map { $0.split(separator: ":").compactMap { Double($0) } } : []
            return (String(swipe), path, words.count > 3 ? Double(words[3]) ?? -1 : -1)
        }.filter { $0.1.count > 4 }
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
    func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags, until done: () -> Bool) {
        app.typeKey(key, modifierFlags: flags)
        XCTAssertTrue(until(5, done), "after \(key)")
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// "⌘T 12ms 0": the key, the time to its frame, the turns; "swipe 230ms 0:145,8:152,…".
    struct Entry {
        let name: String, time: Int, turns: Int
    }

    func recorded() -> [Entry] {
        element("app.latency").stringValue.split(separator: "; ").map { entry in
            let words = entry.split(separator: " ").map(String.init)
            return Entry(name: words.first ?? "", time: Int(words.count > 1 ? words[1].dropLast(2) : "") ?? -1,
                         turns: Int(words.count > 2 ? words[2] : "") ?? -1)
        }
    }
}
