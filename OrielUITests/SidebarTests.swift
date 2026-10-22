import XCTest

/// The sidebar (phase 14): one page per session open in the window, page dots, workspace rows with git data, the
/// footer and the Open Session sheet. Session one: w1 "alpha", w2 "beta"; session two: w1 "gamma"; three is
/// stopped; four is made by a test; five is stopped and started by tests.
extension OrielUITests {
    func testLaunchOpensOnePageAndNoOtherSession() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        XCTAssertEqual(header, one)
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        // The other sessions cost nothing: no bridge, no stream.
        let (runs, status) = try await Self.post("\(env("ORIEL_SESSION2"))/children", Data())
        XCTAssertEqual(status, 200)
        XCTAssertEqual(String(decoding: runs, as: UTF8.self), "")

        // Esc and Cancel close the sheet.
        let filter = openSessionSheet()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.waitForNonExistence(timeout: 2))
        openSessionSheet()
        app.buttons["Cancel"].click()
        XCTAssertTrue(filter.waitForNonExistence(timeout: 2))
    }

    func testOpenSessionListsSessionsAndOpensAPage() throws {
        let two = env("ORIEL_SESSION2"), three = env("ORIEL_SESSION3")
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        openSessionSheet()
        expect("open-session.session.\(two)", under: "Running", above: "Stopped")
        expect("open-session.session.\(three)", under: "Stopped", above: "Open in this window")
        expect("open-session.open.\(one)", under: "Open in this window", above: nil)
        // Empty field: a new name is offered first.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'open-session.new.'"))
            .firstMatch.isSelected)
        keepScreenshot("open session")
        element("open-session.session.\(two)").click()

        XCTAssertTrue(element("open-session.filter").waitForNonExistence(timeout: 2))
        try poll { header == two }
        XCTAssertTrue(element("sidebar.dot.\(one)").exists)
        XCTAssertTrue(element("sidebar.dot.\(two)").isSelected)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'workspace.w1' AND label == 'gamma'"))
            .firstMatch.waitForExistence(timeout: connect))
        keepScreenshot("two pages")
        element("sidebar.dot.\(one)").click()
        try poll { header == one }
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: 2))
    }

    func testShiftCommandNCreatesASessionAsANewPage() async throws {
        let four = env("ORIEL_SESSION4")
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(hasKeyboard(element("open-session.filter")))
        app.typeText(four)
        XCTAssertTrue(element("open-session.new.\(four)").wait(for: \.isSelected, toEqual: true, timeout: 2))
        app.typeKey(.return, modifierFlags: [])

        // The app starts the server and makes its first workspace; the new page shows it.
        try poll(timeout: connect) { header == four }
        XCTAssertTrue(element("workspace.w1").waitForExistence(timeout: connect))
        let snapshot = try await Self.call(four, "session.snapshot", [:])["snapshot"] as? [String: Any]
        XCTAssertEqual((snapshot?["workspaces"] as? [Any])?.count, 1)
        XCTAssertTrue(element("sidebar.dot.\(one)").exists)
    }

    func testOpenSessionStartsAStoppedSession() async throws {
        let five = env("ORIEL_SESSION5")
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        let stopped = try await Self.post("\(five)/stop", Data())
        XCTAssertEqual(stopped.status, 200, String(decoding: stopped.data, as: UTF8.self))
        openSessionSheet()
        // Other stopped sessions on this Mac may push its row out of the list's view.
        app.typeText(five)
        let row = element("open-session.session.\(five)")
        XCTAssertTrue(row.wait(for: \.isSelected, toEqual: true, timeout: 2))
        expect(row.identifier, under: "Stopped", above: nil)
        app.typeKey(.return, modifierFlags: [])

        try poll(timeout: connect) { header == five }
        try await Self.call(five, "session.snapshot", [:])
    }

    func testClosePageKeepsTheSessionRunning() async throws {
        let two = env("ORIEL_SESSION2")
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        openPage(two)
        element("sidebar.header").rightClick()
        app.menuItems["Close Page"].click()
        try poll { header == one }
        XCTAssertFalse(element("sidebar.dot.\(two)").exists)
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        try await Self.call(two, "session.snapshot", [:])

        // At its center: the page that slid away may leave it unhittable for a moment.
        element("sidebar.header").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        XCTAssertTrue(app.menuItems["Close Page"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.menuItems["Close Page"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testEmptyPageOffersNewWorkspace() async throws {
        let five = env("ORIEL_SESSION5")
        try await Self.post("\(five)/start", Data())
        let snapshot = try await poll("five to answer") { () async throws -> [String: Any]? in
            try? await Self.call(five, "session.snapshot", [:])["snapshot"] as? [String: Any]
        }
        for workspace in snapshot["workspaces"] as? [[String: Any]] ?? [] {
            try await Self.call(five, "workspace.close", ["workspace_id": workspace["workspace_id"] ?? ""])
        }
        app.terminate()
        app.launchArguments = ["-session", five, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        // The page and the strip each show only the button.
        let buttons = app.buttons.matching(identifier: "new-workspace")
        XCTAssertTrue(buttons.element(boundBy: 1).waitForExistence(timeout: connect))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'herdr'")).firstMatch.exists)
        keepScreenshot("empty page")
        buttons.element(boundBy: 1).click()
        let pane = try await poll("a workspace in herdr") { () async throws -> String? in
            let snapshot = try await Self.call(five, "session.snapshot", [:])["snapshot"] as? [String: Any]
            return (snapshot?["panes"] as? [[String: Any]])?.first?["pane_id"] as? String
        }
        XCTAssertTrue(element("terminal.\(pane)").waitForExistence(timeout: 5))
    }

    func testWorkspaceRowsShowGitAndWorktrees() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        // The sandboxed runner cannot run git: a pane of w2 (in /tmp) builds a repository with an upstream, one
        // commit ahead of it, and a linked worktree.
        let root = "/tmp/oriel-e2e-git-\(Int.random(in: 10000 ... 99999))"
        let git = "git -c user.name=e2e -c user.email=e2e@oriel"
        // In a subshell: w2 stays in /tmp, a folder outside any repository.
        let script = "(mkdir -p \(root) && cd \(root) && git init -q -b main repo && cd repo && "
            + "\(git) commit -q --allow-empty -m one && git clone -q --bare . ../up.git && "
            + "git remote add origin ../up.git && git fetch -q origin && git branch -q -u origin/main && "
            + "\(git) commit -q --allow-empty -m two && git worktree add -q ../tree -b feature) && echo built-$((6*7))"
        try await Self.call(one, "pane.send_text", ["pane_id": "w2:p1", "text": "\(script)\r"])
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": "w2:p1", "text": "rm -rf \(root)\r"])
        }
        try await waitFor("w2:p1") { $0.contains("\nbuilt-42") }
        let made = try await Self.call(one, "workspace.create", ["cwd": "\(root)/repo", "label": "repo",
                                                                 "focus": false])
        let repo = try XCTUnwrap((made["workspace"] as? [String: Any])?["workspace_id"] as? String)
        // herdr fills a workspace's worktree fields only through its worktree calls.
        let opened = try await Self.call(one, "worktree.open", ["workspace_id": repo, "path": "\(root)/tree",
                                                                "focus": false])
        let tree = try XCTUnwrap((opened["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "workspace.close", ["workspace_id": repo, "close_group": true])
        }

        let repoRow = element("workspace.\(repo)"), treeRow = element("workspace.\(tree)")
        try poll(timeout: 5) { repoRow.value as? String == "main ahead 1 behind 0" }
        try poll(timeout: 5) { treeRow.value as? String == "feature ahead 0 behind 0, worktree of repo" }
        XCTAssertEqual(repoRow.frame.height, 44, accuracy: 1)
        XCTAssertEqual(element("workspace.w2").frame.height, 30, accuracy: 1)
        XCTAssertEqual(treeRow.frame.minX - repoRow.frame.minX, 14, accuracy: 1)
        keepScreenshot("git rows")

        // A new commit shows within the 10 s refresh.
        try await Self.call(
            one,
            "pane.send_text",
            ["pane_id": "w2:p1",
             "text": "(cd \(root)/repo && \(git) commit -q --allow-empty -m 3)\r"],
        )
        try poll(timeout: 11) { repoRow.value as? String == "main ahead 2 behind 0" }

        // The filter matches branches; a matching worktree keeps its repository's row.
        let filter = element("sidebar.filter")
        filter.click()
        filter.typeText("feature")
        XCTAssertTrue(element("workspace.w2").waitForNonExistence(timeout: 2))
        XCTAssertTrue(treeRow.exists)
        XCTAssertTrue(repoRow.exists)
    }

    func testHeaderPlusAndRowMenuChangeHerdr() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        let before = try await workspaceIDs()
        element("sidebar.new-workspace").click()
        let made = try await poll("a new workspace") { () async throws -> String? in
            try await workspaceIDs().first { !before.contains($0) }
        }
        addTeardownBlock { [one] in
            // Unless the test closed it.
            let snapshot = try? await Self.call(one, "session.snapshot", [:])["snapshot"] as? [String: Any]
            if (snapshot?["workspaces"] as? [[String: Any]])?.contains(where: { $0["workspace_id"] as? String == made })
                == true
            {
                _ = try? await Self.call(one, "workspace.close", ["workspace_id": made])
            }
        }
        let row = element("workspace.\(made)")
        XCTAssertTrue(row.wait(for: \.isSelected, toEqual: true, timeout: 3))

        // Rename: the inline field, Enter saves.
        row.rightClick()
        app.menuItems["Rename Workspace"].click()
        let field = element("workspace.\(made).rename")
        XCTAssertTrue(hasKeyboard(field))
        field.typeKey("a", modifierFlags: .command)
        field.typeText("renamed\r")
        try await poll("herdr's label") { () async throws -> Bool? in
            try await workspaceLabel(made) == "renamed" ? true : nil
        }

        // Last; Move Up puts it before beta in herdr's order.
        row.rightClick()
        XCTAssertFalse(app.menuItems["Move Down"].isEnabled)
        app.menuItems["Move Up"].click()
        try await poll("herdr's order") { () async throws -> Bool? in
            try await workspaceIDs().suffix(2) == [made, "w2"] ? true : nil
        }

        row.rightClick()
        app.menuItems["Close Workspace"].click()
        // D41: it asks, with the tab and pane count.
        XCTAssertTrue(app.sheets.staticTexts["Its tab, pane and everything running in it will end, here and in every "
                + "herdr client. This cannot be undone."].waitForExistence(timeout: 2))
        app.sheets.buttons["Close Workspace"].click()
        try await poll("herdr to close it") { () async throws -> Bool? in
            try await workspaceIDs().contains(made) ? nil : true
        }
        XCTAssertTrue(row.waitForNonExistence(timeout: 2))
    }

    func testSidebarHandleResizesWithinItsBounds() {
        let sidebar = element("sidebar"), handle = element("sidebar.resize")
        XCTAssertTrue(element("pane.w1:p1").waitForExistence(timeout: connect))
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

    /// Opens the session's page through the sheet.
    func openPage(_ session: String) {
        openSessionSheet()
        element("open-session.session.\(session)").click()
        XCTAssertTrue(element("sidebar.dot.\(session)").waitForExistence(timeout: connect))
    }

    /// The footer's Open Session; the sheet's field has the keyboard.
    @discardableResult
    func openSessionSheet() -> XCUIElement {
        element("sidebar.open-session").click()
        let filter = element("open-session.filter")
        XCTAssertTrue(filter.waitForExistence(timeout: 2))
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    /// The page in view's session (a static text's value).
    private var header: String? {
        element("sidebar.header").value as? String
    }

    private func env(_ name: String) -> String {
        ProcessInfo.processInfo.environment[name] ?? ""
    }

    /// Polls an accessibility check every 100 ms.
    private func poll(timeout: TimeInterval = 3, _ check: () -> Bool) throws {
        let end = Date.now.addingTimeInterval(timeout)
        while !check() {
            guard Date.now < end else {
                XCTFail("timed out")
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func workspaceIDs() async throws -> [String] {
        let snapshot = try await snapshot()
        return (snapshot?["workspaces"] as? [[String: Any]] ?? []).compactMap { $0["workspace_id"] as? String }
    }

    private func workspaceLabel(_ id: String) async throws -> String? {
        let snapshot = try await snapshot()
        return (snapshot?["workspaces"] as? [[String: Any]])?.first { $0["workspace_id"] as? String == id }?["label"]
            as? String
    }
}
