import XCTest

/// The overview (phase 27, D70): every tab of the session as a live miniature, grouped by workspace.
extension OrielUITests {
    /// ⌃⌘O hides the sidebar and tab bar and shows a tile per tab under its workspace; a tab never shown draws live
    /// in its tile; a click shows that tab, its terminals at their size; Esc leaves too.
    func testOverviewShowsEveryTabLiveAndOpensOne() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // A white block in w2's pane, which no card showed yet.
        let block = "clear; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await send("\(block); echo block-$((6*7))\r", to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\nblock-42") }

        app.typeKey("o", modifierFlags: [.command, .control])
        let overview = element("overview")
        XCTAssertTrue(overview.exists(within: 2))
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        XCTAssertFalse(element("tab.w1:t1").exists)
        XCTAssertEqual(element("titlebar.overview").stringValue, "on")
        for id in ["overview.workspace.w1", "overview.workspace.w2", "overview.tab.w1:t1", "overview.tab.w1:t2",
                   "overview.tab.w2:t1"]
        {
            XCTAssertTrue(element(id).exists, id)
        }
        // Under its workspace's name, and each tile at the page's proportions.
        XCTAssertLessThan(element("overview.workspace.w2").frame.maxY, element("overview.tab.w2:t1").frame.minY)
        XCTAssertEqual(element("overview.tab.w1:t1").stringValue, "selected")
        keepScreenshot("overview")
        let tile = element("overview.tab.w2:t1"), dark = element("overview.tab.w1:t2")
        XCTAssertTrue(until(3) { mean(tile) > mean(dark) + 30 }, "\(mean(tile)) \(mean(dark))")

        tile.click()
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(element("sidebar").exists(within: 2))
        XCTAssertTrue(element("tab.w2:t1").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.w2:p1")))
        try await expectPTYSize("w2:p1")

        element("titlebar.overview").click()
        XCTAssertTrue(overview.exists(within: 2))
        XCTAssertEqual(element("overview.tab.w2:t1").stringValue, "selected")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(overview.vanishes(within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.w2:p1")))
    }

    /// The mean brightness of an element's pixels.
    func mean(_ element: XCUIElement) -> Int {
        let brightness = Self.brightness(element.screenshot().image)
        return brightness.isEmpty ? 0 : brightness.reduce(0, +) / brightness.count
    }
}
