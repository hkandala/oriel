import XCTest

/// The Diff plugin (phase 43, spec item 4): a repository's uncommitted changes or one commit, Unified or Side by
/// Side, a header per file and the file list; its links open the file's plugin in a new tab.
extension OrielUITests {
    /// An 80-line file and two short ones, committed, then changed: the diff, its file list, previous / next change,
    /// fold and Viewed, Side by Side, a refresh on a change, a commit from the source pop-up, Open File and ⌘-click.
    func testDiffShowsFoldsAndOpensItsChanges() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("diff")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-diff", root = "/private/tmp/oriel-e2e-diff"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: repo) }
        try await send("rm -rf \(repo) && mkdir \(repo) && cd \(repo) && git init -q && seq 1 80 > a.txt && "
            + "echo old > b.txt && seq 1 20 > c.txt && git add . && git -c user.name=e2e -c user.email=e2e@oriel "
            + "-c commit.gpgsign=false commit -qm first && seq 101 180 > a.txt && echo new > b.txt && seq 1 19 > c.txt "
            + "&& echo twenty >> c.txt && clear && echo ready-$((6*7))\r",
            to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, pane) = try await diffTab(root: root, cwd: repo)
        // A tab after it, so a tab opened right after it is not simply the last.
        let (after, _) = try await createTab(in: "w2")
        closeAfter("tab", after)
        let text = element("diff.\(pane).text"), lines = { text.stringValue.split(separator: "\n") }
        // c.txt's hunk starts at its line 17.
        try await expect("the uncommitted diff") {
            lines().contains("101") && lines().contains("new") && lines().contains("16 unmodified lines")
        }
        XCTAssertTrue(element("pane.\(pane).title").has(\.stringValue, "Changes", within: 3))
        XCTAssertTrue(element("diff.\(pane).list.a.txt").exists)
        // On a line near the top: the text runs far below the window.
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: 100)).click()
        XCTAssertTrue(hasKeyboard(text))

        steps(pane)
        try await folds(pane, lines)

        // Side by Side: the old lines on the left, the new on the right.
        element("pane.\(pane).diff.layout").radioButtons["Side by Side"].click()
        let right = element("diff.\(pane).new"), rightLines = { right.stringValue.split(separator: "\n") }
        try await expect("two sides") {
            lines().contains("old") && !lines().contains("new") && rightLines().contains("new")
                && !rightLines().contains("old")
        }
        keepScreenshot("diff, side by side")
        element("pane.\(pane).diff.layout").radioButtons["Unified"].click()
        XCTAssertTrue(right.vanishes(within: 2))

        // A change on disk shows without a reload.
        try await send("echo more >> b.txt\r", to: shell)
        try await expect("the new line", times: 100) { lines().contains("more") }
        // Its overview tile shows; the card has its diff view again after, with its lines.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(pane)").has(\.stringValue, "diff", within: 3))
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(pane)").vanishes(within: 3))
        XCTAssertTrue(until(3) { lines().contains("more") })
        try await commit(pane, root: root, text: text)
        try await links(pane, in: tab, root: root, text: text)
    }

    /// b.txt's header is below the first screen until Next Change, or the file list, reaches its lines.
    private func steps(_ pane: String) {
        let header = element("diff.\(pane).file.b.txt")
        XCTAssertFalse(header.exists)
        element("pane.\(pane).diff.next").click()
        XCTAssertFalse(header.exists)
        element("pane.\(pane).diff.next").click()
        XCTAssertTrue(header.exists(within: 2))
        element("pane.\(pane).diff.previous").click()
        XCTAssertTrue(header.vanishes(within: 2))
        element("diff.\(pane).list.b.txt").click()
        XCTAssertTrue(header.exists(within: 2))
        element("diff.\(pane).list.a.txt").click()
        XCTAssertTrue(header.vanishes(within: 2))
    }

    /// Viewed folds a file, and so does its disclosure; the list closes from row 2.
    private func folds(_ pane: String, _ lines: () -> [Substring]) async throws {
        let viewed = element("diff.\(pane).file.a.txt.viewed")
        viewed.click()
        XCTAssertTrue(until(2) { viewed.value as? Int == 1 })
        try await expect("a.txt folded") { !lines().contains("101") && lines().contains("new") }
        viewed.click()
        try await expect("a.txt shown") { lines().contains("101") }
        element("diff.\(pane).file.a.txt.fold").click()
        try await expect("a.txt folded") { !lines().contains("101") }
        element("diff.\(pane).file.a.txt.fold").click()
        try await expect("a.txt shown") { lines().contains("101") }
        element("pane.\(pane).diff.file-list").click()
        XCTAssertTrue(element("diff.\(pane).list.a.txt").vanishes(within: 2))
        element("pane.\(pane).diff.file-list").click()
        XCTAssertTrue(element("diff.\(pane).list.a.txt").exists(within: 2))
    }

    /// A tab with a diff pane of the uncommitted changes, as Oriel makes one; its tab and pane.
    private func diffTab(root: String, cwd: String) async throws -> (tab: String, pane: String) {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": cwd, "label": "oriel:diff#e2e42d \(root) uncommitted",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("diff.\(pane).card").exists(within: 5))
        return (tab, pane)
    }

    /// The source pop-up's commit: the label names it and the title is its short hash.
    private func commit(_ pane: String, root: String, text: XCUIElement) async throws {
        element("pane.\(pane).diff.source").click()
        element("pane.\(pane).diff.source").menuItems.matching(NSPredicate(format: "title ENDSWITH ' first'"))
            .firstMatch.click()
        let hash = try await poll("the commit's label") { () async throws -> String? in
            let words = try await paneLabel(pane).split(separator: " ")
            return words.count == 3 && words[1] == root && words[2].count == 40 ? String(words[2]) : nil
        }
        XCTAssertTrue(element("pane.\(pane).title").has(\.stringValue, String(hash.prefix(7)), within: 3))
        try await expect("the commit's diff") {
            let lines = text.stringValue.split(separator: "\n")
            return lines.contains("old") && !lines.contains("new") && !lines.contains("101")
        }
    }

    /// Open File and ⌘-click on a line: the file's plugin in a new tab right after this one, selected.
    private func links(_ pane: String, in tab: String, root: String, text: XCUIElement) async throws {
        let open = { self.element("diff.\(pane).file.b.txt.open").click() }
        let line = {
            // The commit's first line, under a.txt's header and its hunk's row.
            let line = text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 120, dy: 32 + 18 + 9))
            XCUIElement.perform(withKeyModifiers: .command) { line.click() }
        }
        for (click, file) in [(open, "b.txt"), (line, "a.txt")] {
            element("tab.\(tab)").click()
            XCTAssertTrue(text.exists(within: 3))
            let before = try await tabIDs()
            click()
            let opened = try await newTabID(after: before)
            closeAfter("tab", opened)
            try await expect("\(opened) right after \(tab)") {
                let order = try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]]
                    ?? []).compactMap { $0["tab_id"] as? String }
                return order.firstIndex(of: opened) == order.firstIndex(of: tab).map { $0 + 1 }
            }
            XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
            let label = try await paneLabel(self.pane(of: opened))
            XCTAssertTrue(label.hasPrefix("oriel:file#") && label.hasSuffix(" \(root)/\(file)"), label)
        }
    }
}
