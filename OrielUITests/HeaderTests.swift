import XCTest

/// A plugin's header row (phase 47, future-work/plugins/manifest#header).
extension OrielUITests {
    /// A user plugin's controls, drawn from its manifest before its page loads: Back and Forward at the row's left
    /// edge,
    /// a path text, a badge in a button's label, a field that takes the free width, Open With; a hidden control is not
    /// drawn. A toggle and segments change at once, and the floating window draws the same row with the same values.
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
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": "oriel:fixture#e2ehdr /tmp/notes.md",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let card: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        try await show(tab)

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

        let window = try float(card)
        let floating = { (id: String) in self.element("pane.\(card).\(id)", in: window) }
        XCTAssertTrue(floating("mode.edit").has(\.isSelected, true, within: 3))
        XCTAssertFalse(floating("outline").isSelected)
        let content = element("fixture.\(card).card", in: window).frame
        XCTAssertEqual(floating("go-back").frame.minX - content.minX, 1, accuracy: 1, "\(content)")
        keepScreen("plugin header floating")
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.vanishes(within: 3))
        try await send("rm -rf \(config)\r", to: shell)
    }

    /// A shell line that writes a plugin whose header has every control type.
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
        return "rm -rf \(config) && mkdir -p \(config)/plugins/fixture && touch /tmp/notes.md"
            + " && echo '\(json)' > \(config)/plugins/fixture/package.json && clear && echo made-$((6*7))"
    }
}
