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
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/plugin-api").path
        try await send("rm -rf \(config) \(folder) && mkdir -p \(config) \(folder)/sub && "
            + "echo '{\"packages\":[\"\(fixture)\"]}' > \(config)/settings.json && clear && echo made-$((6*7))\r",
            to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
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
        for line in ["state: 1", "card: 1 plugin-api This Mac \(root)/", #"files.read: "hello\n""#,
                     "files.changed: changed The file changed on disk", "files.missing: notFound Not a file",
                     #"run: 3 "\#(root)\nin\n""#, "git.root: \(root)", "git.commit: one", "git.head: main",
                     "git.diff: true", "symbol: true", "controls: counted"]
        {
            XCTAssertTrue(self.line(line).exists, line)
        }
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "oriel-plugin-api")
        keepScreenshot("plugin API fixture")

        // What the calls did, as the machine sees it.
        element("tab.\(tab)").click()
        try await send("clear; cat \(folder)/a.txt; git -C \(folder) log --format=%s; echo x > \(folder)/watched.txt; "
            + "grep -c runs ~/.local/state/oriel/\(one)/plugin-api/e2eapi.json; echo done-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("four\none\n1\ndone-42") }
        try await show(cardTab)
        XCTAssertTrue(line("watch: 1").exists(within: 5))

        try await cardCalls(card, root: root)
        try await failingCard(root)

        // The state comes back from the state file.
        relaunch(nil, ["-configFolder", config])
        element("workspace.w2").click()
        try await show(cardTab)
        XCTAssertTrue(line("state: 2").exists(within: 10))
        try await send("rm -rf \(config) \(folder)\r", to: shell)
    }

    /// The calls that ask the user or move the card, from the fixture's buttons.
    private func cardCalls(_ card: String, root: String) async throws {
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
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuBars.menuItems["Taken Key"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])

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

    /// A line of the fixture's page.
    private func line(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", text)).firstMatch
    }
}
