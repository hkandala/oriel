import XCTest

/// The sidebar (phase 14): one page per session open in the window, page dots, workspace rows with git data, the
/// footer and the Open Session sheet. Session one: w1 "alpha", w2 "beta"; session two: w1 "gamma"; three is
/// stopped; four is made by a test; five is stopped and started by tests.
extension OrielUITests {
    func testLaunchOpensOnePageAndNoOtherSession() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        XCTAssertEqual(header, one)
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        // The other sessions cost nothing: no bridge, no stream.
        let runs = try await runs(two)
        XCTAssertEqual(runs, [])

        // Esc and a click outside close the panel.
        let filter = openSessionSheet()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        openSessionSheet()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).click()
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    func testOpenSessionListsSessionsAndOpensAPage() {
        let three = env("ORIEL_SESSION3")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openSessionSheet()
        expect("open-session.session.\(two)", under: "Running", above: "Stopped")
        expect("open-session.session.\(three)", under: "Stopped", above: "Open in this window")
        expect("open-session.open.\(one)", under: "Open in this window", above: nil)
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
    }

    func testShiftCommandNCreatesASessionAsANewPage() async throws {
        let four = env("ORIEL_SESSION4")
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
        let five = env("ORIEL_SESSION5")
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        try await running(five)
        try await Self.post("\(five)/stop")
        openSessionSheet()
        // Other stopped sessions on this Mac may push its row out of the list's view.
        app.typeText(five)
        let row = element("open-session.session.\(five)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))
        expect(row.identifier, under: "Stopped", above: nil)
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(until(connect) { header == five })
        try await Self.snapshot(five)
    }

    func testClosePageKeepsTheSessionRunning() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        // From the dot's menu (closePage uses the header's).
        element("sidebar.dot.\(two)").rightClick()
        app.windows.firstMatch.menuItems["Close Page"].click()
        XCTAssertTrue(until(3) { header == one })
        XCTAssertFalse(element("sidebar.dot.\(two)").exists)
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        // The session still runs (testClosingAPageAndQuittingLeaveNoStreams checks its runs end).
        try await Self.snapshot(two)

        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        XCTAssertTrue(app.windows.firstMatch.menuItems["Close Page"].exists(within: 2))
        XCTAssertFalse(app.windows.firstMatch.menuItems["Close Page"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testEmptyPageOffersNewWorkspace() async throws {
        let five = env("ORIEL_SESSION5")
        for workspace in try await running(five)["workspaces"] as? [[String: Any]] ?? [] {
            try await Self.call(five, "workspace.close", ["workspace_id": workspace["workspace_id"] ?? ""])
        }
        relaunch(five)
        // The page and the strip each show only the button.
        let buttons = app.buttons.matching(identifier: "new-workspace")
        XCTAssertTrue(buttons.element(boundBy: 1).exists(within: connect))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.'")).firstMatch
            .exists)
        keepScreenshot("empty page")
        buttons.element(boundBy: 1).click()
        let pane = try await poll("a workspace in herdr") { () async throws -> String? in
            try await (Self.snapshot(five)["panes"] as? [[String: Any]])?.first?["pane_id"] as? String
        }
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 5))
    }

    func testWorkspaceRowsShowGitAndWorktrees() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // The sandboxed runner cannot run git: a pane of w2 (in /tmp) builds a repository one commit ahead of its
        // upstream and one behind it, and a linked worktree.
        let root = "/tmp/oriel-e2e-git-\(Int.random(in: 10000 ... 99999))"
        let git = "git -c user.name=e2e -c user.email=e2e@oriel"
        // In a subshell: w2 stays in /tmp, a folder outside any repository.
        let script = "(mkdir -p \(root) && cd \(root) && git init -q -b main repo && cd repo && "
            + "\(git) commit -q --allow-empty -m one && git clone -q --bare . ../up.git && "
            + "git remote add origin ../up.git && git fetch -q origin && git branch -q -u origin/main && "
            // Pushed, then replaced: one commit behind the upstream and one ahead of it.
            + "\(git) commit -q --allow-empty -m two && git push -q origin main && git reset -q --hard HEAD~1 && "
            + "\(git) commit -q --allow-empty -m three && git worktree add -q ../tree -b feature) && "
            + "echo built-$((6*7))"
        try await send("\(script)\r", to: "w2:p1")
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": "w2:p1", "text": "rm -rf \(root)\r"])
        }
        try await waitFor("w2:p1") { $0.contains("\nbuilt-42") }
        let repo = try await workspace(of: createWorkspace("repo", cwd: "\(root)/repo").tab)
        // herdr fills a workspace's worktree fields only through its worktree calls.
        let tree = try await id(Self.call(one, "worktree.open", ["workspace_id": repo, "path": "\(root)/tree",
                                                                 "focus": false]), "workspace")
        closeAfter("workspace", tree)

        let repoRow = element("workspace.\(repo)"), treeRow = element("workspace.\(tree)")
        XCTAssertTrue(until(5) { repoRow.value as? String == "main ahead 1 behind 1" })
        XCTAssertTrue(until(5) { treeRow.value as? String == "feature ahead 0 behind 0, worktree of repo" })
        XCTAssertEqual(repoRow.frame.height, 44, accuracy: 1)
        XCTAssertEqual(element("workspace.w2").frame.height, 30, accuracy: 1)
        XCTAssertEqual(treeRow.frame.minX - repoRow.frame.minX, 14, accuracy: 1)
        keepScreenshot("git rows")

        // A new commit shows within the 10 s refresh.
        try await send("(cd \(root)/repo && \(git) commit -q --allow-empty -m 3) && echo committed-$((6*7))\r",
                       to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\ncommitted-42") }
        XCTAssertTrue(until(12) { repoRow.value as? String == "main ahead 2 behind 1" })

        // The filter matches branches; a matching worktree keeps its repository's row.
        let filter = element("sidebar.filter")
        filter.click()
        filter.typeText("feature")
        XCTAssertTrue(element("workspace.w2").vanishes(within: 2))
        XCTAssertTrue(treeRow.exists)
        XCTAssertTrue(repoRow.exists)
    }

    func testHeaderPlusAndRowMenuChangeHerdr() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let before = try await workspaceIDs()
        element("sidebar.new-workspace").click()
        let made = try await poll("a new workspace") { () async throws -> String? in
            try await workspaceIDs().first { !before.contains($0) }
        }
        closeAfter("workspace", made)
        let row = element("workspace.\(made)")
        XCTAssertTrue(row.has(\.isSelected, true, within: 3))

        // Rename: the inline field, Enter saves.
        row.rightClick()
        app.menuItems["Rename Workspace"].click()
        let field = element("workspace.\(made).rename")
        XCTAssertTrue(hasKeyboard(field))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("renamed\r")
        try await expect("herdr's label") { try await workspaceLabel(made) == "renamed" }

        // Last; Move Up puts it before beta in herdr's order.
        row.rightClick()
        XCTAssertFalse(app.menuItems["Move Down"].isEnabled)
        app.menuItems["Move Up"].click()
        try await expect("herdr's order") { try await workspaceIDs().suffix(2) == [made, "w2"] }
        // The sidebar shows the new order before the next move.
        XCTAssertTrue(until(3) { row.frame.maxY <= element("workspace.w2").frame.minY })
        row.rightClick()
        app.menuItems["Move Down"].click()
        try await expect("herdr's order back") { try await workspaceIDs().last == made }

        row.rightClick()
        app.windows.firstMatch.menuItems["Close Workspace"].click()
        // D41: it asks, with the tab and pane count.
        XCTAssertTrue(app.sheets.staticTexts["Its tab, pane and everything running in it will end, here and in every "
                + "herdr client. This cannot be undone."].exists(within: 2))
        app.sheets.buttons["Close Workspace"].click()
        try await expect("herdr to close it") { try await !workspaceIDs().contains(made) }
        XCTAssertTrue(row.vanishes(within: 2))
    }

    /// A double-click on a row renames too; Esc keeps herdr's label.
    func testDoubleClickRenamesAndEscapeCancels() async throws {
        let row = element("workspace.w2"), field = element("workspace.w2.rename")
        XCTAssertTrue(row.exists(within: connect))
        row.doubleClick()
        XCTAssertTrue(hasKeyboard(field))
        field.typeText("other")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 2))
        // For a second: a wrong save would land a moment later.
        for _ in 0 ..< 10 {
            let label = try await workspaceLabel("w2")
            XCTAssertEqual(label, "beta")
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(row.label, "beta")
    }

    func testSidebarHandleResizesWithinItsBounds() {
        let sidebar = element("sidebar"), handle = element("sidebar.resize")
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        let start = sidebar.frame.width
        let drag = { (offset: CGFloat) in
            let from = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.click(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: offset, dy: 0)))
        }
        drag(60)
        XCTAssertEqual(sidebar.frame.width, start + 60, accuracy: 2)
        drag(-600)
        XCTAssertEqual(sidebar.frame.width, 227, accuracy: 1)
        drag(600)
        XCTAssertEqual(sidebar.frame.width, 480, accuracy: 1)
        drag(start - 480)
    }

    /// The sheet's row sits in this group: below its header, above the next one.
    private func expect(_ row: String, under section: String, above next: String?) {
        let frame = element(row).frame
        XCTAssertGreaterThan(frame.minY, element("open-session.section.\(section)").frame.maxY, row)
        if let next {
            XCTAssertLessThan(frame.maxY, element("open-session.section.\(next)").frame.minY, row)
        }
    }

    /// Opens the session's page through the sheet, in this window when there are several.
    func openPage(_ session: String, in window: XCUIElement? = nil) {
        openSessionSheet(in: window)
        element("open-session.session.\(session)", in: window).click()
        XCTAssertTrue(element("sidebar.dot.\(session)", in: window).exists(within: connect))
    }

    /// Shows the session's page and closes it from its header's context menu (in the window, not the menu bar's File ▸
    /// Close Page).
    func closePage(_ session: String, in window: XCUIElement? = nil) {
        let dot = element("sidebar.dot.\(session)", in: window)
        dot.click()
        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header", in: window).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        (window ?? app.windows.firstMatch).menuItems["Close Page"].click()
        XCTAssertTrue(dot.vanishes(within: 3))
    }

    /// The footer's Open Session; the sheet's field has the keyboard.
    @discardableResult
    func openSessionSheet(in window: XCUIElement? = nil) -> XCUIElement {
        element("sidebar.open-session", in: window).click()
        let filter = element("open-session.filter", in: window)
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    /// The page in view's session (a static text's value).
    private var header: String? {
        element("sidebar.header").value as? String
    }

    func workspaceIDs() async throws -> [String] {
        try await Self.ids("workspace", in: one)
    }

    private func workspaceLabel(_ id: String) async throws -> String? {
        let snapshot = try await snapshot()
        return (snapshot["workspaces"] as? [[String: Any]])?.first { $0["workspace_id"] as? String == id }?["label"]
            as? String
    }
}
