import XCTest

/// File Explorer's Markdown place: Read renders the file, Edit (⌘E) is its own text with each mark hidden unless
/// the caret is in its element, the outline lists the headings, ⌘S saves, Read follows the file on disk, the
/// overview's tile shows the page and a relative link shows its file in the card, or a new tab with ⌘.
extension OrielUITests {
    func testMarkdownCardReadsEditsSavesAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("markdown")
        let folder = "/tmp/oriel-e2e-markdown"
        try await waitForPrompt(shell)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("mkdir -p \(folder) && cd \(folder) && printf '%s\\n' '---' 'title: Hidden' '---' '# Notes' "
            + "'Some *words*.' '## Second' '[Other](other.md)' >notes.md && printf '# Other\\n' >other.md && clear "
            + "&& echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, card) = try await markdownCard("\(folder)/notes.md")

        // Read: the rendered page, front matter left out; no editor.
        let page = element("markdown.\(card).page")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.exists(within: 10))
        XCTAssertTrue(element("pane.\(card).mode.read").isSelected)
        XCTAssertFalse(page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Hidden'")).firstMatch.exists)
        XCTAssertFalse(page.textViews.firstMatch.exists)
        element("pane.\(card).outline").click()
        XCTAssertTrue(element("pane.\(card).outline").has(\.isSelected, true, within: 3))
        XCTAssertTrue(page.buttons["Second"].exists(within: 3))
        XCTAssertFalse(page.buttons["title: Hidden"].exists)
        keepScreenshot("markdown card, read, outline")

        try await editAndSave(card, page: page, shell: shell)

        // The overview's tile shows the card's own page.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "explorer", within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))

        // Back in Read, clean: a change on disk shows; a relative link shows its file in the card, ⌘-click in a new
        // tab after this one.
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).mode.read").has(\.isSelected, true, within: 3))
        try await send("printf '## Third\\n' >>notes.md\r", to: shell)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Third'")).firstMatch.exists(within: 5))
        let before = try await tabIDs()
        XCUIElement.perform(withKeyModifiers: .command) { page.links["Other"].click() }
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.label, "File Explorer other.md", within: 5))
        let label = try await paneLabel(pane(of: opened))
        XCTAssertTrue(label.hasPrefix("oriel:explorer#") && label.hasSuffix(" \(folder)/other.md"), label)
        try await show(tab)
        page.links["Other"].click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "other.md", within: 5))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "notes.md", within: 5))
    }

    /// ⌘E: marks away from the caret (at the top) are hidden; an outline row puts the caret on its heading, whose
    /// mark shows. A typed letter shows the dirty dot and ⌘S writes it to the file.
    private func editAndSave(_ card: String, page: XCUIElement, shell: String) async throws {
        page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).mode.edit").has(\.isSelected, true, within: 3))
        let editor = page.textViews.firstMatch
        XCTAssertTrue(until(5) { editor.exists && editor.stringValue.contains("Some words.") })
        XCTAssertFalse(editor.stringValue.contains("*words*"))
        XCTAssertFalse(editor.stringValue.contains("## Second"))
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
    }

    /// A Markdown card of this file in a tab of its own in w2 (selected by `newTab`), made as Oriel makes one, shown.
    private func markdownCard(_ path: String) async throws -> (tab: String, pane: String) {
        let root: [String: Any] = ["type": "pane", "cwd": "/tmp", "label": "oriel:markdown#e2emdc \(path)",
                                   "command": ["sh", "-c", "cat", "sh"]]
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": root])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        closeAfter("tab", tab)
        try await show(tab)
        return try (tab, field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane"))
    }
}
