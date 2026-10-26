import XCTest

/// The sidebar (phase 14): one page per session open in the window, page dots, workspace rows with git data, the
/// footer and the Open Session panel. Session one: w1 "alpha", w2 "beta"; session two: w1 "gamma"; three is
/// stopped; four is made by a test; five is stopped and started by tests; seven is stopped and deleted by a test.
extension OrielUITests {
    func testLaunchOpensOnePageAndNoOtherSession() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        XCTAssertEqual(header, one)
        XCTAssertFalse(element("sidebar.dot.\(one)").exists)
        // The other sessions cost nothing: no bridge, no stream.
        let runs = try await runs(two)
        XCTAssertEqual(runs, [])

        // Esc and a click outside close the panel.
        let filter = openSessionPanel()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(filter.vanishes(within: 2))
        openSessionPanel()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).click()
        XCTAssertTrue(filter.vanishes(within: 2))
    }

    /// With the sidebar collapsed, the light of the workspace menu, of Open Session and of the palette follows the
    /// pointer (user, phases 24 and 29).
    func testMenuLightFollowsThePointer() {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(element("titlebar.workspace").exists(within: 2))
        element("titlebar.workspace").click()
        let alpha = element("workspaces.\(one).w1"), beta = element("workspaces.\(one).w2")
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 2))
        beta.hover()
        XCTAssertTrue(beta.has(\.isSelected, true, within: 2))
        XCTAssertFalse(alpha.isSelected)
        element("workspaces.open-session").click()
        let open = element("open-session.session.\(two)") // above the fold: other tests' sessions push rows down
        XCTAssertTrue(open.exists(within: 2))
        XCTAssertFalse(open.isSelected)
        open.hover()
        XCTAssertTrue(open.has(\.isSelected, true, within: 2))
        keepScreenshot("open session lit by the pointer")
        app.typeKey(.escape, modifierFlags: [])
        // The light moves in the hover's own update with or without a fade: the fade itself (phase 29) needs an eye.
        app.typeKey("k", modifierFlags: .command)
        let tab = element("palette.tab.w1:t1"), workspace = element("palette.workspace.\(one).w2")
        XCTAssertTrue(workspace.exists(within: 2))
        workspace.hover()
        XCTAssertTrue(workspace.has(\.isSelected, true, within: 2))
        tab.hover()
        XCTAssertTrue(tab.has(\.isSelected, true, within: 2))
        XCTAssertFalse(workspace.isSelected)
    }

    /// With ⌥ held, a swipe anywhere (over a card here) moves between sessions sideways, with the sidebar's pages, and
    /// between workspaces up or down, one step a gesture, and never pages the strip (phase 30); so does a wheel.
    func testOptionSwipesMoveBetweenSessionsAndWorkspaces() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(until(3) { header == one })
        let card = element("terminal.w1:p1").frame, center = "\(card.midX) \(card.midY)"
        // 14 steps of 10 pt (625 pt/s) with ⌥; the other way if natural scrolling is off.
        var forward = -1.0
        for sign in [-1.0, 1.0] where header != two {
            forward = sign
            try await Self.post("\(one)/swipe", Data("\(center) \(10 * sign) 14 0 0 1".utf8))
            _ = until(1.5) { header == two }
        }
        XCTAssertEqual(header, two)
        try await Self.post("\(one)/swipe", Data("\(center) \(-10 * forward) 14 0 0 1".utf8))
        XCTAssertTrue(until(3) { header == one })
        // A sideways swipe that reached the strip would have shown t2.
        XCTAssertTrue(element("tab.w1:t1").isSelected)

        // Session one has two workspaces: a step either way shows w2, and the other way back w1.
        let alpha = element("workspace.w1")
        XCTAssertTrue(alpha.isSelected)
        try await Self.post("\(one)/swipe", Data("\(center) 10 4 0 1 1".utf8))
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 3))
        try await Self.post("\(one)/swipe", Data("\(center) -10 4 0 1 1".utf8))
        XCTAssertTrue(alpha.has(\.isSelected, true, within: 3))
        XCTAssertEqual(header, one)

        // A wheel with ⌥: a workspace too.
        let terminal = element("terminal.w1:p1")
        XCUIElement.perform(withKeyModifiers: .option) {
            terminal.scroll(byDeltaX: 0, deltaY: 30)
        }
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 3))
    }

    /// A sideways swipe over the sidebar pages it and never the strip; over a card it pages the strip and never the
    /// sidebar. In the Agents view it shows the other page's agents.
    func testSwipesPageTheSidebarAndTheStripApart() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        openPage(two)
        element("sidebar.dot.\(one)").click()
        let sidebar = element("sidebar"), header = element("sidebar.header")
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        try await swipe(sidebar, until: header, \.stringValue, two)
        try await swipe(sidebar, until: header, \.stringValue, one)
        // Page one's strip has two tabs: a swipe that reached it would have left t2 selected.
        XCTAssertTrue(element("tab.w1:t1").isSelected)
        // Near the card's left edge, where page two of the sidebar lies, off to the side (phase 28).
        let edge = element("terminal.w1:p1").coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 30, dy: 0))
        var delta = -Double(element("terminal.w1:p1").frame.width)
        XCTAssertTrue(until(6) {
            edge.hover()
            edge.scroll(byDeltaX: delta, deltaY: 0)
            delta = -delta
            return self.element("tab.w1:t2").has(\.isSelected, true, within: 0.7)
        })
        XCTAssertEqual(header.stringValue, one)

        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("agents.sort").exists(within: 2))
        try await swipe(sidebar, until: header, \.stringValue, two)
    }

    /// With three sessions, the page a swipe lands on shows its rows, in the sidebar, at rest: from 8c524dd a page not
    /// laid out took no room, so every page but the first showed blank once a swipe settled (phase 28).
    func testSwipedSessionPagesShowTheirRows() async throws {
        let five = try env("ORIEL_SESSION5")
        try await running(five)
        openPage(two)
        openPage(five)
        element("sidebar.dot.\(one)").click()
        let sidebar = element("sidebar"), header = element("sidebar.header")
        XCTAssertTrue(header.has(\.stringValue, one, within: 3))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.'"))
        // The first page goes nowhere the other way: then the next swipe goes forward.
        var delta = -Double(sidebar.frame.width)
        for session in [two, five] {
            sidebar.hover()
            sidebar.scroll(byDeltaX: delta, deltaY: 0)
            if !header.has(\.stringValue, session, within: 1.5) {
                delta = -delta
                sidebar.scroll(byDeltaX: delta, deltaY: 0)
            }
            XCTAssertTrue(header.has(\.stringValue, session, within: 1.5))
            try await Task.sleep(for: .seconds(0.5))
            XCTAssertTrue(rows.firstMatch.exists(within: 3), session)
            XCTAssertTrue(sidebar.frame.contains(rows.firstMatch.frame), "\(rows.firstMatch.frame) \(sidebar.frame)")
            XCTAssertTrue(rows.firstMatch.isHittable, session)
        }
    }

    /// ⌘Q and a relaunch bring back the window's pages that still run, the page in view and each page's workspace.
    func testRelaunchRestoresThePagesThatStillRun() async throws {
        let five = try env("ORIEL_SESSION5")
        try await running(five)
        // Not relaunch: a launch with -ApplePersistenceIgnoreState saves no state at ⌘Q (CI 39902793320). -session
        // keeps any saved pages out; ⌘Q saves whatever the Mac's "close windows when quitting" setting says.
        app.launchArguments = ["-session", one, "-NSQuitAlwaysKeepsWindows", "YES"]
        app.launch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
        openPage(five)
        openPage(two)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await Self.post("\(five)/stop")

        // No -session, which wins over the saved pages; if they did not come back, the window opens one, never the
        // user's default.
        app.launchArguments = ["-defaultSession", one]
        app.launch()
        XCTAssertTrue(until(connect) { header == two })
        XCTAssertTrue(element("sidebar.dot.\(one)").exists)
        XCTAssertFalse(element("sidebar.dot.\(five)").exists)
        element("sidebar.dot.\(one)").click()
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: connect))
    }

    func testEmptyPageOffersNewWorkspace() async throws {
        let five = try env("ORIEL_SESSION5")
        for workspace in try await running(five)["workspaces"] as? [[String: Any]] ?? [] {
            try await Self.call(five, "workspace.close", ["workspace_id": workspace["workspace_id"] ?? ""])
        }
        relaunch(five)
        // The page shows the button; the strip, no button, only that the session is empty (user, phase 28).
        let button = element("new-workspace")
        XCTAssertTrue(element("detail.empty").firstMatch.exists(within: connect))
        XCTAssertTrue(app.staticTexts["This session is empty"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "new-workspace").count, 1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.'")).firstMatch
            .exists)
        keepScreenshot("empty page")
        button.click()
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

        // New Tab: a tab of it in herdr, selected.
        let tabs = try await tabIDs()
        row.rightClick()
        // In the window, not the menu bar's File ▸ New Tab.
        app.windows.firstMatch.menuItems["New Tab"].click()
        let tab = try await newTabID(after: tabs)
        XCTAssertEqual(workspace(of: tab), made)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))

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

        try await runSleep(pane(of: tab))
        try await settle(tabIDs().filter { workspace(of: $0) == made })
        row.rightClick()
        app.windows.firstMatch.menuItems["Close Workspace"].click()
        // D41: a program runs, so it asks, with what runs and the tab and pane count.
        // A predicate: a query by identifier takes at most 128 characters.
        let text = "sleep is running in it. Its 2 tabs, 2 panes and everything running in them will end, here and "
            + "in every herdr client. This cannot be undone."
        XCTAssertTrue(app.sheets.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", text, text))
            .firstMatch.exists(within: 2))
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

    func workspaceIDs() async throws -> [String] {
        try await Self.ids("workspace", in: one)
    }

    func workspaceLabel(_ id: String) async throws -> String? {
        let snapshot = try await snapshot()
        return (snapshot["workspaces"] as? [[String: Any]])?.first { $0["workspace_id"] as? String == id }?["label"]
            as? String
    }
}
