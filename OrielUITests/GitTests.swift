import XCTest

/// The Git card (phase 46): a pane labeled `oriel:git#<iid> <root>` shows its home (`web/src/git.ts`) with row 2's
/// branch and buttons; `<root> <source>` shows a diff (`web/src/diff.ts`). The writes run in a throwaway repository.
extension OrielUITests {
    /// The home lists every branch's commits and the changes; Stage moves a file to the staged list, Commit commits it
    /// with the typed message, Push sends it to the remote; a commit opens its diff in the card, and Back and Forward
    /// walk between the home and the diff; the branch menu switches the branch. The diff: Uncommitted from a change
    /// follows the work tree; Open File opens the file in a new tab right after this one; Viewed folds the file;
    /// Next Change scrolls to a change the page has not drawn; ⌘-click on a line opens the file at the line, in
    /// Unified and in Side by Side; the file list hides.
    func testGitCardCommitsPushesAndOpensDiffs() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("git")
        try await waitForPrompt(left)
        let repo = "/tmp/oriel-e2e-git", root = "/private/tmp/oriel-e2e-git"
        let hash = try await makeRepo(repo, in: left)
        try await show(tab)
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "oriel:git#e2egit \(root)"])

        let home = element("git.\(card).page")
        // Every branch: the side branch's commit is not in main's history.
        XCTAssertTrue(commit("on the side", in: home).exists(within: 10))
        XCTAssertTrue(commit("second", in: home).exists)
        XCTAssertTrue(home.buttons["Untracked: b.md"].exists)
        keepScreenshot("git home")
        try await commitAndPush(home, card: card, shell: left, repo: repo)

        // A commit opens its diff in the card; Back and Forward walk the card's places.
        commit("second", in: home).click()
        try await expect("the label names the commit") { try await paneLabel(card).hasSuffix(" \(root) \(hash)") }
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, String(hash.prefix(7)), within: 3))
        let page = element("diff.\(card).page")
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 10))
        XCTAssertFalse(page.buttons["b.md"].exists)
        element("pane.\(card).back").click()
        try await expect("back home") { try await paneLabel(card).hasSuffix("e2egit \(root)") }
        element("pane.\(card).forward").click()
        try await expect("forward to the commit") { try await paneLabel(card).hasSuffix(" \(root) \(hash)") }
        try await diff(page, card: card, tab: tab, root: root)
        element("pane.\(card).diff.home").click()
        // A change opens Uncommitted at its file, which follows the work tree.
        XCTAssertTrue(home.buttons["Modified: a.txt"].exists(within: 10))
        home.buttons["Modified: a.txt"].click()
        try await expect("the label is Uncommitted") { try await paneLabel(card).hasSuffix(" \(root) uncommitted") }
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 10))
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "Changes", within: 3))
        try await send("echo new >c.txt\r", to: left)
        XCTAssertTrue(page.buttons["c.txt"].exists(within: 10))

        element("pane.\(card).diff.home").click()
        let branch = element("pane.\(card).git.branch")
        XCTAssertTrue(branch.has(\.isHittable, true, within: 5))
        // a.txt's change would be lost: git refuses, and its words show in the toast.
        branch.click()
        branch.menuItems["side"].click()
        let toast = element("pane.\(card).toast")
        XCTAssertTrue(until(10) { toast.stringValue.contains("overwritten") })
        element("pane.\(card).toast.main").click()
        try await send("git -C \(repo) checkout -- a.txt\r", to: left)
        branch.click()
        branch.menuItems["side"].click()
        try await expectGit("branch --show-current", "side", in: left, repo: repo)
        try await send("cd / && rm -rf \(repo) \(repo).git\r", to: left)
    }

    /// Stage moves b.md to the staged list, Commit commits it with the typed message, Push sends it to the remote.
    private func commitAndPush(_ home: XCUIElement, card: String, shell left: String, repo: String) async throws {
        // Stage shows under the pointer.
        home.buttons["Untracked: b.md"].hover()
        home.buttons["Stage b.md"].click()
        XCTAssertTrue(home.buttons["Added: b.md"].exists(within: 5))
        home.buttons["Unstage b.md"].click()
        XCTAssertTrue(home.buttons["Untracked: b.md"].exists(within: 5))
        home.buttons["Stage b.md"].click()
        XCTAssertTrue(home.buttons["Added: b.md"].exists(within: 5))
        try await expectGit("diff --cached --name-only", "b.md", in: left, repo: repo)
        let message = home.textViews["Message"]
        message.click()
        message.typeText("e2e commit")
        home.buttons["Commit"].click()
        try await expectGit("log -1 --format=%s", "e2e commit", in: left, repo: repo)
        XCTAssertTrue(commit("e2e commit", in: home).exists(within: 5))
        XCTAssertTrue(element("pane.\(card).git.push").has(\.label, "Push, 1 ahead", within: 5))
        element("pane.\(card).git.push").click()
        try await expectGit("--git-dir \(repo).git log -1 --format=%s main", "e2e commit", in: left, repo: repo)
    }

    /// The diff's own controls, on the diff of the commit that changes lines 1-150 and 290.
    private func diff(_ page: XCUIElement, card: String, tab: String, root: String) async throws {
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
        try await commandClick(far, after: tab, root: root)
        try await show(tab)
        try await sideBySide(card, page, far)
        XCTAssertTrue(far.has(\.isHittable, true, within: 3), "far \(far.frame), page \(page.frame)")
        try await commandClick(far, after: tab, root: root)
        try await show(tab)
    }

    /// A commit's row in the history: its label starts with the subject, then its names and its date.
    private func commit(_ subject: String, in home: XCUIElement) -> XCUIElement {
        home.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", subject + ",")).firstMatch
    }

    /// `git <command>` in the shell pane prints the line `expected`, now or within a few tries (the app's write may
    /// still run).
    private func expectGit(_ command: String, _ expected: String, in pane: String, repo: String) async throws {
        try await expect("git \(command) gives \(expected)", times: 10) {
            try await send("clear && git -C \(repo) \(command); echo done-$((6*7))\r", to: pane)
            try await waitFor(pane) { $0.contains("done-42") }
            return try await read(pane).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(expected)
        }
    }

    /// ⌘-click on the line opens the file at the line in a new tab after `tab`; the editor draws only the lines in
    /// view.
    private func commandClick(_ line: XCUIElement, after tab: String, root: String) async throws {
        let file = try await opens("\(root)/a.txt", after: tab) {
            XCUIElement.perform(withKeyModifiers: .command) { line.click() }
        }
        let editor = element("file.\(file).page").textViews.firstMatch
        XCTAssertTrue(until(5) { (editor.value as? String)?.contains("far290") == true })
    }

    /// Side by Side puts the old line and the new one on one row; the file list hides and comes back.
    private func sideBySide(_ card: String, _ page: XCUIElement, _ far: XCUIElement) async throws {
        element("pane.\(card).diff.layout").radioButtons["Side by Side"].click()
        let old = page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'line 290'")).firstMatch
        // By their tops: a narrow column wraps the old line.
        XCTAssertTrue(until(3) {
            old.exists && abs(old.frame.minY - far.frame.minY) < 2 && old.frame.maxX < far.frame.minX
        }, "old \(old.exists ? old.frame : .zero), new \(far.exists ? far.frame : .zero)")
        keepScreenshot("diff card, side by side")
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].vanishes(within: 3))
        element("pane.\(card).diff.file-list").click()
        XCTAssertTrue(page.buttons["a.txt"].exists(within: 3))
    }

    /// A repository with two commits and uncommitted changes, made in the shell pane; HEAD's hash.
    private func makeRepo(_ repo: String, in pane: String) async throws -> String {
        // A commit that changes lines 1-150 and line 290: its second change is far below the first.
        // A side branch with its own commit, a bare remote as the upstream, no signing.
        try await send("rm -rf \(repo) \(repo).git && git init -q --bare -b main \(repo).git && mkdir \(repo) "
            + "&& cd \(repo) && git init -q -b main && git config user.name e2e && git config user.email e2e@oriel "
            + "&& git config commit.gpgsign false && git remote add origin \(repo).git "
            + "&& seq 300 | sed 's/^/line /' >a.txt && git add a.txt "
            + "&& git commit -qm first && git switch -qc side && echo s >s.txt && git add s.txt "
            + "&& git commit -qm 'on the side' && git switch -q main "
            + "&& sed -i '' '1,150s/line/LINE/; s/^line 290$/far290/' a.txt "
            + "&& git commit -qam second && git push -qu origin main && echo new >b.md "
            + "&& sed -i '' 's/^line 200$/changed 200/' a.txt && clear && echo ready-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("ready-42") }
        try await send("clear && git -C \(repo) rev-parse HEAD\r", to: pane)
        return try await poll("HEAD's hash") {
            try await read(pane, in: nil).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        }
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
        XCTAssertTrue(label.hasPrefix("oriel:explorer#") && label.hasSuffix(" \(path)"), label)
        return pane
    }
}
