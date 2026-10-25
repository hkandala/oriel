import XCTest

/// The main interactions react at once (phase 25, item 14): `-recordLatency YES` gives, for each key, the time to the
/// first frame that drew its change and how many run loop turns that took.
extension OrielUITests {
    func testMainInteractionsReactAtOnce() async throws {
        relaunch(one, ["-recordLatency", "YES"])
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        try await settle(["w1:t1"])

        func key(_ key: String, _ flags: XCUIElement.KeyModifierFlags, until done: () -> Bool) {
            app.typeKey(key, modifierFlags: flags)
            XCTAssertTrue(until(5, done), "after \(key)")
            Thread.sleep(forTimeInterval: 0.5)
        }
        let palette = element("palette.filter"), openSession = element("open-session.filter")
        key("k", .command) { palette.exists }
        key(XCUIKeyboardKey.escape.rawValue, []) { !palette.exists }
        key("k", .command) { palette.exists }
        key(XCUIKeyboardKey.escape.rawValue, []) { !palette.exists }
        key("n", [.command, .shift]) { openSession.exists }
        key(XCUIKeyboardKey.escape.rawValue, []) { !openSession.exists }
        key("2", .command) { self.element("tab.w1:t2").isSelected }
        key("1", .command) { self.element("tab.w1:t1").isSelected }
        key("]", [.command, .control]) { self.element("workspace.w2").isSelected }
        key("[", [.command, .control]) { self.element("workspace.w1").isSelected }
        key("]", [.command, .option]) { self.header == self.two }
        key("[", [.command, .option]) { self.header == self.one }
        key("t", .command) { self.element("tab.w1:t1").exists && !self.element("tab.w1:t1").isSelected }
        let made = try await newTabID(after: before)
        try await settle([made])
        let cards = element("page.\(made)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        key("d", .command) { cards.count == 2 }
        try await settle([made])
        key("w", .command) { cards.count == 1 }
        key("w", [.command, .option]) { !self.element("tab.\(made)").exists }
        // Half a page: the snap does the rest.
        let sidebar = element("sidebar"), header = element("sidebar.header")
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: header, \.stringValue, two)
        try await Task.sleep(for: .seconds(1))
        try await swipe(sidebar, by: sidebar.frame.width / 2, until: header, \.stringValue, one)
        try await Task.sleep(for: .seconds(1))

        let recorded = element("app.latency").stringValue
        let attachment = XCTAttachment(string: recorded)
        attachment.name = "latency"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("latency: \(recorded)")
    }
}
