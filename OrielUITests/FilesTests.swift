import XCTest

/// The File Explorer (phase 46): the root's tree from `@pierre/trees`, the filter, files shown in the card with Back
/// and Forward, the open gestures and the row menu, against a small repository.
extension OrielUITests {
    /// The tree lists the root and a folder as it opens (a click on its name only selects it; → opens it); a new file
    /// shows by itself; the filter finds a file in a folder never opened; a double-click shows it in the card, whose
    /// label follows; Back comes back to the kept tree as it was (the filter's text and matches, build still open
    /// under them), Forward to the file; Show in File Explorer reveals it; Open as Root and the root's menu move the
    /// root.
    func testFileExplorerBrowsesOpensAndGoesBack() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files", root = "/private/tmp/oriel-e2e-files"
        try await makeRepo(repo, in: shell)
        let (tab, card) = try await explorer(root, in: repo)
        try await show(tab)

        let tree = element("files.\(card).page")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        XCTAssertTrue(row("build", in: tree).exists)
        XCTAssertFalse(row("main.swift", in: tree).exists)
        // The first ↓ goes to the first row: `..`, not the one after the row that has the keyboard unseen.
        XCTAssertTrue(hasKeyboard(row("build", in: tree)))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("Parent Folder", in: tree)))
        openAndCollapse(card, tree)
        try await send("touch new.md\r", to: shell)
        XCTAssertTrue(row("new.md", in: tree).exists(within: 5))
        keepScreenshot("file explorer home")
        // The overview draws the card live in its tile.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "explorer", within: 3))
        app.typeKey(.escape, modifierFlags: [])

        // A file in a folder never opened: the filter loads every path. A double-click shows it in the card.
        element("pane.\(card).filter").click()
        app.typeText("main")
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 5))
        XCTAssertFalse(row("a.txt", in: tree).exists)
        let tabs = try await tabIDs()
        row("main.swift", in: tree).doubleClick()
        let file = element("file.\(card).page")
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        try await labelEnds(card, " \(root)/src/deep/main.swift")
        let after = try await tabIDs()
        XCTAssertEqual(after, tabs)
        keepScreenshot("file explorer file")

        // Back (⌘[ over the card), then Forward (⌘] over the tree): the file.
        file.textViews.firstMatch.click()
        app.typeKey("[", modifierFlags: .command)
        try await backToTheKeptTree(card, tree, root)
        row("out.o", in: tree).click()
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        element("pane.\(card).reveal").click()
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        XCTAssertTrue(element("pane.\(card).go-forward").has(\.isEnabled, false, within: 3))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))

        try await moveRoot(card, tree, root)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// Back shows the tree as it was left, its filter's text and matches; with the filter cleared, build is still open.
    private func backToTheKeptTree(_ card: String, _ tree: XCUIElement, _ root: String) async throws {
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        try await labelEnds(card, " \(root)/")
        let filter = element("pane.\(card).filter")
        XCTAssertTrue(filter.has(\.stringValue, "main", within: 3))
        XCTAssertFalse(row("a.txt", in: tree).exists)
        filter.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(row("out.o", in: tree).exists(within: 5))
    }

    /// A click on src's name selects it and → opens it; Collapse All closes it; build stays open.
    private func openAndCollapse(_ card: String, _ tree: XCUIElement) {
        row("src", in: tree).click()
        XCTAssertTrue(hasKeyboard(row("src", in: tree)))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: tree).exists(within: 3))
        element("pane.\(card).collapse").click()
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 3))
        row("build", in: tree).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("out.o", in: tree).exists(within: 3))
    }

    /// The row menu's Open as Root, `..` back up, a double-click on a folder, then the path field: a path that is no
    /// folder stays and Esc puts the root back; a folder's path goes there.
    private func moveRoot(_ card: String, _ tree: XCUIElement, _ root: String) async throws {
        row("src", in: tree).rightClick()
        app.menuItems["Open as Root"].click()
        try await labelEnds(card, " \(root)/src/")
        // The old tree shows until the new one drew, and it has deep too: main.swift is revealed in it.
        XCTAssertTrue(row("a.txt", in: tree).vanishes(within: 10))
        XCTAssertTrue(row("deep", in: tree).exists(within: 5))
        row("Parent Folder", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        element("pane.\(card).collapse").click()
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 3))
        row("src", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/src/")
        // Its first click opened nothing: the root's tree comes back as it left it, src closed.
        element("pane.\(card).go-back").click()
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        XCTAssertFalse(row("deep", in: tree).exists)
        element("pane.\(card).go-forward").click()
        try await labelEnds(card, " \(root)/src/")

        let field = element("pane.\(card).root")
        XCTAssertTrue(field.has(\.stringValue, "\(root)/src", within: 5))
        field.click()
        app.typeText("\(root)/none\r")
        // A path that is no folder makes no place (Back below); Esc puts the root back.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.has(\.stringValue, "\(root)/src", within: 3))
        // Tidied: `src/..` is the root. Back comes to src: the refused path made no place.
        field.click()
        app.typeText("\(root)/src/..\r")
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        element("pane.\(card).go-back").click()
        try await labelEnds(card, " \(root)/src/")
    }

    /// The tree has the keyboard as its card shows: the first ↑ goes to the last row, ↑ from the first row to `..` and
    /// ↓ back, ↓ moves, → opens a folder, ← closes it, Return opens a file. Hidden files show only with row 2's eye. An
    /// empty folder shows its placeholder. ⌘F gives the filter the keyboard, and `..` hides while it has text.
    func testFileExplorerKeysHiddenFilesAndFind() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files-keys")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files-keys", root = "/private/tmp/oriel-e2e-files-keys"
        try await makeRepo(repo, in: shell)
        let (tab, card) = try await explorer(root, in: repo)
        try await show(tab)
        let tree = element("files.\(card).page")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        XCTAssertFalse(row(".gitignore", in: tree).exists)

        // build, src, a.txt: the first row has the keyboard, a turn after the page's focus. The first ↑ goes to the
        // last row; ↑ from the first goes to `..`.
        XCTAssertTrue(hasKeyboard(row("build", in: tree)))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("a.txt", in: tree)))
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("Parent Folder", in: tree)))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(hasKeyboard(row("build", in: tree)))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: tree).exists(within: 5))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        try await labelEnds(card, " \(root)/a.txt")
        element("pane.\(card).go-back").click()
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))

        let eye = element("pane.\(card).hidden-files")
        eye.click()
        XCTAssertTrue(row(".gitignore", in: tree).exists(within: 5))
        eye.click()
        XCTAssertTrue(row(".gitignore", in: tree).vanishes(within: 5))

        // An empty folder shows its placeholder.
        try await send("mkdir \(repo)/empty\r", to: shell)
        XCTAssertTrue(row("empty", in: tree).exists(within: 5))
        row("empty", in: tree).doubleClick()
        try await labelEnds(card, " \(root)/empty/")
        let empty = tree.staticTexts.matching(NSPredicate(format: "value == 'This folder is empty'")).firstMatch
        XCTAssertTrue(empty.exists(within: 10))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("main")
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 5))
        XCTAssertFalse(row("Parent Folder", in: tree).exists)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// A File Explorer beside a terminal leaves it the keyboard: a refresh of the tree (a file made under its root, as
    /// a fetch writes in .git) and its tab shown again type nothing into the tree.
    func testFileExplorerLeavesTheKeyboardToThePaneInUse() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (shellTab, shell) = try await newTab("files-keyboard")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files-keyboard", root = "/private/tmp/oriel-e2e-files-keyboard"
        try await makeRepo(repo, in: shell)
        let (tab, card) = try await explorer(root, in: repo)
        let beside = try await split(card)
        try await show(tab)
        let tree = element("files.\(card).page")
        // The tree has the keyboard on a.txt, then the terminal.
        row("a.txt", in: tree).click()
        XCTAssertTrue(hasKeyboard(row("a.txt", in: tree)))
        element("terminal.\(beside)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(beside)"))
        // A file before a.txt moves its row.
        try await send("touch \(repo)/0.txt\r", to: shell)
        XCTAssertTrue(row("0.txt", in: tree).exists(within: 5))
        app.typeText("echo kept-$((6*7))\r")
        try await waitFor(beside) { $0.contains("kept-42") }
        try await show(shellTab)
        try await show(tab)
        XCTAssertTrue(row("0.txt", in: tree).exists(within: 5))
        app.typeText("echo back-$((6*7))\r")
        try await waitFor(beside) { $0.contains("back-42") }
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// ⌘-click opens a file in a new tab at the end, ⌥-click in a pane to the card's side, both behind: the card's
    /// tab stays selected and the tree keeps the keyboard.
    func testFileExplorerOpensInNewTabsAndToTheSide() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files-open")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files-open", root = "/private/tmp/oriel-e2e-files-open"
        try await send("rm -rf \(repo) && mkdir -p \(repo) && cd \(repo) && touch one.txt two.txt three.txt four.txt "
            + "&& clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        // An old Files label, its root without the `/`, still opens the tree.
        let (tab, card) = try await explorer(root, in: repo, label: "oriel:files#e2efio \(root)")
        try await show(tab)
        let tree = element("files.\(card).page")
        XCTAssertTrue(row("four.txt", in: tree).exists(within: 10))

        XCUIElement.perform(withKeyModifiers: .option) { row("one.txt", in: tree).click() }
        let side = try await poll("a pane beside the card") { () async throws -> String? in
            try await (snapshot()["panes"] as? [[String: Any]] ?? []).first {
                $0["tab_id"] as? String == tab && $0["pane_id"] as? String != card
            }?["pane_id"] as? String
        }
        try await labelEnds(side, " \(root)/one.txt")
        XCTAssertTrue(element("file.\(side).page").exists(within: 10))
        XCTAssertTrue(hasKeyboard(row("one.txt", in: tree)))

        // Each ⌘-click from the tree: a new tab at the end (from the second on, the card's tab is not last), behind
        // it.
        for name in ["two.txt", "three.txt", "four.txt"] {
            let before = try await tabIDs()
            XCUIElement.perform(withKeyModifiers: .command) { row(name, in: tree).click() }
            let opened = try await newTabID(after: before)
            closeAfter("tab", opened)
            let pane = try await pane(of: opened)
            try await labelEnds(pane, " \(root)/\(name)")
            let last = try await isLast(opened)
            XCTAssertTrue(last, "\(name)'s tab is not last")
            // Once the bar shows the new tab, the card's tab stays selected: the app follows a new tab only after it
            // shows.
            XCTAssertTrue(element("tab.\(opened)").exists(within: 5), name)
            XCTAssertFalse(until(0.5) { !element("tab.\(tab)").isSelected }, name)
            XCTAssertTrue(hasKeyboard(row(name, in: tree)), name)
        }
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// A File Explorer card at the folder, in a tab of its own, made as Oriel makes one.
    private func explorer(_ root: String, in repo: String,
                          label: String? = nil) async throws -> (tab: String, pane: String)
    {
        let label = label ?? "oriel:explorer#e2efil \(root)/", command = ["sh", "-c", "cat", "sh"]
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": repo, "label": label, "command": command,
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        return (tab, card)
    }

    private func row(_ name: String, in page: XCUIElement) -> XCUIElement {
        page.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// The card's label follows the place it shows.
    private func labelEnds(_ pane: String, _ end: String) async throws {
        _ = try await poll("the label ending in \(end)") { () async throws -> String? in
            let label = try await paneLabel(pane)
            return label.hasPrefix("oriel:explorer#") && label.hasSuffix(end) ? label : nil
        }
    }

    /// Two commits, a change, and an ignored folder.
    private func makeRepo(_ repo: String, in shell: String) async throws {
        let commit = "git -c user.name=e2e -c user.email=e2e@oriel commit -q"
        try await send("""
        rm -rf \(repo) && mkdir -p \(repo)/src/deep \(repo)/build && cd \(repo) && git init -q && \
        echo build/ >.gitignore && echo one >a.txt && echo 'print(1)' >src/deep/main.swift && git add -A && \
        \(commit) -m first && echo two >>a.txt && \(commit) -am second-commit && echo three >>a.txt && \
        touch build/out.o && clear && echo ready-$((6*7))\r
        """, to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
    }
}
