import XCTest

/// The Files card (phase 44's web variant): the root's tree from `@pierre/trees`, the filter, the Git section, and the
/// linked opens, against a small repository.
extension OrielUITests {
    /// The tree lists the root and a folder as it opens; a new file shows by itself; the filter finds a file in a
    /// folder never opened; double-click opens a file with its kind; the Git section's change and commit open the diff.
    func testFilesCardShowsTheTreeFiltersAndOpensLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files", root = "/private/tmp/oriel-e2e-files"
        try await makeRepo(repo, in: shell)
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": repo, "label": "oriel:files#e2efiles \(root)", "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        element("tab.\(tab)").click()

        let page = element("files.\(card).page")
        func row(_ name: String) -> XCUIElement {
            page.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        }
        XCTAssertTrue(row("a.txt").exists(within: 10))
        XCTAssertTrue(row("build").exists)
        XCTAssertFalse(row("main.swift").exists)
        row("src").click()
        XCTAssertTrue(row("deep").exists(within: 3))
        element("pane.\(card).collapse").click()
        XCTAssertTrue(row("deep").vanishes(within: 3))
        row("src").click()
        XCTAssertTrue(row("deep").exists(within: 3))
        try await send("touch new.md\r", to: shell)
        XCTAssertTrue(row("new.md").exists(within: 5))
        keepScreenshot("files card")
        // The overview draws the card live in its tile.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "files", within: 3))
        app.typeKey(.escape, modifierFlags: [])

        // A file in a folder never opened: the filter loads every path.
        element("pane.\(card).filter").click()
        app.typeText("main")
        XCTAssertTrue(row("main.swift").exists(within: 5))
        XCTAssertFalse(row("a.txt").exists)
        var label = try await opens(row("main.swift"))
        XCTAssertTrue(label.hasPrefix("oriel:file#") && label.hasSuffix(" \(root)/src/deep/main.swift"), label)

        element("tab.\(tab)").click()
        row("Git").click()
        XCTAssertTrue(row("second-commit").exists(within: 3))
        label = try await opens(row("Modified: a.txt"), command: true)
        XCTAssertTrue(label.hasPrefix("oriel:diff#") && label.hasSuffix(" \(root) uncommitted"), label)

        element("tab.\(tab)").click()
        label = try await opens(row("second-commit"))
        XCTAssertTrue(label.hasPrefix("oriel:diff#") && label.range(of: #" \#(root) [0-9a-f]{40}$"#,
                                                                    options: .regularExpression) != nil, label)
        try await send("rm -rf \(repo)\r", to: shell)
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

    /// A double-click, or a ⌘-click, on the row opens a new tab: its pane's label.
    private func opens(_ row: XCUIElement, command: Bool = false) async throws -> String {
        let before = try await tabIDs()
        if command {
            XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        } else {
            row.doubleClick()
        }
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        return try await paneLabel(pane(of: opened))
    }
}
