import XCTest

/// Plugin packages (phase 47, tracks F and F2): the building page's CSV Table (Fixtures/csv-table, its own esbuild
/// build
/// script) as a local path, its dependencies installed from npm's cache as its author would. Its first card asks for
/// trust, then says it is not built; Build runs its build script and the page loads. An edit that imports a dependency
/// from the package's own `node_modules` shows after Reload Plugin (⌥⌘R) with the header's values kept; a failed build
/// keeps the page and says so, and the log has it. Then the Plugins panel installs the same package from a local git
/// repository at a tag, which installs its dependencies and builds it.
extension OrielUITests {
    func testAPluginPackageAsksForTrustBuildsAndReloads() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("packages")
        try await waitForPrompt(shell)
        let config = "/tmp/oriel-e2e-packages", csv = "/tmp/oriel-e2e-csv", data = "/tmp/oriel-e2e-csv-data"
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/csv-table").path
        let logs = "~/Library/Logs/Oriel/plugins/oriel-e2e-", log = logs + "csv-table.log"
        try await send("rm -rf \(config) \(csv) \(data) \(logs)* ~/.local/state/oriel/\(one)/oriel-e2e-csv-table && "
            + "mkdir -p \(config) \(data) && cp -R \(fixture) \(csv) && (cd \(csv) && npm_config_offline=true npm ci "
            + "--no-audit --no-fund --silent) && printf 'name,count\\nb,2\\na,10\\nc,1\\n' > "
            + "\(data)/a.csv && echo '{\"packages\":[\"\(csv)\"]}' > \(config)/settings.json && clear && "
            + "echo made-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(config) \(csv) "
                    + "\(data) /tmp/oriel-e2e-csv-repo ~/.local/state/oriel/\(one)/oriel-e2e-csv-table\r"])
        }
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": data, "label": "oriel:oriel-e2e-csv-table#e2ecsv \(data)/a.csv",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let cardTab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", cardTab)
        try await show(cardTab)

        try await trustsAndBuilds(card, csv: csv, shell: shell, tab: tab, cardTab: cardTab)
        let rows = element("pane.\(card).rows")
        XCTAssertTrue(rows.has(\.stringValue, "3 rows", within: 5))
        // A header value the page reads again after the reload.
        element("pane.\(card).first-row").click()
        XCTAssertTrue(rows.has(\.stringValue, "4 rows", within: 5))

        try await reloads(card, in: cardTab, csv: csv, shell: shell, tab: tab)
        element("tab.\(tab)").click()
        try await send("clear; grep -c 'CSV Table did not build' \(log); echo logged-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("1\nlogged-42") }

        try await installFromGit(fixture, config: config, shell: shell)
    }

    /// Its code runs only after Allow: Reload Plugins over the prompt builds nothing. Then it is not built yet, and
    /// Build runs its build script.
    private func trustsAndBuilds(_ card: String, csv: String, shell: String, tab: String,
                                 cardTab: String) async throws
    {
        let trust = element("pane.\(card).trust")
        XCTAssertTrue(trust.has(\.stringValue, "Trust “CSV Table”?", within: 10))
        XCTAssertEqual(element("pane.\(card).trust.words").stringValue,
                       "It can read files and folders on the machine of each card you open. "
                           + "Its build script runs as you on this Mac when Oriel builds it.")
        XCTAssertFalse(text("CSV Table one").exists)
        keepScreenshot("plugin trust prompt")
        let filter = openPalette()
        filter.typeText("reload plugins")
        XCTAssertTrue(element("palette.command.Reload Plugins").exists(within: 2))
        filter.typeText("\r")
        XCTAssertTrue(trust.exists(within: 2))
        element("tab.\(tab)").click()
        try await send("clear; ls \(csv)/dist || echo unbuilt-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("unbuilt-42") }
        try await show(cardTab)
        element("pane.\(card).trust.allow").click()
        XCTAssertTrue(element("pane.\(card).failure").has(\.stringValue, "CSV Table is not built", within: 10))
        XCTAssertEqual(element("pane.\(card).failure.text").stringValue,
                       "dist/main.js is missing. Build runs its build script.")
        keepScreenshot("plugin not built")
        element("pane.\(card).build").click()
        XCTAssertTrue(text("CSV Table one").exists(within: 20))
    }

    /// An edit that imports from the package's own node_modules, then Reload Plugin over the card: the new page with
    /// the header's values. Then a build that fails keeps the page and says why.
    private func reloads(_ card: String, in cardTab: String, csv: String, shell: String, tab: String) async throws {
        let rows = element("pane.\(card).rows")
        element("tab.\(tab)").click()
        try await send("mkdir -p \(csv)/node_modules/oriel-e2e-word && echo '{\"name\":\"oriel-e2e-word\","
            + "\"version\":\"1.0.0\",\"main\":\"index.js\"}' > \(csv)/node_modules/oriel-e2e-word/package.json && "
            + "echo 'export const word = \"two\"' > \(csv)/node_modules/oriel-e2e-word/index.js && "
            + "sed -i '' 's/^const caption = .*/import { word } from \"oriel-e2e-word\"; const caption = "
            + "`CSV Table ${word}`/' \(csv)/src/main.ts && clear && echo edited-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("edited-42") }
        try await show(cardTab)
        element("oriel-e2e-csv-table.\(card).card").click()
        app.typeKey("r", modifierFlags: [.command, .option])
        XCTAssertTrue(text("CSV Table two").exists(within: 10))
        XCTAssertTrue(rows.has(\.stringValue, "4 rows", within: 5))

        // A build that fails keeps the page and says why.
        element("tab.\(tab)").click()
        try await send("echo 'export default {' >> \(csv)/src/main.ts && clear && echo broken-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("broken-42") }
        try await show(cardTab)
        element("oriel-e2e-csv-table.\(card).card").click()
        app.typeKey("r", modifierFlags: [.command, .option])
        let toast = element("pane.\(card).toast")
        XCTAssertTrue(toast.exists(within: 10))
        XCTAssertTrue((toast.stringValue).hasPrefix("CSV Table did not build"), toast.stringValue)
        XCTAssertTrue(text("CSV Table two").exists)
    }

    /// Oriel ▸ Plugins… installs the fixture from a local git repository at its tag, after the trust prompt, with its
    /// dependencies and its build; the row shows the tag's version and its source. New Plugin… makes one from the
    /// template.
    private func installFromGit(_ fixture: String, config: String, shell: String) async throws {
        let repo = "/tmp/oriel-e2e-csv-repo", git = "git -C \(repo) -c user.name=e2e -c user.email=e2e@e2e"
        try await send(
            "rm -rf \(repo) && cp -R \(fixture) \(repo) && sed -i '' "
                + "'s/\"oriel-e2e-csv-table\"/\"oriel-e2e-csv-git\"/; s/\"CSV Table\"/\"CSV Git\"/' "
                + "\(repo)/package.json && git init -q \(repo) && \(git) add . && "
                + "\(git) commit -qm one && \(git) tag v1 && sed -i '' 's/0.1.0/0.2.0/' \(repo)/package.json && "
                + "\(git) commit -qam two && clear && echo repo-$((6*7))\r",
            to: shell,
        )
        try await waitFor(shell) { $0.contains("repo-42") }
        app.menuBars.menuBarItems["Oriel"].click()
        app.menuBars.menuItems["Plugins…"].click()
        let source = element("plugins.source")
        XCTAssertTrue(source.exists(within: 5))
        source.click()
        source.typeText("git:\(repo)@v1\r")
        let allow = app.sheets.buttons["Install"]
        XCTAssertTrue(allow.exists(within: 10))
        allow.click()
        XCTAssertTrue(element("plugins.oriel-e2e-csv-git.version").has(\.stringValue, "0.1.0", within: 30))
        XCTAssertEqual(element("plugins.oriel-e2e-csv-git.source").stringValue, "git:\(repo)@v1")
        XCTAssertTrue(element("plugins.oriel-e2e-csv-git.update").exists)
        XCTAssertEqual(element("plugins.oriel-e2e-csv-table.source").stringValue, "/tmp/oriel-e2e-csv")
        // New Plugin… makes one from the template, installed and built.
        element("plugins.new").click()
        let name = app.sheets.textFields.firstMatch
        XCTAssertTrue(name.exists(within: 5))
        name.typeText("Oriel E2E Lines")
        app.sheets.buttons["Create"].click()
        XCTAssertTrue(element("plugins.oriel-e2e-lines.version").has(\.stringValue, "0.1.0", within: 30))
        keepScreenshot("plugins panel")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(source.exists)
        try await send("clear; test -f \(config)/plugins/oriel-e2e-csv-repo/dist/main.js && test -f "
            + "\(config)/plugins/oriel-e2e-lines/dist/main.js && echo built-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("built-42") }
    }

    /// Text the plugin's page shows.
    private func text(_ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
    }
}
