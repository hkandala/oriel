import XCTest

/// `ovvi plugins` (agent-control/cli, plugins): the registry for agents, and New Plugin, Reload Plugin and Install
/// from a pane on This Mac, each in a config folder of the test's own.
extension OvviUITests {
    /// The list with a package that did not load, `--for` with its default, then an install of a local folder: the
    /// confirmation names the asking pane and its folder, Cancel is `declined`, Install answers with the plugin, which
    /// then opens CSV files.
    func testTheOvviCommandListsAndInstallsPlugins() async throws {
        let config = "/tmp/ovvi-e2e-agent-plugins", csv = "/tmp/ovvi-e2e-agent-csv"
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/csv-table").path
        let (_, pane) = try await agentPluginsSetUp(config, "mkdir -p \(config)/plugins/broken && echo '{\"version\":"
            + "\"1.0.0\",\"ovvi\":{\"id\":\"broken\"}}' > \(config)/plugins/broken/package.json && rm -rf \(csv) && "
            + "cp -R \(fixture) \(csv)", clean: csv)
        let ovvi = Self.ovviCommand
        try await run("\(ovvi) plugins", in: pane, "list", 0, "browser", "explorer", "git")
        try await run("\(ovvi) plugins | grep '^broken'", in: pane, "broken", 0, "broken")
        try await run("\(ovvi) plugins | grep -c 'package.json: ovvi.name is missing'", in: pane, "why", 0, "1")
        try await run("\(ovvi) plugins --for a.csv | head -1 | grep -c 'explorer.*default'", in: pane, "for", 0, "1")

        // The command waits on the prompt; the test answers it, then reads the exit.
        let install = "\(ovvi) --timeout 60 plugins install \(csv)"
        try await send("\(install) --json; echo cancel-$((6*7))-$?\r", to: pane)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.buttons["Install"].exists(within: 10))
        let words = sheet.staticTexts.allElementsBoundByIndex.map { $0.value as? String ?? "" }.joined(separator: "\n")
        XCTAssertTrue(words.contains("in pane \(pane) asks to install it."), words)
        XCTAssertTrue(words.contains("ovvi-e2e-csv-table 0.1.0 in \(csv)"), words)
        XCTAssertTrue(words.contains("Install plugins only from sources you trust."), words)
        keepScreenshot("agent install confirmation")
        sheet.buttons["Cancel"].click()
        try await waitFor(pane) { $0.contains("\ncancel-42-") }
        let canceled = try await read(pane)
        XCTAssertTrue(
            canceled.contains("\ncancel-42-1") && canceled.contains("ovvi: the user did not allow")
                && canceled.contains(#"{"error":{"code":"declined""#),
            canceled,
        )

        try await send("\(install) | grep -c '^ovvi-e2e-csv-table'; echo installed-$((6*7))-$?\r", to: pane)
        XCTAssertTrue(sheet.buttons["Install"].exists(within: 10))
        sheet.buttons["Install"].click()
        try await waitFor(pane, times: 100) { $0.contains("\ninstalled-42-") }
        let installed = try await read(pane)
        XCTAssertTrue(installed.contains("\n1\ninstalled-42-0"), installed)
        try await run("\(ovvi) plugins --for a.csv | head -1 | grep -c '^ovvi-e2e-csv-table.*\(csv).*default'",
                      in: pane, "default", 0, "1")
        // A folder by the disk, also one with a file's name.
        try await run("mkdir \(csv)/d.csv && \(ovvi) plugins --for \(csv)/d.csv | head -1 | grep -c "
            + "'^explorer.*default'", in: pane, "folder", 0, "1")
        try await run("\(ovvi) plugins --json | grep -c '\"log\":\"\(config)/logs/plugins/ovvi-e2e-csv-table.log\"'",
                      in: pane, "log", 0, "1")
        // Again is an Update: the user's, on the Plugins page.
        try await run(install, in: pane, "again", 1, "ovvi: \(csv) is installed")
    }

