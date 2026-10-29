import XCTest

/// The Files plugin (plugins: files): a repository's tree with git letters, the filter, the watch, and the links to
/// the file kinds and the diff.
extension OrielUITests {
    /// A repository with a commit after its first, a changed file in a folder, an untracked file and an ignored folder.
    /// Rows show their letters; a folder lists on a double-click; the filter shows only the matches and gives back the
    /// open folder; a new file on disk shows up; Collapse All closes the folder. A double-click on notes.md opens
    /// Markdown, a ⌘-click on a.swift File, a double-click on a change the Uncommitted diff, a ⌘-click on the last
    /// commit its diff: each a new tab with that label. The overview's tile shows the card.
    func testFilesShowsTheTreeAndOpensItsLinks() async throws {
        let (shell, head) = try await filesRepo()
        let (tab, pane) = try await filesCard()
        let root = "/private/tmp/oriel-e2e-files"
        let item = { (path: String) in self.element("files.\(pane).item.\(path)") }
        XCTAssertTrue(element("files.\(pane).card").exists(within: 5))
        XCTAssertTrue(item("Sources").has(\.stringValue, "M", within: 5))
        XCTAssertTrue(item("new.txt").has(\.stringValue, "U", within: 1))
        XCTAssertTrue(item("build").has(\.stringValue, "Ignored", within: 1))
        XCTAssertTrue(item("a.swift").has(\.stringValue, "", within: 1))
        XCTAssertFalse(item(".git").exists)

        filterTree(pane, "main")
        XCTAssertTrue(item("Sources/main.swift").exists(within: 5))
        XCTAssertTrue(item("a.swift").vanishes(within: 1))
        filterTree(pane, "")
        XCTAssertTrue(item("a.swift").exists(within: 3))
        XCTAssertFalse(item("Sources/main.swift").exists)
        item("Sources").doubleClick()
        XCTAssertTrue(item("Sources/main.swift").has(\.stringValue, "M", within: 3), rows(pane))
        filterTree(pane, "notes")
        XCTAssertTrue(item("Sources/main.swift").vanishes(within: 5))
        filterTree(pane, "zzz")
        XCTAssertTrue(element("files.\(pane).message").has(\.stringValue, "No matching files", within: 3))
        filterTree(pane, "")
        // The folder open before the filter is open again.
        XCTAssertTrue(item("Sources/main.swift").exists(within: 3))
        try await send("touch Sources/later.txt\r", to: shell)
        XCTAssertTrue(item("Sources/later.txt").exists(within: 5))
        element("pane.\(pane).collapse").click()
        XCTAssertTrue(item("Sources/main.swift").vanishes(within: 3))
        keepScreenshot("files card")

        try await opens("oriel:markdown#", " \(root)/notes.md", from: tab) { item("notes.md").doubleClick() }
        try await opens("oriel:file#", " \(root)/a.swift", from: tab) {
            XCUIElement.perform(withKeyModifiers: .command) { item("a.swift").click() }
        }
        try await opens("oriel:file#", " \(root)/a.swift", from: tab) {
            item("a.swift").click()
            app.typeKey(.return, modifierFlags: [])
        }
        element("files.\(pane).git").click()
        let change = element("files.\(pane).change.Sources/main.swift")
        XCTAssertTrue(change.has(\.stringValue, "M", within: 5))
        XCTAssertTrue(element("files.\(pane).change.new.txt").exists)
        keepScreenshot("files card, git")
        try await opens("oriel:diff#", " \(root) uncommitted", from: tab) { change.doubleClick() }
        let commit = element("files.\(pane).commit.\(head)")
        XCTAssertTrue(commit.exists(within: 3))
        try await opens("oriel:diff#", " \(root) \(head)", from: tab) {
            XCUIElement.perform(withKeyModifiers: .command) { commit.click() }
        }
        overviewBorrows(pane)
    }

    /// The overview's tile shows the card's tree, which the card has again after.
    private func overviewBorrows(_ pane: String) {
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.card.\(pane)")
        scrollOverview(to: tile)
        XCTAssertTrue(tile.has(\.stringValue, "files", within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        XCTAssertTrue(element("files.\(pane).item.a.swift").exists(within: 3))
    }

    /// The repository in /tmp/oriel-e2e-files, made by a shell in a new tab: the shell's pane and the last commit.
    private func filesRepo() async throws -> (shell: String, head: String) {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("files")
        try await waitForPrompt(shell)
        let repo = "/tmp/oriel-e2e-files", git = "git -c user.name=e -c user.email=e"
        try await send("""
        rm -rf \(repo) && mkdir -p \(repo)/Sources && cd \(repo) && git init -q && echo build/ >.gitignore && \
        echo 1 >a.swift && echo 1 >Sources/main.swift && echo '# Notes' >notes.md && git add -A && \
        \(git) commit -qm one && echo 2 >Sources/main.swift && \(git) commit -qam two && \
        echo 3 >Sources/main.swift && echo n >new.txt && mkdir build && touch build/out.o && clear && \
        echo "head-$(git rev-parse HEAD)"\r
        """, to: shell)
        try await waitFor(shell) { $0.contains("head-") && !$0.contains("rev-parse") }
        let head = try await String(read(shell).split(separator: "head-").last?.prefix(40) ?? "")
        XCTAssertEqual(head.count, 40, head)
        return (shell, head)
    }

    /// A Files tab on the repository, selected.
    private func filesCard() async throws -> (tab: String, pane: String) {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": "oriel:files#e2e43f /private/tmp/oriel-e2e-files",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        element("tab.\(tab)").click()
        return (tab, pane)
    }

    /// The tree's rows with their values, for a failure's message.
    private func rows(_ pane: String) -> String {
        element("files.\(pane).tree").staticTexts.allElementsBoundByIndex.map { "\($0.identifier)=\($0.stringValue)" }
            .joined(separator: " ")
    }

    /// Types the filter's text in place of what it had, once the field has the keyboard (an empty one is a button
    /// until clicked).
    private func filterTree(_ pane: String, _ text: String) {
        element("pane.\(pane).filter").click()
        XCTAssertTrue(hasKeyboard("pane.\(pane).filter"))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        app.typeText(text)
    }

    /// The click opens a new tab, selected, labeled with that prefix and suffix; then the files tab is selected again.
    private func opens(_ prefix: String, _ suffix: String, from tab: String, click: () -> Void) async throws {
        let before = try await tabIDs()
        click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        let label = try await paneLabel(pane(of: opened))
        XCTAssertTrue(label.hasPrefix(prefix) && label.hasSuffix(suffix), label)
        // Closed at once: more tabs than the bar shows scroll it.
        try await Self.call(one, "tab.close", ["tab_id": opened])
        XCTAssertTrue(element("tab.\(opened)").vanishes(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
    }
}
