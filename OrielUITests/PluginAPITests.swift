import XCTest

/// The plugin API (phase 47): a fixture package (Fixtures/plugin-api, a local path in the settings) calls every part of
/// `oriel` on a folder of its own and shows a line per part. The test reads the lines and checks what the calls did
/// through herdr and the folder: files, git, run, state (the state file, and again after a relaunch), watch, toast,
/// the native menu, Choose Folder…, the Edited dot, the card's places with Back, ⌘S and open.
extension OrielUITests {
    func testAPluginPageCallsEveryPartOfTheAPI() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("plugin-api")
        try await waitForPrompt(shell)
        let config = "/tmp/oriel-e2e-api-config", folder = "/tmp/oriel-e2e-api", root = "/private/tmp/oriel-e2e-api"
        try await writeConfig(config, folder: folder, shell: shell)
        keepPasteboard()
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": folder, "label": "oriel:plugin-api#e2eapi \(root)/",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let cardTab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", cardTab)
        try await show(cardTab)
        XCTAssertTrue(line("ready: yes").exists(within: 10))
        for line in ["state: 1", "card: 1 plugin-api This Mac \(root)/", "files.write: true", #"files.read: "hello\n""#,
                     "files.readBytes: 6", "files.info: 6 false true",
                     "files.changed: changed The file changed on disk",
                     "files.missing: notFound Not a file", #"run: 3 "\#(root)\nin\n""#,
                     "files.list: sub/ .gitignore a.txt ignored.txt!", "files.paths: .gitignore a.txt",
                     "git.root: \(root)", "git.status: U .gitignore, U a.txt", "git.changes: a.txt", "git.commit: one",
                     "git.head: main", "git.branches: main", "git.diff: true", "clipboard: written", "symbol: true"]
        {
            XCTAssertTrue(self.line(line).exists, line)
        }
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "oriel-plugin-api")
        keepScreenshot("plugin API fixture")

        // A change while the card shows; showing it again calls the watch once more.
        let shown = count("visible: true ")
        try await send("echo x > \(folder)/watched.txt\r", to: shell)
        XCTAssertTrue(line("watch: 1").exists(within: 5))
        try await machineChecks(folder, shell: shell, tab: tab, cardTab: cardTab)
        XCTAssertTrue(line("watch.again: yes").exists(within: 5))
        XCTAssertTrue(line("visible: true \(shown + 2)").exists)

        try await cardCalls(card, in: cardTab, root: root)
        try await failingCard(root)

        // The state comes back from the state file.
        relaunch(nil, ["-configFolder", config])
        element("workspace.w2").click()
        try await show(cardTab)
        XCTAssertTrue(line("state: 2").exists(within: 10))
        try await send("rm -rf \(config) \(folder) ~/.local/state/oriel/\(one)/plugin-api\r", to: shell)
    }

    /// The settings with the fixture's folder as a local path, an empty folder for it, and no state file of an earlier
    /// run.
    private func writeConfig(_ config: String, folder: String, shell: String) async throws {
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/plugin-api").path
        try await send(
            "rm -rf \(config) \(folder) ~/.local/state/oriel/\(one)/plugin-api && mkdir -p \(config) \(folder)/sub && "
                + "echo '{\"packages\":[\"\(fixture)\"]}' > \(config)/settings.json && clear && echo made-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("made-42") }
    }

    /// What the calls did, as the machine sees it: the file, the commit, the state file with the header's value.
    private func machineChecks(_ folder: String, shell: String, tab: String, cardTab: String) async throws {
        element("tab.\(tab)").click()
        try await send("clear; cat \(folder)/a.txt; git -C \(folder) log --format=%s; grep -c "
            + "'\"count\":\"counted\".*\"runs\":1' ~/.local/state/oriel/\(one)/plugin-api/e2eapi.json; "
            + "echo done-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("four\none\n1\ndone-42") }
        try await show(cardTab)
    }

    /// The calls that ask the user or move the card, from the fixture's buttons.
    private func cardCalls(_ card: String, in tab: String, root: String) async throws {
        let button = { (title: String) in self.element("main.\(card).page").buttons[title] }
        button("Toast").click()
        XCTAssertTrue(element("pane.\(card).toast").exists(within: 3))
        element("pane.\(card).toast.main").click()
        XCTAssertTrue(line("toast: Yes").exists(within: 3))
        XCTAssertTrue(line("keyboard: true").exists)

        button("Menu").click()
        XCTAssertTrue(app.menuItems["Two"].exists(within: 3))
        app.menuItems["Two"].click()
        XCTAssertTrue(line("menu: two").exists(within: 3))

        button("Pick").click()
        XCTAssertTrue(app.sheets.buttons["Cancel"].exists(within: 5))
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(line("pick: undefined").exists(within: 3))

        button("Dirty").click()
        XCTAssertTrue(element("pane.\(card).dirty").exists(within: 3))
        button("Clean").click()
        XCTAssertTrue(element("pane.\(card).dirty").vanishes(within: 3))

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(line("save: heard").exists(within: 3))
        // The manifest's commands while the card has the keyboard; one with a key the app uses goes without it.
        app.typeKey("y", modifierFlags: [.command, .shift])
        XCTAssertTrue(line("control: shout").exists(within: 3))
        // A header button of the manifest; the header's text the page set.
        element("pane.\(card).again").click()
        XCTAssertTrue(line("control: again").exists(within: 3))
        XCTAssertTrue(element("pane.\(card).count").has(\.stringValue, "counted", within: 1))

        // A place of its own, its label following; Back says where it came back from.
        button("Go").click()
        XCTAssertTrue(line("place: \(root)/sub/ x").exists(within: 3))
        try await expect("the label follows") { try await paneLabel(card).hasSuffix(" \(root)/sub/") }
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(line("place: \(root)/ x").exists(within: 3))
        try await expect("the label goes back") { try await paneLabel(card).hasSuffix(" \(root)/") }

        let before = try await tabIDs()
        closeNew("tab", besides: before)
        button("Open").click()
        let opened = try await newTabID(after: before)
        let pane = try await pane(of: opened)
        let label = try await paneLabel(pane)
        XCTAssertTrue(label.hasSuffix(" \(root)/a.txt"), label)

        // A command whose key the app uses goes without it: ⌘T over the card is New Tab.
        try await show(tab)
        button("Clean").click()
        let tabs = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        _ = try await newTabID(after: tabs)
        XCTAssertFalse(line("control: taken").exists)
    }

    /// A page whose `main` throws (the fixture on a folder named fail): the card says so, with Reload.
    private func failingCard(_ root: String) async throws {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": root, "label": "oriel:plugin-api#e2efal \(root)/fail/",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        try await show(tab)
        XCTAssertTrue(element("pane.\(pane).failure").has(\.stringValue, "Plugin API stopped", within: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'asked to fail'")).firstMatch
            .exists)
        XCTAssertTrue(element("pane.\(pane).reload").exists)
    }

    /// The user's clipboard, every type of it, back after the test (the fixture writes it).
    private func keepPasteboard() {
        let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        addTeardownBlock {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types {
                    item.setData(data, forType: type)
                }
                return item
            })
        }
    }

    /// A line of the fixture's page.
    private func line(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", text)).firstMatch
    }

    /// The number at the end of the line that starts with `prefix`; 0 for none.
    private func count(_ prefix: String) -> Int {
        let text = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
        return text.exists ? Int(text.stringValue.dropFirst(prefix.count)) ?? 0 : 0
    }
}