    /// New Plugin from an agent: made, built and confirmed; Reload Plugin answers its build, and a broken build its
    /// last lines. A card with unsaved edits stops a reload with `dirty`, and keeps its edits.
    func testTheOvviCommandMakesAndReloadsAPlugin() async throws {
        let config = "/tmp/ovvi-e2e-agent-new", folder = "/tmp/ovvi-e2e-agent-file"
        let (tab, pane) = try await agentPluginsSetUp(config, "rm -rf \(folder) && mkdir \(folder) && echo one > "
            + "\(folder)/a.txt", clean: folder)
        let ovvi = Self.ovviCommand, made = "\(config)/plugins/ovvi-e2e-agent"
        // New installs the template's dependencies from npm's cache and builds it: more than `run`'s 10 s.
        try await send("\(ovvi) --timeout 120 plugins new 'Ovvi E2E Agent' | grep -c '^id: ovvi-e2e-agent'; "
            + "echo new-$((6*7))-$?\r", to: pane)
        try await waitFor(pane, times: 1200) { $0.contains("\nnew-42-") }
        let new = try await read(pane)
        XCTAssertTrue(new.contains("\n1\nnew-42-0"), new)
        try await run("test -f \(made)/dist/main.js && grep -c ovvi-e2e-agent \(config)/trust.json", in: pane,
                      "made", 0, "1")
        // The template opens text files as an Open With choice: after the default.
        try await run("\(ovvi) plugins --for a.txt | awk '{ printf \"%s,\", $1 } END { print \"\" }'", in: pane, "for",
                      0, "explorer,ovvi-e2e-agent,")
        try await run("\(ovvi) plugins reload ovvi-e2e-agent", in: pane, "reload", 0, "built: true", "cards: 0")
        try await run("echo 'export default {' >> \(made)/src/main.ts", in: pane, "broke", 0)
        // The code on standard output, the toast's title and the build's own lines on standard error.
        try await run("j=$(\(ovvi) --json plugins reload ovvi-e2e-agent 2>\(made)/err); s=$?; echo \"$j\" | "
            + "grep -c '\"code\":\"build_failed\"'; grep -q '^ovvi: Ovvi E2E Agent did not build:' \(made)/err && "
            + "grep -q 'main.ts' \(made)/err && echo stderr; (exit $s)", in: pane, "failed", 1, "1\nstderr")
        try await run("\(ovvi) plugins reload nope", in: pane, "nope", 1, "ovvi: no plugin nope")

        element("workspace.w2").click()
        element("tab.\(tab)").click()
        let card = try await split(pane)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "ovvi:explorer#e2eagt \(folder)/a.txt"])
        let editor = element("file.\(card).page").textViews.firstMatch, dirty = element("pane.\(card).dirty")
        XCTAssertTrue(until(10) { editor.exists && editor.stringValue.contains("one") })
        editor.click()
        app.typeText("!")
        XCTAssertTrue(dirty.exists(within: 3))
        try await run("\(ovvi) plugins reload explorer", in: pane, "dirty", 1,
                      "ovvi: pane \(card) has unsaved edits")
        XCTAssertTrue(dirty.exists && editor.stringValue.contains("!"), editor.stringValue)
        // No toast asks: the user's edits are not the agent's to drop.
        XCTAssertFalse(element("pane.\(card).toast").exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
    }

    /// From Key Host (CI's sshd): the list without logs; new, reload and install are `other_machine`.
    func testTheOvviPluginsCommandFromARemoteMachine() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await waitForPrompt("w1:p1")
        try await expectOpen("w1")
        let ovvi = Self.ovviCommand
        // The Key Host store writes the script once its session opens.
        try await run("until \(ovvi) status >/dev/null; do sleep 0.1; done", in: "w1:p1", "ready", 0)
        try await run("\(ovvi) plugins | head -1", in: "w1:p1", "list", 0, "browser")
        try await run("j=$(\(ovvi) plugins --json) && echo \"$j\" | grep -q '\"id\":\"browser\"' && ! echo \"$j\" | "
            + "grep -q '\"log\"' && echo no-logs", in: "w1:p1", "logs", 0, "no-logs")
        for (index, sub) in ["new x", "reload", "install npm:x"].enumerated() {
            try await run("\(ovvi) plugins \(sub)", in: "w1:p1", "remote\(index)", 1,
                          "ovvi: plugins \(sub.split(separator: " ")[0]) works only")
        }
    }

    /// A config folder made by the line, the app relaunched on it, and a new tab's shell ready for the command. The
    /// folder and `clean` go after the test.
    private func agentPluginsSetUp(_ config: String, _ line: String,
                                   clean: String) async throws -> (tab: String, pane: String)
    {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("plugins")
        try await waitForPrompt(pane)
        try await send("rm -rf \(config) && mkdir -p \(config) && \(line) && clear && echo made-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("made-42") }
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "rm -rf \(config) \(clean)\r"])
        }
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        try await waitForPrompt(pane)
        try await expectOpen("w2")
        return (tab, pane)
    }
}
