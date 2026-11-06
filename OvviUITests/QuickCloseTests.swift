import XCTest

/// ⌘W right after ⌘D, and the active pane's border.
extension OvviUITests {
    /// ⌘W right after quick ⌘Ds closes the lit card each time, also a split herdr has not made yet, and herdr's pane
    /// for it never shows. A last ⌘D's write comes after all of theirs: then herdr has two panes and the page two
    /// cards.
    func testCloseRightAfterQuickSplitsAndTheActiveBorder() async throws {
        relaunch(one, ["-recordMotion", "YES"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (tab, first) = try await newTab("quick-close")
        element("tab.\(tab)").click()
        element("terminal.\(first)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(first)"))
        // One card: no border.
        XCTAssertTrue(element("pane.\(first)").exists)
        XCTAssertFalse(element("pane.\(first).border").exists)
        let cards = element("cards.\(tab)")
        XCTAssertTrue(cards.exists(within: 2))
        let before = cards.stringValue.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(before.count, 2, cards.stringValue)
        for key in ["d", "d", "d", "w", "w", "w", "d"] {
            app.typeKey(key, modifierFlags: .command)
        }
        // The last ⌘D's pane has the keyboard once its write, the last, is done.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let panes = try await poll("a new last pane with the keyboard") { () async throws -> [String]? in
            let panes = try await order(tab), last = element("terminal.\(panes.last ?? "")")
            return panes.count > 1 && last.exists && focused.evaluate(with: last) ? panes : nil
        }
        XCTAssertEqual(panes.count, 2, "herdr's tree: \(panes)")
        XCTAssertEqual(panes.first, first)
        // Four cards came and three went: none for a closed split's pane.
        let counts = "\(before[0] + 4) \(before[1] + 3)"
        XCTAssertTrue(cards.has(\.stringValue, counts, within: 2), "came went: \(cards.stringValue)")
        // The active pane's border: on the keyboard card of two, at once; none when one card shows.
        XCTAssertTrue(element("pane.\(panes[1]).border").exists)
        element("terminal.\(first)").click()
        XCTAssertTrue(element("pane.\(first).border").exists(within: 1))
        XCTAssertFalse(element("pane.\(panes[1]).border").exists)
        app.typeKey(.return, modifierFlags: [.command, .shift])
        XCTAssertTrue(element("pane.\(first).border").vanishes(within: 2))
    }
}
