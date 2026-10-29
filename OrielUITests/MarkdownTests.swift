import XCTest

/// The Markdown plugin (phase 44): Read renders the file, Edit (⌘E) is its own text with each mark hidden unless
/// the caret is in its element, the outline lists the headings, ⌘S saves, the overview's tile shows the page and a
/// relative link opens its file in a new tab.
extension OrielUITests {
    func testMarkdownCardReadsEditsSavesAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let folder = "/tmp/oriel-e2e-markdown"
        let (_, shell) = try await markdownTab(["sh"], label: nil)
        try await waitForPrompt(shell)
        try await send("mkdir -p \(folder) && cd \(folder) && printf '%s\\n' '---' 'title: Hidden' '---' '# Notes' "
            + "'Some *words*.' '## Second' '[Other](other.md)' >notes.md && printf '# Other\\n' >other.md && clear "
            + "&& echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, card) = try await markdownTab(["sh", "-c", "cat", "sh"],
                                                label: "oriel:markdown#e2emd \(folder)/notes.md")
        element("tab.\(tab)").click()

        // Read: the rendered page, front matter left out; no editor.
        let page = element("markdown.\(card).page")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.exists(within: 10))
        XCTAssertTrue(element("pane.\(card).mode.read").isSelected)
        XCTAssertFalse(page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Hidden'")).firstMatch.exists)
        XCTAssertFalse(page.textViews.firstMatch.exists)
        element("pane.\(card).outline").click()
        XCTAssertTrue(element("pane.\(card).outline").has(\.isSelected, true, within: 3))
        keepScreenshot("markdown card, read, outline")

        // Edit: marks away from the caret (at the top) are hidden.
        page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).mode.edit").has(\.isSelected, true, within: 3))
        let editor = page.textViews.firstMatch
        XCTAssertTrue(until(5) { editor.exists && editor.stringValue.contains("Some words.") })
        XCTAssertFalse(editor.stringValue.contains("*words*"))
        XCTAssertFalse(editor.stringValue.contains("## Second"))
        // An outline row puts the caret on its heading: its mark shows.
        page.buttons["Second"].click()
        XCTAssertTrue(until(3) { editor.stringValue.contains("## Second") })
        XCTAssertFalse(element("pane.\(card).dirty").exists)
        app.typeText("x")
        XCTAssertTrue(element("pane.\(card).dirty").exists(within: 3))
        keepScreenshot("markdown card, edit")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 5))
        try await send("clear && grep -q '^x## Second$' notes.md && echo saved-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("saved-42") }

        // The overview's tile shows the card's own page.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "markdown", within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))

        // Back in Read, a relative link: its file in a new tab right after this one.
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).mode.read").has(\.isSelected, true, within: 3))
        let before = try await tabIDs()
        page.links["Other"].click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.label, "Markdown other.md", within: 5))
        let label = try await paneLabel(pane(of: opened))
        XCTAssertTrue(label.hasPrefix("oriel:markdown#") && label.hasSuffix(" \(folder)/other.md"), label)
        try await send("rm -rf \(folder)\r", to: shell)
    }

    /// A new tab in w2 made with `layout.apply` (no ⌘T, no focus change); with a label, a plugin's pane.
    private func markdownTab(_ command: [String], label: String?) async throws -> (tab: String, pane: String) {
        var root: [String: Any] = ["type": "pane", "cwd": "/tmp", "command": command]
        root["label"] = label
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": root])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        closeAfter("tab", tab)
        return try (tab, field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane"))
    }
}
