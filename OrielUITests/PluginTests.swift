import XCTest

/// Plugin panes (phase 42): a herdr pane labeled `oriel:<kind>#<iid> <arg>` with a placeholder, shown as the kind's
/// card with two header rows.
extension OrielUITests {
    /// The chooser's Changes and ⌘K Open Files Here make labeled panes in the pane's place, rooted at its git
    /// repository. File, Preview and Markdown cards from their labels, their tabs titled by kind and file. The
    /// cards come back after a relaunch.
    func testPluginPanesOpenFromTheChooserThePaletteAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("plugins")
        try await waitForPrompt(left)
        let repo = "/tmp/oriel-e2e-plugins", root = "/private/tmp/oriel-e2e-plugins"
        try await send("rm -rf \(repo) && mkdir \(repo) && cd \(repo) && git init -q && clear && echo ready-$((6*7))\r",
                       to: left)
        try await waitFor(left) { $0.contains("ready-42") }
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))

        app.typeKey("d", modifierFlags: .command)
        let chooser = try await replaced(left, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(chooser).chooser.files").exists(within: 3))
        XCTAssertTrue(element("pane.\(chooser).chooser.changes").exists)
        app.typeKey("5", modifierFlags: [])
        let diff = try await replaced(chooser, in: tab, besides: [left])
        let diffLabel = try await paneLabel(diff)
        XCTAssertTrue(diffLabel.hasPrefix("oriel:diff#") && diffLabel.hasSuffix(" \(root) uncommitted"), diffLabel)
        XCTAssertTrue(element("diff.\(diff).card").exists(within: 3))
        XCTAssertTrue(element("pane.\(diff).title").has(\.stringValue, "Changes", within: 3))
        try await waitFor(diff, in: nil) { $0.contains("Diff") && $0.contains("Shown in Oriel") }

        element("terminal.\(left)").click()
        openPalette()
        app.typeText("open files here")
        XCTAssertTrue(element("palette.command.Open Files Here").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let files = try await replaced(left, in: tab, besides: [diff])
        let filesLabel = try await paneLabel(files)
        XCTAssertTrue(filesLabel.hasPrefix("oriel:files#") && filesLabel.hasSuffix(" \(root)"), filesLabel)
        XCTAssertTrue(element("pane.\(files).title").has(\.stringValue, "oriel-e2e-plugins", within: 3))
        keepScreenshot("files and changes cards")

        try await fileCards(in: repo, root: root)

        relaunch()
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("files.\(files).card").exists(within: connect))
        XCTAssertTrue(element("diff.\(diff).card").exists)
    }

    /// A tab per file kind made as Oriel makes one (`layout.apply` with the label and a placeholder): its card, Open
    /// With on This Mac, the tab's title.
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
        }
    }
}
