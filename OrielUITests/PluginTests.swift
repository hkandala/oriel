import XCTest

/// Plugin panes (phase 42): a herdr pane labeled `oriel:<kind>#<iid> <arg>` with a placeholder, shown as the kind's
/// card with two header rows.
extension OrielUITests {
    /// The chooser's Git and ⌘K Open File Explorer Here make labeled panes in the pane's place, rooted at its git
    /// repository (a linked open's new tab: DiffTests). File Explorer cards of a file from their labels (also an old
    /// `preview` one), their tabs titled by kind and file (the dirty dot: FileTests). The cards come back after a
    /// relaunch.
    func testPluginPanesOpenFromTheChooserThePaletteAndLinks() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("plugins")
        // A tab after it, so a tab opened right after the current one is not simply the last.
        let (after, _) = try await createTab(in: "w2")
        closeAfter("tab", after)
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
        XCTAssertTrue(element("pane.\(chooser).chooser.explorer").exists(within: 3))
        XCTAssertTrue(element("pane.\(chooser).chooser.git").exists)
        app.typeKey("5", modifierFlags: [])
        let diff = try await replaced(chooser, in: tab, besides: [left])
        let diffLabel = try await paneLabel(diff)
        XCTAssertTrue(diffLabel.hasPrefix("oriel:git#") && diffLabel.hasSuffix(" \(root)/"), diffLabel)
        XCTAssertTrue(element("git.\(diff).card").exists(within: 3))
        // The Git home, titled by its root.
        XCTAssertTrue(element("pane.\(diff).title").has(\.stringValue, "oriel-e2e-plugins", within: 3))
        try await waitFor(diff, in: nil) { $0.contains("Git") && $0.contains("Shown in Oriel") }

        element("terminal.\(left)").click()
        openPalette()
        app.typeText("open file explorer here")
        XCTAssertTrue(element("palette.command.Open File Explorer Here").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let files = try await replaced(left, in: tab, besides: [diff])
        let filesLabel = try await paneLabel(files)
        XCTAssertTrue(filesLabel.hasPrefix("oriel:explorer#") && filesLabel.hasSuffix(" \(root)/"), filesLabel)
        XCTAssertTrue(element("pane.\(files).title").has(\.stringValue, "oriel-e2e-plugins", within: 3))
        keepScreenshot("file explorer and git cards")

        try await fileCards(in: repo, root: root)

        relaunch()
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("explorer.\(files).card").exists(within: connect))
        XCTAssertTrue(element("git.\(diff).card").exists)
    }

    /// A tab per file page made as Oriel makes one (`layout.apply` with the label and a placeholder): its card and
    /// page, Open With on This Mac, the tab's title.
    private func fileCards(in repo: String, root: String) async throws {
        for (word, page, name) in [("explorer", "file", "main.swift"), ("preview", "preview", "icon.png"),
                                   ("explorer", "markdown", "notes.md")]
        {
            let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
                "type": "pane", "cwd": repo, "label": "oriel:\(word)#e2e42\(page.prefix(1)) \(root)/\(name)",
                "command": ["sh", "-c", "cat", "sh"],
            ]])
            let layout = reply["layout"] as? [String: Any]
            let tab: String = try field(layout?["tab_id"], "layout's tab")
            let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
            closeAfter("tab", tab)
            try await show(tab)
            XCTAssertTrue(element("explorer.\(pane).card").exists(within: 5))
            XCTAssertTrue(element("\(page).\(pane).page").exists)
            XCTAssertTrue(element("pane.\(pane).title").has(\.stringValue, name, within: 3))
            XCTAssertTrue(element("pane.\(pane).open-with").exists)
            XCTAssertTrue(element("tab.\(tab)").has(\.label, "File Explorer \(name)", within: 3))
        }
    }
}

extension OrielUITests {
    /// The registry (phase 47): packages in the plugins folder and the settings' local paths get chooser rows after
    /// Git, by id, and Open ‹chooser› Here; a bad manifest and a taken id are left out. A label naming a plugin not on
    /// this Mac shows its missing card, whose Show Placeholder shows the pane's terminal.
    func testTheRegistryListsUserPackagesAndShowsAMissingPlugin() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("registry")
        try await waitForPrompt(pane)
        let config = "/tmp/oriel-e2e-config"
        try await send(packages(in: config) + "\r", to: pane)
        try await waitFor(pane) { $0.contains("made-42") }
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        let before = try await tabIDs()
        closeNew("tab", besides: before)
        app.typeKey("t", modifierFlags: .command)
        let newTab = try await newTabID(after: before), new = try await self.pane(of: newTab)
        let row = { (id: String) in self.element("pane.\(new).chooser.\(id)") }
        XCTAssertTrue(row("notes").has(\.label, "Notes", within: 3))
        XCTAssertTrue(row("kanban").has(\.label, "Kanban", within: 1))
        XCTAssertEqual(row("explorer").label, "File Explorer")
        XCTAssertFalse(row("broken").exists)
        XCTAssertLessThan(row("git").frame.minY, row("kanban").frame.minY)
        XCTAssertLessThan(row("kanban").frame.minY, row("notes").frame.minY)
        keepScreenshot("user plugins in the chooser")
        // Terminal, Agent, Browser, File Explorer, Git, Kanban, Notes: a folder plugin's label names the folder.
        app.typeKey("7", modifierFlags: [])
        let notes = try await replaced(new, in: newTab, besides: [])
        let label = try await paneLabel(notes)
        XCTAssertTrue(label.hasPrefix("oriel:notes#") && label.hasSuffix("/"), label)

        element("tab.\(tab)").click()
        element("terminal.\(pane)").click()
        openPalette()
        app.typeText("open kanban here")
        XCTAssertTrue(element("palette.command.Open Kanban Here").exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        try await missingCard()
    }

    /// A shell line that writes the config folder: two good packages (one from the settings' local path), a bad
    /// manifest, and a second `explorer`.
    private func packages(in config: String) -> String {
        func package(_ id: String, _ more: String) -> String {
            #"{"version":"1.0.0","description":"\#(id) rows","oriel":{"id":"\#(id)","name":"\#(id)","api":1,"#
                + #""entry":"main.ts","icon":"note.text"\#(more)}}"#
        }
        let files = [
            ("plugins/notes", package("notes", #","opens":{"folders":true},"chooser":"Notes""#)),
            ("plugins/broken", #"{"version":"1.0.0","oriel":{"id":"broken","chooser":"Broken"}}"#),
            ("plugins/twin", package("explorer", #","chooser":"Twin""#)),
            ("local/kanban", package("kanban", #","chooser":"Kanban""#)),
        ]
        var script = "rm -rf \(config)"
        for (folder, json) in files {
            script += " && mkdir -p \(config)/\(folder) && echo '\(json)' > \(config)/\(folder)/package.json"
        }
        return script + #" && echo '{"packages":["./local/kanban"]}' > \#(config)/settings.json"#
            + " && clear && echo made-$((6*7))"
    }

    /// A label naming a plugin not on this Mac: its card, then the pane's terminal.
    private func missingCard() async throws {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": "oriel:csv-table#e2emis /tmp/data.csv",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        try await show(tab)
        XCTAssertTrue(element("pane.\(pane).missing").has(\.stringValue, "csv-table is not on this Mac", within: 5))
        XCTAssertFalse(element("terminal.\(pane)").exists)
        keepScreenshot("missing plugin")
        element("pane.\(pane).show-placeholder").click()
        XCTAssertTrue(element("terminal.\(pane)").exists(within: 3))
        XCTAssertTrue(element("pane.\(pane).missing").vanishes(within: 2))
    }
}
