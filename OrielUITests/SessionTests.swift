import XCTest

/// The window's sessions (phases 14, 25): Open Session lists, opens, starts, stops and deletes sessions; a session
/// opened goes last; Detach Session leaves one running. Sessions as in SidebarTests.
extension OrielUITests {
    func testOpenSessionListsSessionsAndOpensAPage() throws {
        let three = try env("ORIEL_SESSION3")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionPanel()
        expectRow("open-session.session.\(two)", under: "Running", above: "Stopped")
        expectRow("open-session.session.\(three)", under: "Stopped", above: "Open in this window")
        expectRow("open-session.open.\(one)", under: "Open in this window", above: nil)
        // Empty field: a new name is offered first.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'open-session.new.'"))
            .firstMatch.isSelected)
        // Only this run's sessions, so all four groups are in view.
        app.typeText(String(one.dropLast()))
        XCTAssertTrue(element("open-session.new.\(one.dropLast())").exists(within: 2))
        keepScreenshot("open session")
        element("open-session.session.\(two)").click()

        XCTAssertTrue(element("open-session.filter").vanishes(within: 2))
        XCTAssertTrue(until(3) { header == two })
        XCTAssertTrue(element("sidebar.dot.\(one)").exists)
        XCTAssertTrue(element("sidebar.dot.\(two)").isSelected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'workspace.w1' AND label == 'gamma'"))
            .firstMatch.exists(within: connect))
        keepScreenshot("two pages")
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        XCTAssertTrue(element("workspace.w2").exists(within: 2))

        // The workspace menu has a group per page; another page's workspace shows that page.
        element("sidebar.dot.\(two)").click()
        XCTAssertTrue(until(3) { header == two })
        app.typeKey("s", modifierFlags: [.command, .control])
        let button = element("titlebar.workspace")
        XCTAssertTrue(button.exists(within: 2))
        button.click()
        XCTAssertTrue(element("workspaces.\(two).w1").exists(within: 2))
        element("workspaces.\(one).w2").click()
        XCTAssertTrue(until(3) { button.value as? String == "\(one) | beta" })
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
        XCTAssertTrue(until(3) { header == one })

        // Enter on a page open in this window shows it; no page opens or closes.
        element("sidebar.dot.\(two)").click()
        XCTAssertTrue(until(3) { header == two })
        openSessionPanel()
        app.typeText(one)
        XCTAssertTrue(element("open-session.open.\(one)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(until(3) { header == one })
        XCTAssertTrue(element("sidebar.dot.\(two)").exists)
    }

    func testShiftCommandNCreatesASessionAsANewPage() async throws {
        let four = try env("ORIEL_SESSION4")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(hasKeyboard(element("open-session.filter")))
        app.typeText(four)
        XCTAssertTrue(element("open-session.new.\(four)").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])

        // The app starts the server and makes its first workspace; the new page shows it.
        XCTAssertTrue(until(connect) { header == four })
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let snapshot = try await Self.snapshot(four)
        XCTAssertEqual((snapshot["workspaces"] as? [Any])?.count, 1)
        XCTAssertTrue(element("sidebar.dot.\(one)").exists)
    }

    func testOpenSessionStartsAStoppedSession() async throws {
        let five = try env("ORIEL_SESSION5")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        try await running(five)
        try await Self.post("\(five)/stop")
        openSessionPanel()
        // Other stopped sessions on this Mac may push its row out of the list's view.
        app.typeText(five)
        let row = element("open-session.session.\(five)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))
        expectRow(row.identifier, under: "Stopped", above: nil)
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(until(connect) { header == five })
        try await Self.snapshot(five)
    }

    /// Open Session's lit running row has Stop; once stopped, Delete. Both ask first.
    func testOpenSessionStopsAndDeletesASession() async throws {
        let seven = try env("ORIEL_SESSION7")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionPanel()
        app.typeText(seven)
        let row = element("open-session.session.\(seven)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))
        expectRow(row.identifier, under: "Running", above: nil)
        XCTAssertFalse(element("\(row.identifier).delete").exists)
        keepScreenshot("stop on the lit row")
        element("\(row.identifier).stop").click()
        let stop = app.sheets.buttons["Stop Session"]
        XCTAssertTrue(stop.exists(within: 2))
        stop.click()
        XCTAssertTrue(element("\(row.identifier).delete").exists(within: 10))
        expectRow(row.identifier, under: "Stopped", above: nil)
        let stopped = try? await Self.snapshot(seven)
        XCTAssertNil(stopped)

        element("\(row.identifier).delete").click()
        let confirm = app.sheets.buttons["Delete Session"]
        XCTAssertTrue(confirm.exists(within: 2))
        keepScreenshot("delete asks")
        confirm.click()
        XCTAssertTrue(row.vanishes(within: 10))
        // Deleted: the name is free again.
        XCTAssertTrue(element("open-session.new.\(seven)").exists(within: 2))
    }

    /// A session opened goes last in the window's sessions, not beside the one in view.
    func testOpenedSessionsGoLast() async throws {
        let five = try env("ORIEL_SESSION5")
        try await running(five)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        openPage(five)
        let dots = [one, two, five].map { element("sidebar.dot.\($0)").frame.midX }
        XCTAssertEqual(dots, dots.sorted())
    }

    func testDetachSessionKeepsTheSessionRunning() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        // From the dot's menu (closePage uses the header's).
        element("sidebar.dot.\(two)").rightClick()
        app.windows.firstMatch.menuItems["Detach Session"].click()
        XCTAssertTrue(until(3) { header == one })
        XCTAssertFalse(element("sidebar.dot.\(two)").exists)
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        // The session still runs (testClosingAPageAndQuittingLeaveNoStreams checks its runs end).
        try await Self.snapshot(two)

        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        XCTAssertTrue(app.windows.firstMatch.menuItems["Detach Session"].exists(within: 2))
        XCTAssertFalse(app.windows.firstMatch.menuItems["Detach Session"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// The panel's row sits in this group: below its header, above the next one.
    private func expectRow(_ row: String, under section: String, above next: String?) {
        let frame = element(row).frame
        XCTAssertGreaterThan(frame.minY, element("open-session.section.\(section)").frame.maxY, row)
        if let next {
            XCTAssertLessThan(frame.maxY, element("open-session.section.\(next)").frame.minY, row)
        }
    }

    /// Opens the session's page through the panel, in this window when there are several.
    func openPage(_ session: String, in window: XCUIElement? = nil) {
        openSessionPanel(in: window)
        element("open-session.session.\(session)", in: window).click()
        XCTAssertTrue(element("sidebar.dot.\(session)", in: window).exists(within: connect))
    }

    /// Shows the session's page and closes it from its header's context menu (in the window, not the menu bar's File ▸
    /// Detach Session).
    func closePage(_ session: String, in window: XCUIElement? = nil) {
        let dot = element("sidebar.dot.\(session)", in: window)
        dot.click()
        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header", in: window).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        (window ?? app.windows.firstMatch).menuItems["Detach Session"].click()
        XCTAssertTrue(dot.vanishes(within: 3))
    }

    /// The footer's Open Session; the panel's field has the keyboard.
    @discardableResult
    func openSessionPanel(in window: XCUIElement? = nil) -> XCUIElement {
        element("sidebar.open-session", in: window).click()
        let filter = element("open-session.filter", in: window)
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    /// The page in view's session (a static text's value).
    var header: String? {
        element("sidebar.header").value as? String
    }
}
