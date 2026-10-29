import XCTest

/// The Diff card (phase 44, web): a pane labeled `oriel:diff#<iid> <root> <source>` shows the patch in
/// `web/src/diff.ts` with the file list, and row 2 drives it.
extension OrielUITests {
    /// Uncommitted lists the changed and the untracked files and follows the work tree; the overview's tile shows
    /// the card; the source pop-up picks a commit (the label and the title follow, the page loads it); Open File
    /// opens the file in a new tab right after this one; Viewed folds the file and opens it again; Next Change
    /// scrolls to a change the page has not drawn; ⌘-click on a line opens the file at the line; Side by Side puts
    /// the old and the new line on one row; the file list hides.
    func testDiffCardShowsAPatchAndOpensItsFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("diff")
        try await waitForPrompt(left)
        let repo = "/tmp/oriel-e2e-diff", root = "/private/tmp/oriel-e2e-diff"
        let hash = try await makeRepo(repo, in: left)
        try await show(tab)
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "oriel:diff#e2edif \(root) uncommitted"])

        let page = element("diff.\(card).page")
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 10))
        XCTAssertTrue(page.buttons["b.md"].exists)
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "Changes", within: 3))
        keepScreenshot("diff card, uncommitted")
        // The overview's tile borrows the card's page, and the card gets it back.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "diff", within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))
        // A change in the work tree shows by itself.
        try await send("echo new >c.txt\r", to: left)
        XCTAssertTrue(page.buttons["c.txt"].exists(within: 10))

        try await pick(hash, in: card, root: root)
        XCTAssertTrue(page.buttons["b.md"].vanishes(within: 10))
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))

        // Clicks in the page wait for what it draws: its layout comes back late after the card was hidden.
        let open = page.buttons["Open a.txt"]
        XCTAssertTrue(open.has(\.isHittable, true, within: 3))
        _ = try await opens("\(root)/a.txt", after: tab) { open.click() }
        try await show(tab)
        let viewed = page.checkBoxes["Viewed a.txt"], line = page.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH 'line'"),
        ).firstMatch
        XCTAssertTrue(viewed.has(\.isHittable, true, within: 3) && line.exists)
        viewed.click()
        XCTAssertTrue(line.vanishes(within: 3))
        viewed.click()
        XCTAssertTrue(line.exists(within: 3))

        let far = page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'far290'")).firstMatch
        XCTAssertFalse(far.exists)
        element("pane.\(card).diff.next").click()
        element("pane.\(card).diff.next").click()
        XCTAssertTrue(far.has(\.isHittable, true, within: 3))
        // In Unified: a ~200 pt Side by Side column clips the line where the click lands (phase 44's findings).
        let file = try await opens("\(root)/a.txt", after: tab) {
            XCUIElement.perform(withKeyModifiers: .command) { far.click() }
        }
        // At the line: the editor draws only the lines in view.
        let editor = element("file.\(file).page").textViews.firstMatch
        XCTAssertTrue(until(5) { (editor.value as? String)?.contains("far290") == true })
        try await show(tab)
        try await sideBySide(card, page, far)
        try await send("cd / && rm -rf \(repo)\r", to: left)
    }

    /// Side by Side puts the old line and the new one on one row; the file list hides and comes back.
    private func sideBySide(_ card: String, _ page: XCUIElement, _ far: XCUIElement) async throws {
        element("pane.\(card).diff.layout").radioButtons["Side by Side"].click()
        let old = page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'line 290'")).firstMatch
        XCTAssertTrue(until(3) {
            old.exists && abs(old.frame.midY - far.frame.midY) < 2 && old.frame.maxX < far.frame.minX
        })
        keepScreenshot("diff card, side by side")
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].vanishes(within: 3))
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))
    }

    /// A repository with two commits and uncommitted changes, made in the shell pane; HEAD's hash.
    private func makeRepo(_ repo: String, in pane: String) async throws -> String {
        // A commit that changes lines 1-150 and line 290: its second change is far below the first.
        try await send("rm -rf \(repo) && mkdir \(repo) && cd \(repo) && git init -q && git config user.name e2e "
            + "&& git config user.email e2e@oriel && seq 300 | sed 's/^/line /' >a.txt && git add a.txt "
            + "&& git commit -qm first && sed -i '' '1,150s/line/LINE/; s/^line 290$/far290/' a.txt "
            + "&& git commit -qam second && echo new >b.md && sed -i '' 's/^line 200$/changed 200/' a.txt "
            + "&& clear && echo ready-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("ready-42") }
        try await send("clear && git -C \(repo) rev-parse HEAD\r", to: pane)
        return try await poll("HEAD's hash") {
            try await read(pane, in: nil).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        }
    }

    /// Picks the commit from the card's source pop-up: the label and the title name it.
    private func pick(_ hash: String, in card: String, root: String) async throws {
        let source = element("pane.\(card).diff.source")
        source.click()
        source.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", String(hash.prefix(7)))).firstMatch.click()
        try await expect("the label names the commit") { try await paneLabel(card).hasSuffix(" \(root) \(hash)") }
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, String(hash.prefix(7)), within: 3))
    }

    /// The action opens a file card for the path in a new tab right after `tab`, selected; its pane.
    private func opens(_ path: String, after tab: String, _ action: () -> Void) async throws -> String {
        let before = try await tabIDs()
        action()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        try await expect("\(opened) right after \(tab)") {
            let index = try await order(of: opened), before = try await order(of: tab)
            return index != nil && index == before.map { $0 + 1 }
        }
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        let pane = try await pane(of: opened), label = try await paneLabel(pane)
        XCTAssertTrue(label.hasPrefix("oriel:file#") && label.hasSuffix(" \(path)"), label)
        return pane
    }
}
