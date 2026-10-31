import XCTest

/// A plugin's header row (phase 47, future-work/plugins/manifest#header).
extension OrielUITests {
    /// A user plugin's controls, drawn from its manifest before its page loads: Back and Forward at the row's left
    /// edge, a menu with a section and a divider, a path text, a badge in a button's label, a field that takes the free
    /// width, Open With; a hidden control is not drawn. A toggle and segments change at once, a menu pick leaves the
    /// value to the page, and the floating window draws the same row with the same values. A plugin with no header has
    /// one header row.
    func testAPluginsHeaderDrawsItsManifestsControls() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("header")
        try await waitForPrompt(shell)
        let config = "/tmp/oriel-e2e-header"
        try await send(fixture(in: config) + "\r", to: shell)
        try await waitFor(shell) { $0.contains("made-42") }
        relaunch(nil, ["-configFolder", config])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let card = try await pluginTab("oriel:fixture#e2ehdr /tmp/notes.md")

        let control = { (id: String) in self.element("pane.\(card).\(id)") }
        XCTAssertTrue(control("root").exists(within: 5))
        XCTAssertEqual(control("root").value as? String, "oriel")
        XCTAssertFalse(control("go-back").isEnabled)
        XCTAssertEqual(control("jump").value as? String, "Sources › App.swift › body")
        XCTAssertEqual(control("push").label, "Push, 2")
        XCTAssertTrue(control("open-with").exists)
        XCTAssertFalse(control("gone").exists)
        // Over the page's left edge (11 pt into the card, the page 10 pt), in the pane and floating.
        let page = element("fixture.\(card).card").frame
        XCTAssertEqual(control("go-back").frame.minX - page.minX, 1, accuracy: 1, "\(page)")
        XCTAssertGreaterThan(control("filter").frame.width, control("jump").frame.width)
        keepScreenshot("plugin header")

        XCTAssertTrue(control("outline").isSelected)
        control("outline").click()
        XCTAssertTrue(control("outline").has(\.isSelected, false, within: 2))
        control("mode.edit").click()
        XCTAssertTrue(control("mode.edit").has(\.isSelected, true, within: 2))
        control("root").click()
        for item in ["Places", "tmp", "Choose…"] {
            XCTAssertTrue(control("root").menuItems[item].exists(within: 2), item)
        }
        control("root").menuItems["tmp"].click()
        XCTAssertTrue(control("root").menuItems["tmp"].vanishes(within: 2))
        XCTAssertEqual(control("root").value as? String, "oriel")

        let window = try float(card)
        let floating = { (id: String) in self.element("pane.\(card).\(id)", in: window) }
        XCTAssertTrue(floating("mode.edit").has(\.isSelected, true, within: 3))
        XCTAssertFalse(floating("outline").isSelected)
        let content = element("fixture.\(card).card", in: window).frame
        XCTAssertEqual(floating("go-back").frame.minX - content.minX, 1, accuracy: 1, "\(content)")
        keepScreen("plugin header floating")
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.vanishes(within: 3))

        // The page starts right under row 1.
        let bare = try await pluginTab("oriel:bare#e2ebar /tmp")
        XCTAssertTrue(element("bare.\(bare).card").exists(within: 5))
        let top = element("bare.\(bare).card").frame.minY - element("pane.\(bare)").frame.minY
        XCTAssertLessThan(top, 50, "one row of 36 pt, not two")
        try await send("rm -rf \(config) /tmp/notes.md\r", to: shell)
    }

    /// A new tab whose pane has this label, shown; its pane.
    private func pluginTab(_ label: String) async throws -> String {
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": label, "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        try await show(tab)
        return pane
    }

    /// A shell line that writes a plugin whose header has every control type, and one with no header.
    private func fixture(in config: String) -> String {
        let header = [
            #"{"id":"root","type":"menu","symbol":"folder","title":"oriel","items":[{"title":"Places"},"#
                + #"{"value":"/tmp","title":"tmp","symbol":"folder"},"-",{"value":"choose","title":"Choose…"}]}"#,
            #"{"id":"filter","type":"field","placeholder":"Filter"}"#,
            #"{"id":"jump","type":"text","style":"path","symbol":"curlybraces","#
                + #""value":["Sources","App.swift","body"]}"#,
            #"{"id":"rows","type":"text","style":"dim","value":"3 of 12"}"#,
            #"{"id":"mode","type":"segmented","options":[{"value":"read","title":"Read"},"#
                + #"{"value":"edit","title":"Edit"}],"value":"read"}"#,
            #"{"id":"outline","type":"toggle","symbol":"sidebar.left","title":"Outline","value":true}"#,
            #"{"id":"push","type":"button","symbol":"arrow.up","title":"Push","badge":"2"}"#,
            #"{"id":"gone","type":"button","symbol":"trash","title":"Gone","hidden":true}"#,
            #"{"id":"open-with","type":"openWith","value":"/tmp/notes.md"}"#,
        ].joined(separator: ",")
        let json = #"{"version":"1.0.0","oriel":{"id":"fixture","name":"Fixture","api":1,"entry":"main.ts","#
            + #""icon":"testtube.2","history":true,"header":[\#(header)]}}"#
        let bare = #"{"version":"1.0.0","oriel":{"id":"bare","name":"Bare","api":1,"entry":"main.ts","icon":"leaf"}}"#
        return "rm -rf \(config) && mkdir -p \(config)/plugins/fixture \(config)/plugins/bare && touch /tmp/notes.md"
            + " && echo '\(json)' > \(config)/plugins/fixture/package.json"
            + " && echo '\(bare)' > \(config)/plugins/bare/package.json && clear && echo made-$((6*7))"
    }
}
