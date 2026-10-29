import XCTest

/// Plugin panes (phase 42): a herdr pane labeled `oriel:<kind>#<iid> <arg>` with a placeholder, shown as the kind's
/// card with two header rows.
extension OrielUITests {
    /// The chooser's Files and ⌘K Open Changes Here make labeled panes in the pane's place, rooted at its git
    /// repository; Open in New Tab (`Page.open`) makes a tab right after the current one. File, Preview and Markdown
    /// cards from their labels, their tabs titled by kind and file; an edit shows the dirty dot. The cards come back
    /// after a relaunch.
    func testPluginPanesOpenFromTheChooserThePaletteAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("plugins")
        // A tab after it, so a tab opened right after the current one is not simply the last.
        let (after, _) = try await createTab(in: "w2")
        closeAfter("tab", after)
        try await waitForPrompt(left)
        let repo = "/tmp/oriel-e2e-plugins", root = "/private/tmp/oriel-e2e-plugins"
        try await send("rm -rf \(repo) && mkdir \(repo) && cd \(repo) && git init -q && clear\r", to: left)
        try await waitFor(left) { !$0.contains("git") }
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))

        app.typeKey("d", modifierFlags: .command)
        let chooser = try await replaced(left, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(chooser).chooser.files").exists(within: 3))
        XCTAssertTrue(element("pane.\(chooser).chooser.changes").exists)
        app.typeKey("4", modifierFlags: [])
        let files = try await replaced(chooser, in: tab, besides: [left])
        let filesLabel = try await paneLabel(files)
        XCTAssertTrue(filesLabel.hasPrefix("oriel:files#") && filesLabel.hasSuffix(" \(root)"), filesLabel)
        XCTAssertTrue(element("files.\(files).card").exists(within: 3))
        XCTAssertTrue(element("pane.\(files).title").has(\.stringValue, "oriel-e2e-plugins", within: 3))
        try await waitFor(files, in: nil) { $0.contains("Files") && $0.contains("Shown in Oriel") }

        element("terminal.\(left)").click()
        openPalette()
        app.typeText("open changes here")
        XCTAssertTrue(element("palette.command.Open Changes Here").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let diff = try await replaced(left, in: tab, besides: [files])
        let diffLabel = try await paneLabel(diff)
        XCTAssertTrue(diffLabel.hasPrefix("oriel:diff#") && diffLabel.hasSuffix(" \(root) uncommitted"), diffLabel)
        XCTAssertTrue(element("pane.\(diff).title").has(\.stringValue, "Changes", within: 3))
        keepScreenshot("files and changes cards")

        try await openInNewTab(diff, after: tab, label: " \(root) uncommitted")
        try await fileCards(in: repo, root: root)

        relaunch()
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("files.\(files).card").exists(within: connect))
        XCTAssertTrue(element("diff.\(diff).card").exists)
        let kept = try await paneLabel(files)
        XCTAssertEqual(kept, filesLabel)
    }

    /// Page.open from the card's placeholder: a new tab right after this one, selected, with the same kind and
    /// argument.
    private func openInNewTab(_ diff: String, after tab: String, label: String) async throws {
        let before = try await tabIDs()
        element("diff.\(diff).open").click()
        let opened = try await newTabID(after: before)
        closeAfter("tab", opened)
        let order = try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]] ?? [])
            .compactMap { $0["tab_id"] as? String }
        XCTAssertEqual(order.firstIndex(of: opened), order.firstIndex(of: tab).map { $0 + 1 }, "\(order)")
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 5))
        XCTAssertTrue(element("tab.\(opened)").has(\.label, "Diff Changes", within: 3))
        let copy = try await paneLabel(pane(of: opened))
        XCTAssertTrue(copy.hasPrefix("oriel:diff#") && copy.hasSuffix(label), copy)
    }

    /// A tab per file kind made as Oriel makes one (`layout.apply` with the label and a placeholder): its card, Open
    /// With on This Mac, the tab's title; typing into the markdown placeholder shows the dirty dot.
    private func fileCards(in repo: String, root: String) async throws {
        for (kind, name) in [("file", "main.swift"), ("preview", "icon.png"), ("markdown", "notes.md")] {
            let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
                "type": "pane", "cwd": repo, "label": "oriel:\(kind)#e2e42\(kind.prefix(1)) \(root)/\(name)",
                "command": ["sh", "-c", "cat", "sh"],
            ]])
            let layout = reply["layout"] as? [String: Any]
            let tab: String = try field(layout?["tab_id"], "layout's tab")
            let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
            closeAfter("tab", tab)
            element("tab.\(tab)").click()
            XCTAssertTrue(element("\(kind).\(pane).card").exists(within: 5))
            XCTAssertTrue(element("pane.\(pane).title").has(\.stringValue, name, within: 3))
            XCTAssertTrue(element("pane.\(pane).open-with").exists)
            XCTAssertTrue(element("tab.\(tab)").has(\.label, "\(kind.capitalized) \(name)", within: 3))
            guard kind == "markdown" else { continue }
            XCTAssertFalse(element("pane.\(pane).dirty").exists)
            element("markdown.\(pane).text").click()
            app.typeText("# Notes")
            XCTAssertTrue(element("pane.\(pane).dirty").exists(within: 3))
            keepScreenshot("markdown card, edited")
        }
    }
}
