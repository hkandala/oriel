import XCTest

/// Settings ▸ Plugins (plugins/packages#the-plugins-page): a plugin whose card waits for trust says Needs review, and
/// the sidebar counts it; its page allows it, which loads the card; its setting reaches the card at once (API 3) and
/// settings.json keeps it; Forget Trust brings the trust prompt back and the page's calls fail; Allow loads it again
/// with the value set; Don't Allow closes the waiting card. File Explorer's page draws its manifest's settings and says
/// it never asks.
extension OvviUITests {
    func testAPluginsPageAllowsSetsAndForgetsTrust() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("plugin settings")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-plugin-settings", card = try await shoutCard(config, shell: shell).pane
        XCTAssertTrue(element("pane.\(card).trust").exists(within: 10))

        // ⌘, opens the window; the Plugins page lists the browser and the plugin that waits.
        app.typeKey(",", modifierFlags: .command)
        let page = element("settings.page.plugins")
        XCTAssertTrue(page.exists(within: 5))
        let settings = settingsWindow
        page.click()
        let row = element("plugins.ovvi-e2e-shout")
        XCTAssertTrue(row.exists(within: 5))
        XCTAssertTrue(until(3) { row.label.hasSuffix(", Needs review") }, row.label)
        XCTAssertEqual(page.stringValue, "1", "the sidebar's badge")
        XCTAssertEqual(element("plugins.browser").label, "Browser, Comes with Ovvi")
        keepScreenshot("plugins page dark", of: settings)
        row.click()
        let trust = element("plugins.ovvi-e2e-shout.trust")
        XCTAssertTrue(trust.has(\.stringValue, "Not allowed yet", within: 5))
        keepScreenshot("plugin page waiting", of: settings)

        // Allow loads the card; the setting reaches it at once, and settings.json keeps it.
        element("plugins.ovvi-e2e-shout.allow").click()
        XCTAssertTrue(text("Shout false at load").exists(within: 10))
        XCTAssertTrue(trust.has(\.stringValue, "Allowed", within: 3))
        let shout = element("plugins.ovvi-e2e-shout.setting.shout")
        shout.click()
        XCTAssertTrue(text("Shout true").exists(within: 3))
        try await send("clear; tr -d ' \\n' < \(config)/settings.json | grep -q "
            + "'\"plugins\":{\"ovvi-e2e-shout\":{\"shout\":true}}' && echo kept-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("kept-42") }

        // Forget Trust: the card asks again, and the page under the prompt can call nothing.
        let forget = element("plugins.ovvi-e2e-shout.forget")
        forget.click()
        XCTAssertTrue(element("pane.\(card).trust").exists(within: 5))
        XCTAssertTrue(trust.has(\.stringValue, "Not allowed yet", within: 3))
        shout.click()
        try await send("clear; for i in $(seq 40); do grep -q 'denied: files.list: not trusted' \(config)/logs/plugins/"
            + "*.log && echo denied-$((6*7)) && break; sleep 0.1; done\r", to: shell)
        try await waitFor(shell) { $0.contains("denied-42") }
        // Allow again: the page loads with the value set. Then Don't Allow closes it, as the card's own button does.
        shout.click()
        element("plugins.ovvi-e2e-shout.allow").click()
        XCTAssertTrue(text("Shout true at load").exists(within: 10))
        forget.click()
        XCTAssertTrue(element("pane.\(card).trust").exists(within: 5))
        element("plugins.ovvi-e2e-shout.deny").click()
        try await expect("the waiting card's pane to close") { await (try? self.pane(card)) == nil }

        defaultPluginPage(page, in: settings)
        settingsWindow.buttons["_XCUI:CloseWindow"].click()
    }

    /// A default plugin's page: its manifest's settings, and it never asks. Pictures of both pages in dark and light.
    private func defaultPluginPage(_ page: XCUIElement, in settings: XCUIElement) {
        // Back to the list: a click on the selected row changes nothing.
        element("settings.page.general").click()
        page.click()
        element("plugins.explorer").click()
        XCTAssertTrue(element("plugins.explorer.setting.markdown").exists(within: 5))
        XCTAssertTrue(element("plugins.explorer.setting.hidden-files").exists)
        XCTAssertEqual(element("plugins.explorer.trust").stringValue, "Comes with Ovvi, so it never asks.")
        keepScreenshot("plugin page dark", of: settings)
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        pick("Appearance", "Light")
        keepScreenshot("plugin page light", of: settings)
        // Back to the list: a click on the selected row changes nothing.
        element("settings.page.general").click()
        page.click()
        XCTAssertTrue(element("plugins.explorer").exists(within: 3))
        keepScreenshot("plugins page light", of: settings)
    }

    /// A config folder with the Shout plugin, trusted by no one, with one toggle; the app launched on it, and a card
    /// of the plugin in its own tab. `extra`: a shell command that adds to the folder.
    func shoutCard(_ config: String, shell: String, extra: String = "true") async throws
        -> (tab: String, pane: String)
    {
        let folder = "\(config)/plugins/ovvi-e2e-shout"
        let manifest = #"{"version":"1.0.0","description":"Says it.","ovvi":{"id":"ovvi-e2e-shout","#
            + #""name":"Shout","api":3,"entry":"main.js","icon":"megaphone","permissions":["files:read"],"#
            + #""settings":[{"id":"shout","type":"toggle","title":"Shout","default":false}]}}"#
        // Each draw also reads a folder: a call that fails after Forget Trust is in the log.
        let main = #"export default function main(ovvi) { const p = document.body.appendChild("#
            + #"document.createElement("p")); const draw = (more) => { p.textContent = "Shout " + "#
            + #"ovvi.settings.get("shout") + more; ovvi.files.list("/tmp").catch(() => {}) }; "#
            + #"draw(" at load"); ovvi.on("settings", () => draw("")) }"#
        try await send("rm -rf \(config) && mkdir -p \(folder) && echo '\(manifest)' > \(folder)/package.json && "
            + "echo '\(main)' > \(folder)/main.js && \(extra) && clear && echo made-$((6*7))\r", to: shell)
        // A long line: a loaded Mac's shell takes seconds to echo it.
        try await waitFor(shell, times: 150) { $0.contains("made-42") }
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": shell, "text": "rm -rf \(config)\r"])
        }
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": "ovvi:ovvi-e2e-shout#e2eshu /tmp",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let cardTab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", cardTab)
        try await show(cardTab)
        return (cardTab, card)
    }

    /// Text a plugin's page shows.
    private func text(_ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
    }
}
