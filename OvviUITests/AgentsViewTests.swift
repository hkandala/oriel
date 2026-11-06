import XCTest

/// The Agents view: one list by the newest change, rows that hold still under the pointer, Pinned and Settled. Every
/// status comes from `pane.report_agent` on a throwaway tab, closed after the test (its agent goes with it).
extension OvviUITests {
    func testAgentsViewListsAgentsByTheirNewestChange() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let idle = try await newTab("review", in: "w1").pane
        try await report(idle, "idle", agent: "pi")
        // A split, not a fourth tab in w1: 220 pt tabs, and only 3 fit on CI's window.
        let working = try await split(idle)
        try await report(working, "working")
        try await Self.call(one, "pane.rename", ["pane_id": working, "label": "fixer"])
        let blocked = try await newTab("deploy").pane
        try await report(blocked, "blocked", agent: "claude")
        let docs = try await newTab("docs")
        try await report(docs.pane, "working")
        try await waitForValue("tab.\(docs.tab)", containing: "working")
        try await report(docs.pane, "idle")
        let done = docs.pane

        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("titlebar.agents").has(\.isSelected, true, within: 2))
        // The session's name alone: no sort menu.
        XCTAssertEqual(element("sidebar.header").value as? String, one)
        XCTAssertFalse(element("agents.sort").exists)
        let rows = [done, blocked, working, idle].map { element("agent.\($0)") }
        try await expect("each row's state") {
            rows.map { $0.value as? String } == ["Done", "Needs you", "Working", "Idle"]
        }
        try await expectOrder(rows, "newest change first")
        try await expect("the pane's name as the title") { rows[2].label.hasPrefix("fixer, alpha · ") }
        XCTAssertTrue(rows[3].label.hasPrefix("Untitled, alpha · "), rows[3].label)
        // One leading edge: the page header and the row icons (8 pt into each row).
        let header = element("sidebar.header").frame
        XCTAssertEqual(rows[0].frame.minX + 8, header.minX, accuracy: 0.5, "\(header) \(rows[0].frame)")
        keepScreenshot("agents view by newest change")

        // A change while the pointer rests on the list: the box at once, the row stays; it moves once the pointer
        // leaves and the list settles.
        rows[3].hover()
        try await report(idle, "working", agent: "pi")
        try await waitForValue("agent.\(idle)", containing: "Working")
        XCTAssertFalse(until(1.5) { rows[3].frame.minY < rows[2].frame.minY }, "moved under the pointer")
        element("sidebar.header").hover()
        try await expectOrder([rows[3], rows[0], rows[1], rows[2]], "the newest on top once the pointer left")

        filter("beta", keeps: rows, [true, true, false, false])
        filter("fixer", keeps: rows, [false, false, true, false])
    }

    /// Pin from the row's hover button or its menu: the row goes on top, over a line, and stays there over newer
    /// changes and a relaunch; Unpin in the menu puts it back.
    func testAPinnedAgentStaysOnTop() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let older = try await newTab("deploy").pane
        try await report(older, "idle", agent: "claude")
        let newer = try await split(older)
        try await report(newer, "working")
        app.typeKey(".", modifierFlags: .command)
        let rows = [older, newer].map { app.buttons["agent.\($0)"] }
        try await expectOrder([rows[1], rows[0]], "newest first")

        // The pin shows only under the pointer.
        let pin = element("agent.\(older).pin")
        XCTAssertFalse(pin.exists)
        rows[0].hover()
        XCTAssertTrue(pin.exists(within: 2))
        XCTAssertFalse(element("agent.\(newer).pin").exists)
        pin.click()
        try await expectOrder([rows[0], rows[1]], "the pinned row on top")
        rows[0].hover()
        XCTAssertTrue(pin.has(\.label, "Unpin", within: 2))
        keepScreenshot("pinned agent, hovered")
        try await report(newer, "blocked", agent: "codex")
        try await waitForValue("agent.\(newer)", containing: "Needs you")
        element("sidebar.header").hover()
        XCTAssertFalse(until(2) { rows[1].frame.minY < rows[0].frame.minY }, "a newer change passed the pin")
        keepScreenshot("pinned agent")

        relaunch()
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(rows[1].exists(within: connect))
        try await expectOrder([rows[0], rows[1]], "pinned after a relaunch")
        rows[0].rightClick()
        app.menuItems["Unpin"].click()
        try await expectOrder([rows[1], rows[0]], "unpinned")
        rows[0].rightClick()
        XCTAssertTrue(app.menuItems["Pin"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Settle by hand puts an idle agent on the Settled shelf at the sidebar's foot, folded at first; Unsettle brings
    /// it back. The shelf keeps its fold.
    func testAnIdleAgentSettlesByHand() async throws {
        relaunch(one, ["-settleAfter", "<real>0</real>"])
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let quiet = try await newTab("review", in: "w1").pane
        try await report(quiet, "idle", agent: "pi")
        let busy = try await split(quiet)
        try await report(busy, "working")
        app.typeKey(".", modifierFlags: .command)
        let row = app.buttons["agent.\(quiet)"], shelf = element("agents.shelf.Settled")
        XCTAssertTrue(row.exists(within: 2))
        app.buttons["agent.\(busy)"].rightClick()
        XCTAssertFalse(app.menuItems["Settle"].isEnabled, "a working agent settled")
        app.typeKey(.escape, modifierFlags: [])
        row.rightClick()
        app.menuItems["Settle"].click()
        XCTAssertTrue(shelf.exists(within: 2))
        XCTAssertTrue(row.vanishes(within: 2))
        XCTAssertEqual(shelf.label, "Settled 1")
        XCTAssertEqual(shelf.value as? String, "collapsed")
        addTeardownBlock { @MainActor in
            if shelf.exists, shelf.value as? String == "expanded" {
                shelf.click()
            }
        }
        XCTAssertGreaterThan(shelf.frame.minY, element("sidebar").frame.midY, "\(shelf.frame)")
        keepScreenshot("settled shelf, folded")
        shelf.click()
        XCTAssertTrue(row.exists(within: 2))
        XCTAssertGreaterThan(row.frame.minY, shelf.frame.maxY)
        keepScreenshot("settled shelf, open")
        row.rightClick()
        app.menuItems["Unsettle"].click()
        XCTAssertTrue(shelf.vanishes(within: 2))
        XCTAssertTrue(row.exists)
        // Settled again: the shelf comes back open, as it was left; folded, as the next test expects it.
        row.rightClick()
        app.menuItems["Settle"].click()
        XCTAssertTrue(until(2) { shelf.value as? String == "expanded" }, "the fold was not kept")
        shelf.click()
        XCTAssertTrue(row.vanishes(within: 2))
    }

    /// An idle agent you have seen settles after the setting (none with Never); working brings it back on top.
    func testIdleAgentsSettleAfterTheSetting() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let quiet = try await newTab("review", in: "w1").pane
        try await report(quiet, "idle", agent: "pi")
        let busy = try await split(quiet)
        try await report(busy, "working")
        let row = app.buttons["agent.\(quiet)"], shelf = element("agents.shelf.Settled")
        relaunch(one, ["-settleAfter", "<real>0</real>"])
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(row.exists(within: connect))
        XCTAssertFalse(shelf.exists, "Never settled it")
        relaunch(one, ["-settleAfter", "<real>1</real>"])
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(shelf.exists(within: connect))
        XCTAssertEqual(shelf.label, "Settled 1")
        XCTAssertFalse(row.exists)
        try await report(quiet, "working", agent: "pi")
        // Off the list, where rows hold still.
        element("sidebar.header").hover()
        XCTAssertTrue(shelf.vanishes(within: 3))
        try await expectOrder([row, app.buttons["agent.\(busy)"]], "back on top")
    }

    /// The rows' tops are in this order.
    private func expectOrder(_ rows: [XCUIElement], _ what: String) async throws {
        try await expect(what) {
            guard rows.allSatisfy(\.exists) else { return false }
            let tops = rows.map(\.frame.minY)
            return tops == tops.sorted() && Set(tops).count == tops.count
        }
    }
}
