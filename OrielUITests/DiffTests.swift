import XCTest

/// The Diff card (phase 44, web): a pane labeled `oriel:diff#<iid> <root> <source>` shows the patch in
/// `web/src/diff.ts` with the file list, and row 2 drives it.
extension OrielUITests {
    /// Uncommitted lists the changed and the untracked file; the source pop-up picks a commit (the label and the title
    /// follow, the page loads it); Next Change scrolls to a change the page has not drawn; Side by Side, the file list
    /// and Viewed change the page; ⌘-click on a line and Open File open the file in a new tab right after this one.
    func testDiffCardShowsAPatchAndOpensItsFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("diff")
        try await waitForPrompt(left)
        let repo = "/tmp/oriel-e2e-diff", root = "/private/tmp/oriel-e2e-diff"
        // A commit that changes lines 1-150 and line 290: its second change is far below the first.
        try await send("rm -rf \(repo) && mkdir \(repo) && cd \(repo) && git init -q && git config user.name e2e "
            + "&& git config user.email e2e@oriel && seq 300 | sed 's/^/line /' >a.txt && git add a.txt "
            + "&& git commit -qm first && sed -i '' '1,150s/line/LINE/; s/^line 290$/changed 290/' a.txt "
            + "&& git commit -qam second && echo new >b.md && sed -i '' 's/^line 200$/changed 200/' a.txt "
            + "&& clear && echo ready-$((6*7))\r", to: left)
        try await waitFor(left) { $0.contains("ready-42") }
        let hash = try await commit(in: repo, from: left)
        element("tab.\(tab)").click()
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "oriel:diff#e2ediff \(root) uncommitted"])

        let page = element("diff.\(card).page")
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 10))
        XCTAssertTrue(page.buttons["b.md"].exists)
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "Changes", within: 3))
        keepScreenshot("diff card, uncommitted")

        let source = element("pane.\(card).diff.source")
        source.click()
        source.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", String(hash.prefix(7)))).firstMatch.click()
        try await expect("the label names the commit") { try await paneLabel(card).hasSuffix(" \(root) \(hash)") }
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, String(hash.prefix(7)), within: 3))
        XCTAssertTrue(page.buttons["b.md"].vanishes(within: 10))
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))

        let far = page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'changed 290'")).firstMatch
        XCTAssertFalse(far.exists)
        element("pane.\(card).diff.next").click()
        element("pane.\(card).diff.next").click()
        XCTAssertTrue(far.exists(within: 3))

        element("pane.\(card).diff.layout").radioButtons["Side by Side"].click()
        XCTAssertTrue(page.descendants(matching: .any)["Side by Side"].exists(within: 3))
        keepScreenshot("diff card, side by side")
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].vanishes(within: 3))
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))

        try await opens("\(root)/a.txt", after: tab) { XCUIElement.perform(withKeyModifiers: .command) { far.click() } }
        element("tab.\(tab)").click()
        try await opens("\(root)/a.txt", after: tab) { page.buttons["Open a.txt"].click() }
        element("tab.\(tab)").click()

        page.checkBoxes["Viewed a.txt"].click()
        XCTAssertTrue(far.vanishes(within: 3))
        try await send("cd / && rm -rf \(repo)\r", to: left)
    }

    /// HEAD's hash, printed in the shell pane.
    private func commit(in repo: String, from pane: String) async throws -> String {
        try await send("clear && git -C \(repo) rev-parse HEAD\r", to: pane)
        return try await poll("HEAD's hash") {
            try await read(pane, in: nil).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        }
    }

    /// The action opens a file card for the path in a new tab right after `tab`, selected.
    private func opens(_ path: String, after tab: String, _ action: () -> Void) async throws {
        let before = try await tabIDs()
        action()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        try await expect("\(opened) right after \(tab)") {
            let order = try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]] ?? [])
                .compactMap { $0["tab_id"] as? String }
            return order.firstIndex(of: opened) == order.firstIndex(of: tab).map { $0 + 1 }
        }
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        let label = try await paneLabel(pane(of: opened))
        XCTAssertTrue(label.hasPrefix("oriel:file#") && label.hasSuffix(" \(path)"), label)
    }
}
