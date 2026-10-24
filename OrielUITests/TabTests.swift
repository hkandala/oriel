import XCTest

/// Tab switches, closes and drags from the user's second round (phase 24, items 14, 16, 17, 18).
extension OrielUITests {
    /// A click, +, ⌘T, ⌘1…⌘9, ⇧⌘], the palette and a close show the tab's page at once; only a swipe slides.
    func testSwitchingTabsShowsTheirPageAtOnce() async throws {
        relaunch(one, ["-recordStrip", "YES"])
        let first = element("tab.w1:t1"), second = element("tab.w1:t2"), between = element("strip.between")
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        let launched = between.stringValue, before = try await tabIDs()
        closeNew("tab", besides: before)

        second.click()
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        first.click()
        XCTAssertTrue(first.has(\.isSelected, true, within: 2))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        app.typeKey("]", modifierFlags: [.command, .shift])
        XCTAssertTrue(first.has(\.isSelected, true, within: 2))
        openPalette()
        element("palette.tab.w1:t2").click()
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))

        // A new tab from +, closed from the menu: back to the tab used before it.
        element("titlebar.new-tab").click()
        let plus = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(plus)").has(\.isSelected, true, within: 3))
        app.typeKey("w", modifierFlags: [.command, .option])
        let confirm = app.sheets.buttons["Close Tab"]
        XCTAssertTrue(confirm.exists(within: 2))
        confirm.click()
        XCTAssertTrue(element("tab.\(plus)").vanishes(within: 3))
        XCTAssertTrue(second.has(\.isSelected, true, within: 2))
        // One from ⌘T, closed by herdr.
        app.typeKey("t", modifierFlags: .command)
        let made = try await newTabID(after: before)
        XCTAssertTrue(element("tab.\(made)").has(\.isSelected, true, within: 3))
        try await Self.call(one, "tab.close", ["tab_id": made])
        XCTAssertTrue(second.has(\.isSelected, true, within: 3))
        XCTAssertFalse(until(0.5) { between.stringValue != launched }, "the strip slid \(between.stringValue) times")

        // A swipe does slide: the count sees slides.
        try await swipe(element("terminal.w1:p4"), until: first, \.isSelected, true)
        XCTAssertNotEqual(between.stringValue, launched)
    }

    /// A closed selected tab gives way to the tab used before it, else to the one on its left.
    func testClosingTheSelectedTabGoesToTheOneUsedBefore() async throws {
        let tabs = try await newWorkspace("used", tabs: 5).tabs
        let capsules = tabs.map { element("tab.\($0)") }
        XCTAssertTrue(capsules[0].has(\.isSelected, true, within: 2))
        // ⌘ keys: only 3 tabs fit on CI's window.
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(capsules[4].has(\.isSelected, true, within: 2))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(capsules[2].has(\.isSelected, true, within: 2))

        // Not the left one (1) or the first (0).
        try await Self.call(one, "tab.close", ["tab_id": tabs[2]])
        XCTAssertTrue(capsules[4].has(\.isSelected, true, within: 3))
        // Every tab used before is gone: the left one (3), not the first (1).
        try await Self.call(one, "tab.close", ["tab_id": tabs[0]])
        XCTAssertTrue(capsules[0].vanishes(within: 3))
        try await Self.call(one, "tab.close", ["tab_id": tabs[4]])
        XCTAssertTrue(capsules[3].has(\.isSelected, true, within: 3))
    }
}
