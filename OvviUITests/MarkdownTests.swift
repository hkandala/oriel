import AppKit
import XCTest

/// File Explorer's Markdown place: Read draws the file rendered, Live Edit (⌘E) is the same view with the marks of the
/// caret's line shown, the outline lists the headings, ⌘S saves, Read follows the file on disk, the
/// overview's tile shows the page and a relative link shows its file in the card, or a new tab with ⌘. Side by Side
/// shows the source beside the page.
extension OvviUITests {
    func testMarkdownCardReadsEditsSavesAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("markdown")
        let folder = "/tmp/ovvi-e2e-markdown"
        try await waitForPrompt(shell)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(folder)\r"])
        }
        try await send("mkdir -p \(folder) && cd \(folder) && printf '%s\\n' '---' 'title: Hidden' '---' '# Notes' "
            + "'Some *words*.' '## Second' '- [ ] Ship it' '' '[Other](other.md)' '' '| A | B |' '| - | - |' "
            + "'| 1 | 2 |' '' '1. Alpha' '1. Beta' '' '   More of beta.' '' 'See [Docs][d] &copy;' '' "
            + "'[d]: https://example.com' >notes.md && printf 'Other\\n' >other.md && clear "
            + "&& echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let (tab, card) = try await markdownCard("\(folder)/notes.md")

        // Read: the rendered page with no marks (`Second` alone), a table drawn; no text box.
        let page = element("markdown.\(card).page")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.exists(within: 10))
        XCTAssertEqual(element("pane.\(card).mode").stringValue, "Read")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'B'")).firstMatch.exists)
        XCTAssertFalse(page.textViews.firstMatch.exists)
        element("pane.\(card).outline").click()
        XCTAssertTrue(element("pane.\(card).outline").has(\.isSelected, true, within: 3))
        XCTAssertTrue(page.buttons["Second"].exists(within: 3))
        XCTAssertFalse(page.buttons["title: Hidden"].exists)
        keepScreenshot("markdown card, read, outline")
        constructs(page)
        try await tick(card, page: page, shell: shell)

        try await editAndSave(card, page: page, shell: shell)

        // The overview's tile shows the card's own page.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, "explorer", within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))

        // Back in Read through ⌘K, which finds Edit Mode by its manifest keywords; clean: a change on disk shows; a
        // relative link shows its file in the card, ⌘-click in a new tab at the end.
        openPalette()
        app.typeText("markdown read")
        XCTAssertTrue(element("palette.command.Edit Mode").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("pane.\(card).mode").has(\.stringValue, "Read", within: 3))
        try await send("printf '## Third\\n' >>notes.md\r", to: shell)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Third'")).firstMatch.exists(within: 5))
        copyAll(page)
        let before = try await tabIDs()
        XCUIElement.perform(withKeyModifiers: .command) { page.links["Other"].click() }
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        XCTAssertTrue(element("tab.\(opened)").has(\.label, "File Explorer other.md", within: 5))
        let label = try await paneLabel(pane(of: opened))
        XCTAssertTrue(label.hasPrefix("ovvi:explorer#") && label.hasSuffix(" \(folder)/other.md"), label)
        try await show(tab)
        follow(card, page: page)
        try await sideBySide(card, page: page, shell: shell)
    }

    /// Side by Side from the mode menu: the source as text beside the rendered page; a tick in the page is an edit of
    /// the source, saved with ⌘S; the divider's button hides the page and shows it again.
    private func sideBySide(_ card: String, page: XCUIElement, shell: String) async throws {
        let mode = element("pane.\(card).mode")
        mode.click()
        mode.menuItems["Side by Side"].click()
        XCTAssertTrue(mode.has(\.stringValue, "Side by Side", within: 3))
        let source = page.textViews.firstMatch, box = page.checkBoxes.firstMatch
        XCTAssertTrue(until(5) { source.exists && source.stringValue.contains("Some *words*.") }, source.stringValue)
        XCTAssertTrue(box.exists(within: 5))
        keepScreenshot("markdown card, side by side")
        box.click()
        XCTAssertTrue(until(3) { source.stringValue.contains("- [ ] Ship it") }, source.stringValue)
        let dirty = element("pane.\(card).dirty")
        XCTAssertTrue(dirty.exists(within: 3))
        source.click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
        try await send("clear && grep -q '^- \\[ \\] Ship it$' notes.md && echo split-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("split-42") }
        page.buttons["Hide Preview"].click()
        XCTAssertTrue(box.vanishes(within: 3))
        page.buttons["Show Preview"].click()
        XCTAssertTrue(box.exists(within: 3))
        // The card keeps its mode: a link in the page shows other.md in Side by Side.
        page.links["Other"].click()
        // Shown once its outline toggle hides (other.md has no heading): the old page's row is gone.
        XCTAssertTrue(element("pane.\(card).outline").vanishes(within: 5))
        XCTAssertTrue(mode.has(\.stringValue, "Side by Side", within: 3))
    }

    /// A relative link shows its file in the card: with no heading, the outline's toggle hides; Back shows it.
    private func follow(_ card: String, page: XCUIElement) {
        page.links["Other"].click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "other.md", within: 5))
        XCTAssertTrue(element("pane.\(card).outline").vanishes(within: 3))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "notes.md", within: 5))
        XCTAssertTrue(element("pane.\(card).outline").exists(within: 3))
    }

    /// Read renders what Markdown means, not what it says: `1. 1.` counts up, an item's second paragraph hangs at its
    /// text, a reference link is a link (its definition hidden), an entity is its character.
    private func constructs(_ page: XCUIElement) {
        let text = { (value: String) in
            page.staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
        }
        XCTAssertTrue(text("2.").exists(within: 3))
        let beta = text("Beta"), more = text("More of beta.")
        XCTAssertTrue(more.exists)
        XCTAssertLessThan(
            abs(more.frame.minX - beta.frame.minX),
            3,
            "Beta at \(beta.frame), its paragraph at \(more.frame)",
        )
        XCTAssertTrue(page.links["Docs"].exists)
        XCTAssertFalse(page.staticTexts.matching(NSPredicate(format: "value CONTAINS 'example.com'")).firstMatch.exists)
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value CONTAINS '©'")).firstMatch.exists)
    }

    /// ⌘E: nothing moves but the clicked line, whose marks show; the others stay hidden; a click on the table shows
    /// its source; an outline row puts the caret on its heading, whose mark shows while the other heading's hides. A
    /// typed letter shows the dirty dot and ⌘S writes it to the file.
    private func editAndSave(_ card: String, page: XCUIElement, shell: String) async throws {
        // Read takes no typing: the dot stays off below.
        page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.click()
        app.typeText("q")
        let link = page.links["Other"].frame
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).mode").has(\.stringValue, "Live Edit", within: 3))
        let editor = page.textViews.firstMatch
        XCTAssertTrue(until(5) { editor.exists && editor.stringValue.contains("## Second") }, editor.stringValue)
        XCTAssertTrue(editor.stringValue.contains("Some words."))
        XCTAssertFalse(editor.stringValue.contains("*words*"))
        XCTAssertEqual(page.links["Other"].frame, link)
        page.staticTexts.matching(NSPredicate(format: "value == '1'")).firstMatch.click()
        XCTAssertTrue(until(3) { editor.stringValue.contains("| 1 | 2 |") }, editor.stringValue)
        page.buttons["Notes"].click()
        XCTAssertTrue(until(3) { editor.stringValue.contains("# Notes") && !editor.stringValue.contains("## Second") })
        XCTAssertFalse(element("pane.\(card).dirty").exists)
        app.typeText("x")
        XCTAssertTrue(element("pane.\(card).dirty").exists(within: 3))
        keepScreenshot("markdown card, edit")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 5))
        try await send("clear && grep -q '^x# Notes$' notes.md && echo saved-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("saved-42") }
    }

    /// A task's box sits at the text's left edge, as the heading's; a click on it in Read writes `[x]` to the file and
    /// leaves the card clean.
    private func tick(_ card: String, page: XCUIElement, shell: String) async throws {
        let box = page.checkBoxes.firstMatch
        let heading = page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch
        XCTAssertTrue(box.exists(within: 5))
        XCTAssertLessThan(
            abs(box.frame.minX - heading.frame.minX),
            6,
            "the box at \(box.frame), the heading at \(heading.frame)",
        )
        box.click()
        try await send(
            "clear && until grep -q '^- \\[x\\] Ship it$' notes.md; do sleep 0.1; done && echo ticked-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("ticked-42") }
        XCTAssertTrue(until(3) { box.value as? Int == 1 }, "\(box.value ?? "no value")")
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 3))
    }

    /// Select All and Copy in Read give the whole source, past the lines drawn.
    private func copyAll(_ page: XCUIElement) {
        keepPasteboard()
        NSPasteboard.general.clearContents()
        page.staticTexts.matching(NSPredicate(format: "value == 'Third'")).firstMatch.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(until(3) {
            let copied = NSPasteboard.general.string(forType: .string) ?? ""
            return copied.hasPrefix("---\ntitle: Hidden") && copied.contains("[Other](other.md)")
        }, NSPasteboard.general.string(forType: .string) ?? "nothing copied")
    }

    /// A Markdown card of this file in a tab of its own in w2 (selected by `newTab`), made as Ovvi makes one, shown.
    private func markdownCard(_ path: String) async throws -> (tab: String, pane: String) {
        let root: [String: Any] = ["type": "pane", "cwd": "/tmp", "label": "ovvi:markdown#e2emdc \(path)",
                                   "command": ["sh", "-c", "cat", "sh"]]
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": root])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        closeAfter("tab", tab)
        try await show(tab)
        return try (tab, field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane"))
    }
}
