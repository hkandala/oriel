import XCTest

/// Plugin packages (phase 47, track F): the building page's CSV Table (Fixtures/csv-table) as a local path. Its first
/// card asks for trust, builds and loads; an edit that imports a dependency from the package's own `node_modules`
/// shows after Reload Plugin (⌥⌘R) with the header's values kept; a failed build keeps the page and says so, and the
/// log has it. Then Settings › Plugins installs the same package from a local git repository at a tag.
extension OrielUITests {
    func testAPluginPackageAsksForTrustBuildsAndReloads() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("packages")
        try await waitForPrompt(shell)
        let config = "/tmp/oriel-e2e-packages", csv = "/tmp/oriel-e2e-csv", data = "/tmp/oriel-e2e-csv-data"
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/csv-table").path
        let log = "~/Library/Logs/Oriel/plugins/csv-table.log"
        try await send("rm -rf \(config) \(csv) \(data) \(log) ~/.local/state/oriel/\(one)/csv-table && mkdir -p "
            + "\(config) \(data) && cp -R \(fixture) \(csv) && printf 'name,count\\nb,2\\na,10\\nc,1\\n' > "
            + "\(data)/a.csv && echo '{\"packages\":[\"\(csv)\"]}' > \(config)/settings.json && clear && "
            + "echo made-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(config) \(csv) "
                    + "\(data) /tmp/oriel-e2e-csv-repo ~/.local/state/oriel/\(one)/csv-table\r"])
        }
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()

        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": data, "label": "oriel:csv-table#e2ecsv \(data)/a.csv",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let cardTab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", cardTab)
        try await show(cardTab)

        // Its code runs only after Allow.
        let trust = element("pane.\(card).trust")
        XCTAssertTrue(trust.has(\.stringValue, "Trust “CSV Table”?", within: 10))
        XCTAssertEqual(element("pane.\(card).trust.words").stringValue,
                       "It can read files and folders on the machine of each card you open.")
        XCTAssertFalse(text("CSV Table one").exists)
        keepScreenshot("plugin trust prompt")
        element("pane.\(card).trust.allow").click()
        XCTAssertTrue(text("CSV Table one").exists(within: 10))
        let rows = element("pane.\(card).rows")
        XCTAssertTrue(rows.has(\.stringValue, "3 rows", within: 5))
        // A header value the page reads again after the reload.
        element("pane.\(card).first-row").click()
        XCTAssertTrue(rows.has(\.stringValue, "4 rows", within: 5))

        try await reloads(card, in: cardTab, csv: csv, shell: shell, tab: tab)
        element("tab.\(tab)").click()
        try await send("clear; grep -c 'build failed' \(log); echo logged-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("1\nlogged-42") }

        try await installFromGit(fixture, shell: shell)
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
            + "`CSV Table ${word}`/' \(csv)/main.ts && clear && echo edited-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("edited-42") }
        try await show(cardTab)
        element("csv-table.\(card).card").click()
        app.typeKey("r", modifierFlags: [.command, .option])
        XCTAssertTrue(text("CSV Table two").exists(within: 10))
        XCTAssertTrue(rows.has(\.stringValue, "4 rows", within: 5))

        // A build that fails keeps the page and says why.
        element("tab.\(tab)").click()
        try await send("echo 'export default {' >> \(csv)/main.ts && clear && echo broken-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("broken-42") }
        try await show(cardTab)
        element("csv-table.\(card).card").click()
        app.typeKey("r", modifierFlags: [.command, .option])
        let toast = element("pane.\(card).toast")
        XCTAssertTrue(toast.exists(within: 10))
        XCTAssertTrue((toast.stringValue).hasPrefix("CSV Table did not build"), toast.stringValue)
        XCTAssertTrue(text("CSV Table two").exists)
    }

    /// Settings › Plugins installs the fixture from a local git repository at its tag, after the trust prompt; the
    /// row shows the tag's version and its source.
    private func installFromGit(_ fixture: String, shell: String) async throws {
        let repo = "/tmp/oriel-e2e-csv-repo", git = "git -C \(repo) -c user.name=e2e -c user.email=e2e@e2e"
        try await send("rm -rf \(repo) && cp -R \(fixture) \(repo) && sed -i '' 's/\"csv-table\"/\"csv-git\"/g; "
            + "s/\"CSV Table\"/\"CSV Git\"/' \(repo)/package.json && git init -q \(repo) && \(git) add . && "
            + "\(git) commit -qm one && \(git) tag v1 && sed -i '' 's/0.1.0/0.2.0/' \(repo)/package.json && "
            + "\(git) commit -qam two && clear && echo repo-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("repo-42") }
        app.typeKey(",", modifierFlags: .command)
        let source = element("plugins.source")
        XCTAssertTrue(source.exists(within: 5))
        source.click()
        source.typeText("git:\(repo)@v1\r")
        let allow = app.sheets.buttons["Install"]
        XCTAssertTrue(allow.exists(within: 10))
        allow.click()
        XCTAssertTrue(element("plugins.csv-git.version").has(\.stringValue, "0.1.0", within: 10))
        XCTAssertTrue(element("plugins.csv-table").exists)
        app.typeKey("w", modifierFlags: .command)
    }

    /// Text the plugin's page shows.
    private func text(_ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
    }
}
