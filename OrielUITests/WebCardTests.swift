import XCTest

/// The plugin cards' web host (phase 44): a pane labeled `oriel:webtest#<iid> <path>` shows the bundle's test page
/// over `oriel-plugin://`, a CodeMirror editor that reads the file over the bridge and reports dirty.
extension OrielUITests {
    /// The file's text shows in the editor. A typed letter makes the card dirty and ⌘Z (CodeMirror's history) clean;
    /// ⇧⌘← selects in the editor, not Move Tab Left; ⌘[ reaches the app (Select Previous Pane) before CodeMirror's
    /// indent.
    func testWebCardEditsAFileItReadOverTheBridge() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("web")
        try await waitForPrompt(left)
        let file = "/tmp/oriel-e2e-web.txt"
        try await Self.call(one, "pane.send_text", [
            "pane_id": left, "text": "printf 'oriel-web-%s' $((6*7)) >\(file) && clear\r",
        ])
        try await waitFor(left, in: nil) { !$0.contains("printf") }
        element("tab.\(tab)").click()
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "oriel:webtest#e2eweb \(file)"])
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(until(10) { editor.value as? String == "oriel-web-42" })
        let edited = element("webtest.\(card)")
        XCTAssertEqual(edited.value as? String, "clean")
        keepScreenshot("web card")

        editor.click()
        app.typeKey(.rightArrow, modifierFlags: .command)
        app.typeText("!")
        XCTAssertTrue(until(3) { edited.value as? String == "dirty" })
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(until(3) { edited.value as? String == "clean" })

        let order = try await tabIDs()
        app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        app.typeText("x")
        XCTAssertTrue(until(3) { editor.value as? String == "x" })
        let after = try await tabIDs()
        XCTAssertEqual(after, order)
        XCTAssertTrue(element("tab.\(tab)").isSelected)

        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        XCTAssertEqual(editor.value as? String, "x")
    }
}
