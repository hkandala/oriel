import XCTest

/// The sidebar's git line and its menu: a repository's row shows its branch and runs Fetch, Pull and Push.
extension OvviUITests {
    /// A repository's row shows the branch with ahead and behind, a linked worktree sits under it, the line follows a
    /// commit, and the filter matches branches. Its menu's Fetch, Pull and Push run git (`sync`).
    func testWorkspaceRowsShowGitWorktreesAndSync() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // The sandboxed runner cannot run git: a pane of w2 (in /tmp) builds a repository one commit ahead of its
        // upstream and one behind it, and a linked worktree.
        let root = "/tmp/ovvi-e2e-git-\(Int.random(in: 10000 ... 99999))"
        let git = "git -c user.name=e2e -c user.email=e2e@ovvi"
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
        try await sync(repoRow, root: root, git: git)

        // The filter matches branches; a matching worktree keeps its repository's row.
        let filter = element("sidebar.filter")
        filter.click()
        filter.typeText("feature")
        XCTAssertTrue(element("workspace.w2").vanishes(within: 2))
        XCTAssertTrue(treeRow.exists)
        XCTAssertTrue(repoRow.exists)
    }

    /// Fetch, Pull and Push after a separator only on a repository's row: Fetch brings a commit another clone pushed,
    /// Push's refusal shows git's words in the notice, and Pull brings the commit; the line follows each at once.
    private func sync(_ row: XCUIElement, root: String, git: String) async throws {
        element("workspace.w2").rightClick()
        XCTAssertTrue(app.menuItems["Move Down"].exists(within: 2))
        XCTAssertFalse(app.menuItems["Fetch"].exists)
        keepScreen("menu without a repository")
        app.typeKey(.escape, modifierFlags: [])
        try await send("(cd \(root) && git clone -q up.git other && cd other && \(git) commit -q --allow-empty -m four "
            + "&& git push -q origin main) && echo pushed-$((6*7))\r", to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\npushed-42") }
        row.rightClick()
        XCTAssertTrue(app.menuItems["Push"].exists(within: 2))
        keepScreen("menu of a repository")
        app.menuItems["Fetch"].click()
        XCTAssertTrue(until(10) { row.value as? String == "main ahead 2 behind 2" }, "\(row.value ?? "")")

        row.rightClick()
        XCTAssertTrue(app.menuItems["Push"].exists(within: 2))
        app.menuItems["Push"].click()
        XCTAssertTrue(element("detail.notice").staticTexts.matching(NSPredicate(format: "value CONTAINS 'rejected'"))
            .firstMatch.exists(within: 10))

        // One behind and none ahead: Pull fast-forwards.
        try await send("(cd \(root)/repo && git reset -q --hard origin/main~1) && echo reset-$((6*7))\r", to: "w2:p1")
        try await waitFor("w2:p1") { $0.contains("\nreset-42") }
        row.rightClick()
        XCTAssertTrue(app.menuItems["Pull"].exists(within: 2))
        app.menuItems["Pull"].click()
        XCTAssertTrue(until(10) { row.value as? String == "main ahead 0 behind 0" }, "\(row.value ?? "")")
    }
}
