import XCTest

/// Tab switches, closes and drags from the user's second round (phase 24, items 14, 16, 17, 18).
extension OrielUITests {
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
