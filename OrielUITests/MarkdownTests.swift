import XCTest

/// The Markdown plugin's card (phase 43, spec item 3).
extension OrielUITests {
    /// Read shows the file rendered and opens a relative link as its file's card in a new tab; the outline lists the
    /// headings and jumps to one; ⌘E edits; an edit shows the dirty dot and ⌘S saves it; a change on disk reloads a
    /// clean card and asks on a dirty one.
    func testMarkdownCardReadsEditsAndSaves() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("markdown")
        try await waitForPrompt(shell)
        let folder = "/tmp/oriel-e2e-markdown", root = "/private/tmp/oriel-e2e-markdown"
        // Tall enough that the last heading is far below the first.
        try await send("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && echo '# Other' > other.md && "
            + "{ printf -- '---\\ntitle: Hidden\\n---\\n[Other](other.md)\\n\\n# Top\\n\\n'; "
            + "for i in $(seq 150); do printf 'line %s\\n\\n' $i; done; echo '## Bottom'; } > notes.md && "
            + "clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": folder, "label": "oriel:markdown#e2emd1 \(root)/notes.md",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let cardTab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", cardTab)
        element("tab.\(cardTab)").click()

        // Read: rendered, front matter hidden; a click on the relative link opens other.md's card next to it.
        let read = element("markdown.\(pane).read.0")
        XCTAssertTrue(read.exists(within: 5))
        XCTAssertTrue(element("pane.\(pane).mode.read").isSelected)
        XCTAssertFalse(read.stringValue.contains("Hidden"), read.stringValue)
        let before = try await tabIDs()
        read.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 12, dy: 8)).click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        let label = try await paneLabel(self.pane(of: opened))
        XCTAssertTrue(label.hasPrefix("oriel:markdown#") && label.hasSuffix(" \(root)/other.md"), label)
        XCTAssertTrue(element("tab.\(opened)").has(\.label, "Markdown other.md", within: 5))
        element("tab.\(cardTab)").click()
        try await markdownOutline(pane)
        try await editMarkdown(pane, in: cardTab, shell: shell)
    }

    /// The outline: its headings, and a click scrolls to the last.
    private func markdownOutline(_ pane: String) async throws {
        element("pane.\(pane).outline").click()
        let bottom = element("markdown.\(pane).heading.1")
        XCTAssertTrue(bottom.has(\.label, "Bottom", within: 3))
        // Bottom's section, far below, comes into view.
        let section = element("markdown.\(pane).read.2")
        XCTAssertFalse(section.exists && section.isHittable)
        bottom.click()
        XCTAssertTrue(section.has(\.isHittable, true, within: 3))
        element("pane.\(pane).outline").click()
        XCTAssertTrue(bottom.vanishes(within: 3))
    }

    /// ⌘E, an edit, ⌘S, and changes on disk to the clean and the dirty card.
    private func editMarkdown(_ pane: String, in cardTab: String, shell: String) async throws {
        // ⌘E edits the file's own text; an edit marks the card, ⌘S writes it.
        element("tab.\(cardTab)").click()
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(pane).mode.edit").has(\.isSelected, true, within: 3))
        // Front matter as plain text above MarkdownEngine's text view.
        XCTAssertTrue(element("markdown.\(pane).front").has(\.stringValue, "---\ntitle: Hidden\n---\n", within: 3))
        let text = element("markdown.\(pane).card").textViews.matching(NSPredicate(format: "identifier == ''"))
            .firstMatch
        XCTAssertTrue(text.exists(within: 3))
        XCTAssertTrue(text.stringValue.hasPrefix("[Other](other.md)"), text.stringValue)
        // A click on a link puts the caret in it: no new tab, no browser.
        let before = try await tabIDs()
        text.links.firstMatch.click()
        app.typeText("X")
        XCTAssertTrue(until(3) { text.stringValue.split(separator: "\n")[0].contains("X") }, text.stringValue)
        let after = try await tabIDs()
        XCTAssertEqual(after, before)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("\nSaved by Oriel")
        XCTAssertTrue(element("pane.\(pane).dirty").exists(within: 3))
        // The card is made again after the overview: the edit stays.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 2))
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        XCTAssertTrue(element("pane.\(pane).dirty").exists(within: 3))
        XCTAssertTrue(text.stringValue.hasSuffix("Saved by Oriel"), text.stringValue.suffix(40).description)
        text.click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(pane).dirty").vanishes(within: 5))
        try await send("tail -n 1 notes.md\r", to: shell)
        try await waitFor(shell) { $0.contains("\nSaved by Oriel") }

        // A clean card takes a change on disk; a dirty one asks, and Reload drops the edit.
        try await send("echo 'From disk' >> notes.md\r", to: shell)
        XCTAssertTrue(until(5) { text.stringValue.hasSuffix("From disk\n") }, text.stringValue.suffix(40).description)
        text.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("Mine")
        XCTAssertTrue(element("pane.\(pane).dirty").exists(within: 3))
        try await send("echo 'Again' >> notes.md\r", to: shell)
        let reload = element("pane.\(pane).toast.other")
        XCTAssertTrue(reload.has(\.label, "Reload", within: 5))
        reload.click()
        XCTAssertTrue(element("pane.\(pane).dirty").vanishes(within: 3))
        XCTAssertTrue(until(3) { text.stringValue.hasSuffix("Again\n") }, text.stringValue.suffix(40).description)
    }
}
