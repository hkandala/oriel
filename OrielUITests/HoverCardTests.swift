import XCTest

/// The hover card (phase 19): a tab's panes on a capsule or an Agents view row, and the chrome buttons' tooltips.
extension OrielUITests {
    func testHoverCardShowsABlockedAgentsScreenAndEscClosesIt() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        let (tab, pane) = try await newTab("deploy")
        try await split(split(pane))
        try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "echo hover-$((6*7)); echo waiting\r"])
        try await waitFor(pane) { $0.contains("\nhover-42") }
        try await report(pane, "blocked", agent: "claude")
        try await waitForValue("tab.\(tab)", containing: "claude, needs you")

        element("tab.\(tab)").hover()
        let card = element("hovercard")
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        XCTAssertEqual(rows(of: card).count, 3)
        try await waitForValue("hovercard.\(pane)", containing: "hover-42")
        XCTAssertTrue((element("hovercard.\(pane)").value as? String)?.hasPrefix("Needs you") == true)
        // Under its capsule.
        XCTAssertEqual(card.frame.midX, element("tab.\(tab)").frame.midX, accuracy: 2)
        XCTAssertGreaterThan(card.frame.minY, element("tab.\(tab)").frame.maxY)
        keepScreenshot("hover card")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.waitForNonExistence(timeout: 2))
    }

    func testHoverCardRowGoesToItsPane() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        let (tab, pane) = try await newTab("peek")
        let second = try await split(pane)
        XCTAssertFalse(element("tab.\(tab)").isSelected)

        element("tab.\(tab)").hover()
        let card = element("hovercard")
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        XCTAssertEqual(rows(of: card).count, 2)
        element("hovercard.\(second)").click()
        XCTAssertTrue(element("tab.\(tab)").wait(for: \.isSelected, toEqual: true, timeout: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        XCTAssertTrue(card.waitForNonExistence(timeout: 2))
    }

    func testAgentsRowShowsItsTabsCard() async throws {
        XCTAssertTrue(element("workspace.w1").waitForExistence(timeout: connect))
        let (tab, pane) = try await newTab("build", in: "w1")
        try await split(pane)
        try await report(pane, "working")
        app.typeKey(".", modifierFlags: .command)
        let row = element("agent.\(pane)")
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        row.hover()
        let card = element("hovercard")
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        XCTAssertEqual(rows(of: card).count, 2)
        XCTAssertTrue(element("hovercard.\(pane)").exists)
        XCTAssertGreaterThan(card.frame.minX, element("sidebar").frame.maxX)
        // A click on the title selects the tab.
        element("hovercard.title").click()
        XCTAssertTrue(element("tab.\(tab)").wait(for: \.isSelected, toEqual: true, timeout: 2))
        XCTAssertTrue(card.waitForNonExistence(timeout: 2))
    }

    func testNewTabButtonsTooltipSaysItsShortcut() {
        let button = element("titlebar.new-tab")
        XCTAssertTrue(button.waitForExistence(timeout: connect))
        XCTAssertEqual(button.label, "New Tab ⌘T")
        button.hover()
        let tip = app.helpTags.firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(tip.label, "New Tab ⌘T", tip.debugDescription)
        // The tip is a window of its own: the screen, not the app's window.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "tooltip"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The card's pane rows.
    private func rows(of card: XCUIElement) -> [XCUIElement] {
        card.descendants(matching: .button).matching(NSPredicate(format: "identifier BEGINSWITH 'hovercard.w'"))
            .allElementsBoundByIndex
    }
}
