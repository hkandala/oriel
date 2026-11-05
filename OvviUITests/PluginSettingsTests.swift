import XCTest

/// A plugin that is not confirmed yet asks in its card, in the confirmation's words; Settings ▸ Plugins lists it
/// (plugins/packages#the-plugins-page), and its page draws its setting with no trust rows. Install loads the card and
/// keeps its id in trust.json; the setting reaches the card at once (API 3) and settings.json keeps it. File Explorer's
/// page draws its manifest's settings.
extension OvviUITests {
    func testAPluginCardAsksAndItsPageSetsItsSettings() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("plugin settings")
        try await waitForPrompt(shell)
        let config = "/tmp/ovvi-e2e-plugin-settings", card = try await shoutCard(config, shell: shell).pane
        XCTAssertTrue(element("pane.\(card).trust").has(\.stringValue, "Install “Shout”?", within: 10))
        XCTAssertEqual(element("pane.\(card).trust.words").stringValue,
                       "Plugins run code as you on this Mac and on the machines whose cards you open, including "
                           + "their build script. Install plugins only from sources you trust.")

        // ⌘, opens the window; the Plugins page lists the browser and the plugin.
        app.typeKey(",", modifierFlags: .command)
        let page = element("settings.page.plugins")
        XCTAssertTrue(page.exists(within: 5))
        let settings = settingsWindow
        page.click()
        let row = element("plugins.ovvi-e2e-shout")
        XCTAssertTrue(row.exists(within: 5))
        XCTAssertEqual(element("plugins.browser").label, "Browser, Comes with Ovvi")
        keepScreenshot("plugins page dark", of: settings)
        row.click()
        let shout = element("plugins.ovvi-e2e-shout.setting.shout")
        XCTAssertTrue(shout.exists(within: 5))
        XCTAssertTrue(element("plugins.ovvi-e2e-shout.remove").exists)
        XCTAssertFalse(element("plugins.ovvi-e2e-shout.allow").exists, "a trust row on the plugin's page")

        // Install in the card loads it and keeps its id; the setting reaches it at once, and settings.json keeps it.
        element("pane.\(card).trust.allow").click()
        XCTAssertTrue(text("Shout false at load").exists(within: 10))
        shout.click()
        XCTAssertTrue(text("Shout true").exists(within: 3))
        try await send("clear; tr -d ' \\n' < \(config)/settings.json | grep -q "
            + "'\"plugins\":{\"ovvi-e2e-shout\":{\"shout\":true}}' && grep -qx '\\[\"ovvi-e2e-shout\"\\]' "
            + "\(config)/trust.json && echo kept-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("kept-42") }

        defaultPluginPage(page, in: settings)
        settingsWindow.buttons["_XCUI:CloseWindow"].click()
    }

    /// A default plugin's page: its manifest's settings. Pictures of both pages in dark and light.
    private func defaultPluginPage(_ page: XCUIElement, in settings: XCUIElement) {
        // Back to the list: a click on the selected row changes nothing.
        element("settings.page.general").click()
        page.click()
        element("plugins.explorer").click()
        XCTAssertTrue(element("plugins.explorer.setting.markdown").exists(within: 5))
        XCTAssertTrue(element("plugins.explorer.setting.hidden-files").exists)
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
            + #""name":"Shout","api":3,"entry":"main.js","icon":"megaphone","#
            + #""settings":[{"id":"shout","type":"toggle","title":"Shout","default":false}]}}"#
        let main = #"export default function main(ovvi) { const p = document.body.appendChild("#
            + #"document.createElement("p")); const draw = (more) => { p.textContent = "Shout " + "#
            + #"ovvi.settings.get("shout") + more }; "#
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
