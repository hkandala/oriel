import XCTest

/// The File Explorer (phase 46): the root's tree from `@pierre/trees`, the filter, files shown in the card with Back
/// and Forward, the open gestures and the row menu, against a small repository.
extension OrielUITests {
    /// The tree lists the root and a folder as it opens; a new file shows by itself; the filter finds a file in a
    /// folder never opened; a double-click shows it in the card, whose label follows; Back comes back to the tree
    /// with the file revealed, Forward to the file; Show in File Explorer reveals it; Open as Root and the root's
    /// menu move the root.
    func testFileExplorerBrowsesOpensAndGoesBack() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files", root = "/private/tmp/oriel-e2e-files"
        try await makeRepo(repo, in: shell)
        let (tab, card) = try await explorer(root, in: repo)
        element("tab.\(tab)").click()

        let tree = element("files.\(card).page")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
        XCTAssertTrue(row("build", in: tree).exists)
        XCTAssertFalse(row("main.swift", in: tree).exists)
        row("src", in: tree).click()
        XCTAssertTrue(row("deep", in: tree).exists(within: 3))
        element("pane.\(card).collapse").click()
        XCTAssertTrue(row("deep", in: tree).vanishes(within: 3))
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

        // Back: the tree, the file revealed in its open folders; Forward: the file.
        element("pane.\(card).back").click()
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        try await labelEnds(card, " \(root)/")
        element("pane.\(card).forward").click()
        XCTAssertTrue(file.textViews.firstMatch.exists(within: 10))
        element("pane.\(card).reveal").click()
        XCTAssertTrue(row("main.swift", in: tree).exists(within: 10))
        XCTAssertTrue(element("pane.\(card).forward").has(\.isEnabled, false, within: 3))

        try await moveRoot(card, tree, root)
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// The row menu's Open as Root, then the root's menu back up to its parent.
    private func moveRoot(_ card: String, _ tree: XCUIElement, _ root: String) async throws {
        row("src", in: tree).rightClick()
        app.menuItems["Open as Root"].click()
        try await labelEnds(card, " \(root)/src/")
        XCTAssertTrue(row("deep", in: tree).exists(within: 10))
        XCTAssertFalse(row("a.txt", in: tree).exists)
        element("pane.\(card).root").click()
        app.menuItems["oriel-e2e-files"].click()
        try await labelEnds(card, " \(root)/")
        XCTAssertTrue(row("a.txt", in: tree).exists(within: 10))
    }

    /// ⌘-click opens a file in a new tab right after the card's, ⌥-click in a pane to the card's side. Several quick
    /// ⌘-clicks: the newest open's tab is the one selected and shown, with its card.
    func testFileExplorerOpensInNewTabsAndToTheSide() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files-open")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files-open", root = "/private/tmp/oriel-e2e-files-open"
        try await send("rm -rf \(repo) && mkdir -p \(repo) && cd \(repo) && touch one.txt two.txt three.txt four.txt "
            + "&& clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, card) = try await explorer(root, in: repo)
        element("tab.\(tab)").click()
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

        element("tab.\(tab)").click()
        let before = try await tabIDs()
        XCUIElement.perform(withKeyModifiers: .command) {
            for name in ["two.txt", "three.txt", "four.txt"] {
                row(name, in: tree).click()
            }
        }
        let opened = try await poll("three new tabs") { () async throws -> [String]? in
            let now = try await tabIDs().filter { !before.contains($0) }
            return now.count == 3 ? now : nil
        }
        opened.forEach { closeAfter("tab", $0) }
        var newest = ""
        for id in opened where try await paneLabel(pane(of: id)).hasSuffix("/four.txt") {
            newest = id
        }
        XCTAssertTrue(element("tab.\(newest)").has(\.isSelected, true, within: 5), newest)
        let page = try await pane(of: newest)
        XCTAssertTrue(element("file.\(page).page").has(\.isHittable, true, within: 5))
        // Settled: no later reply takes the selection or the strip elsewhere.
        XCTAssertFalse(until(1) { !element("tab.\(newest)").isSelected || !element("page.\(newest)").isHittable })
        try await send("rm -rf \(repo)\r", to: shell)
    }

    /// A File Explorer card at the folder, in a tab of its own, made as Oriel makes one.
    private func explorer(_ root: String, in repo: String) async throws -> (tab: String, pane: String) {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": repo, "label": "oriel:explorer#e2efil \(root)/", "command": [
                "sh",
                "-c",
                "cat",
                "sh",
            ],
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
