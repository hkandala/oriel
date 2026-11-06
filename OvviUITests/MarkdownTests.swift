import AppKit
import XCTest

/// File Explorer's Markdown place: Rich Text draws the file rendered, locked; unlocked (⌘E) it is the same view with
/// the marks of the caret's line shown; the outline lists the headings, ⌘S saves, a locked page follows the file on
/// disk, the overview's tile shows the page and a relative link shows its file in the card (also
/// unlocked and from the link's menu), or a new tab with ⌘; a web link opens a browser pane in a new tab, selected.
/// Source shows the source, its page folded beside it.
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

        // Rich Text, locked: the rendered page with no marks (`Second` alone), a table drawn; no text box.
        let page = element("markdown.\(card).page")
        XCTAssertTrue(page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.exists(within: 10))
        XCTAssertTrue(element("pane.\(card).mode.rich text").isSelected)
        XCTAssertFalse(element("pane.\(card).lock").isSelected)
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

        // Locked again through ⌘K, which finds Lock Editing by its manifest keywords; clean: a change on disk shows; a
        // relative link shows its file in the card, ⌘-click in a new tab right after the card's.
        openPalette()
        app.typeText("markdown read")
        XCTAssertTrue(element("palette.command.Lock Editing").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("pane.\(card).lock").has(\.isSelected, false, within: 3))
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
        try await openWebLink(page, from: tab)
        try await source(card, page: page, shell: shell)
    }

    /// Source from the mode's segments: the source alone, its page folded; locked, a typed letter changes nothing. ⌘E
    /// unlocks it to text; the divider's button shows the page, where a tick is an edit of the source, saved with ⌘S;
    /// the button folds it and shows it again. The card keeps its mode, lock and fold: a link in the page shows
    /// other.md in Source with its page.
    private func source(_ card: String, page: XCUIElement, shell: String) async throws {
        let mode = element("pane.\(card).mode.source"), lock = element("pane.\(card).lock")
        mode.click()
        XCTAssertTrue(mode.has(\.isSelected, true, within: 3))
        let box = page.checkBoxes.firstMatch, dirty = element("pane.\(card).dirty")
        XCTAssertTrue(page.buttons["Show Preview"].exists(within: 5))
        XCTAssertFalse(box.exists)
        page.click()
        app.typeText("q")
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(lock.has(\.isSelected, true, within: 3))
        let source = page.textViews.firstMatch
        XCTAssertTrue(until(5) { source.exists && source.stringValue.contains("Some *words*.") }, source.stringValue)
        // The file has no q.
        XCTAssertFalse(source.stringValue.contains("q") || dirty.exists, source.stringValue)
        page.buttons["Show Preview"].click()
        XCTAssertTrue(box.exists(within: 5))
        keepScreenshot("markdown card, source")
        box.click()
        XCTAssertTrue(until(3) { source.stringValue.contains("- [ ] Ship it") }, source.stringValue)
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
        page.links["Other"].click()
        // Shown once its outline toggle hides (other.md has no heading): the old page's row is gone.
        XCTAssertTrue(element("pane.\(card).outline").vanishes(within: 5))
        XCTAssertTrue(mode.has(\.isSelected, true, within: 3))
        XCTAssertTrue(lock.isSelected && page.buttons["Hide Preview"].exists)
    }

    /// A web link: a browser pane in a new tab, selected, since the card cannot show it; then the card's tab again.
    private func openWebLink(_ page: XCUIElement, from tab: String) async throws {
        let before = try await tabIDs()
        page.links["Docs"].click()
        let browser = try await newTabID(after: before)
        closeAfter("tab", browser)
        XCTAssertTrue(element("tab.\(browser)").has(\.isSelected, true, within: 5))
        let label = try await paneLabel(pane(of: browser))
        XCTAssertTrue(label.hasPrefix("ovvi:browser#") && label.contains(" https://example.com"), label)
        try await show(tab)
    }

    /// A relative link's menu has the three opens and Copy Link; Open shows its file in the card: with no heading,
    /// the outline's toggle hides; Back shows it.
    private func follow(_ card: String, page: XCUIElement) {
        page.links["Other"].rightClick()
        XCTAssertTrue(app.menuItems["Open to the Side"].exists(within: 2))
        XCTAssertTrue(app.menuItems["Open in New Tab"].exists && app.menuItems["Copy Link"].exists)
        app.menuItems["Open"].click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "other.md", within: 5))
        XCTAssertTrue(element("pane.\(card).outline").vanishes(within: 3))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "notes.md", within: 5))
        XCTAssertTrue(element("pane.\(card).outline").exists(within: 3))
    }

    /// Rich Text renders what Markdown means, not what it says: `1. 1.` counts up, an item's second paragraph hangs at
    /// its text, a reference link is a link (its definition hidden), an entity is its character.
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
        // Locked takes no typing: the dot stays off below.
        page.staticTexts.matching(NSPredicate(format: "value == 'Second'")).firstMatch.click()
        app.typeText("q")
        let link = page.links["Other"].frame
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(card).lock").has(\.isSelected, true, within: 3))
        let editor = page.textViews.firstMatch
        XCTAssertTrue(until(5) { editor.exists && editor.stringValue.contains("## Second") }, editor.stringValue)
        XCTAssertTrue(editor.stringValue.contains("Some words."))
        XCTAssertFalse(editor.stringValue.contains("*words*"))
        XCTAssertEqual(page.links["Other"].frame, link)
        // A link drawn as one, off the caret's line, opens on a click unlocked too.
        page.links["Other"].click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "other.md", within: 5))
        element("pane.\(card).go-back").click()
        XCTAssertTrue(element("pane.\(card).title").has(\.stringValue, "notes.md", within: 5))
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

    /// A task's box sits at the text's left edge, as the heading's; a click on it while locked writes `[x]` to the file
    /// and leaves the card clean.
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

    /// The find bar works while locked, and Esc gives the keyboard back to the page: Select All and Copy there give the
    /// whole source, past the lines drawn.
    private func copyAll(_ page: XCUIElement) {
        keepPasteboard()
        NSPasteboard.general.clearContents()
        page.staticTexts.matching(NSPredicate(format: "value == 'Third'")).firstMatch.click()
        app.typeKey("f", modifierFlags: .command)
        let search = page.searchFields.firstMatch
        XCTAssertTrue(search.exists(within: 2) && hasKeyboard(search))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.vanishes(within: 2))
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
