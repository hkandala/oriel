import XCTest

/// The File and Preview plugins (phase 44, web): a pane labeled `oriel:file#<iid> <path>` or `oriel:preview#…` shows
/// its kind's page over `oriel-plugin://`, which reads the file over the bridge.
extension OrielUITests {
    /// The file in CodeMirror; the jump bar follows the caret; an edit shows the dirty dot and ⌘Z clears it; ⌘S
    /// saves; a change on disk reloads a clean file, and a dirty one gets the toast (Keep Mine, then Reload); ⌘F opens
    /// the editor's search, as do ⌘G and ⇧⌘G; the overview's tile shows it. ⇧⌘← selects in the editor, not Move Tab
    /// Left; ⌘[ reaches the
    /// app before CodeMirror.
    func testAFileCardEditsSavesAndReloadsItsFile() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("file")
        try await waitForPrompt(left)
        let folder = "/tmp/oriel-e2e-file", file = "\(folder)/main.swift"
        try await send("rm -rf \(folder) && mkdir \(folder) && printf 'struct Box {\\n    func open() {\\n        "
            + "let x = 1\\n    }\\n}\\n' >\(file) && clear\r", to: left)
        try await waitFor(left) { !$0.contains("printf") }
        addTeardownBlock { [one] in _ = try? await Self.call(
            one,
            "pane.send_text",
            ["pane_id": left, "text": "rm -rf \(folder)\r"],
        ) }
        element("tab.\(tab)").click()
        let card = try await split(left)
        try await relabel(card, "oriel:file#e2efil \(file)")
        let editor = element("file.\(card).page").textViews.firstMatch
        XCTAssertTrue(until(10) { editor.exists && editor.stringValue.contains("let x = 1") })
        let jump = element("pane.\(card).jump"), dirty = element("pane.\(card).dirty")
        XCTAssertTrue(jump.stringValue.hasPrefix("oriel-e2e-file › main.swift"), jump.stringValue)
        editor.click()
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(jump.has(\.stringValue, "oriel-e2e-file › main.swift › Box › open", within: 3))
        keepScreenshot("file card")

        app.typeText("!")
        XCTAssertTrue(dirty.exists(within: 3))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("// saved")
        XCTAssertTrue(dirty.exists(within: 3))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
        try await send("grep -q '// saved' \(file) && echo saved-$((6*7))\r", to: left)
        try await waitFor(left) { $0.contains("\nsaved-42") }

        try await send("printf 'let y = 2\\n' >\(file)\r", to: left)
        XCTAssertTrue(until(5) { editor.stringValue.hasPrefix("let y = 2") })
        try await diskChangesWhileDirty(card, file: file, shell: left)

        findKeys(card)
        tiled(card, "file")
        try await keysStayInTheEditor(card, shell: left)
    }

    /// ⌘F opens the editor's search with the keyboard; ⌘G and ⇧⌘G (Find Next and Previous) reach it too, and open
    /// it again.
    private func findKeys(_ card: String) {
        let editor = element("file.\(card).page").textViews.firstMatch
        // WebKit takes CodeMirror's `name="search"` field for a search field.
        let search = element("file.\(card).page").searchFields.firstMatch
        for (key, modifiers) in [
            ("f", XCUIElement.KeyModifierFlags.command),
            ("g", .command),
            ("g", [.command, .shift]),
        ] {
            editor.click()
            app.typeKey(key, modifierFlags: modifiers)
            XCTAssertTrue(search.exists(within: 2) && hasKeyboard(search), "\(key) \(modifiers)")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(search.vanishes(within: 2))
        }
    }

    /// A new label, and the metadata report that makes the app read the snapshot (herdr sends no event for a rename),
    /// as an agent's `oriel-panes` does.
    private func relabel(_ pane: String, _ label: String) async throws {
        try await Self.call(one, "pane.rename", ["pane_id": pane, "label": label])
        try await Self.call(one, "pane.report_metadata", ["pane_id": pane, "source": "oriel-panes",
                                                          "tokens": ["oriel-label": "1"], "ttl_ms": 1000])
    }

    /// The card's page shows in its overview tile.
    private func tiled(_ card: String, _ kind: String) {
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(card)").has(\.stringValue, kind, within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
    }

    /// ⇧⌘← (Move Tab Left) selects the line in the editor; ⌘[ (Select Previous Pane) reaches the app, and there ⌘F
    /// is the terminal's Find.
    private func keysStayInTheEditor(_ card: String, shell: String) async throws {
        let editor = element("file.\(card).page").textViews.firstMatch
        editor.click()
        let order = try await tabIDs()
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeKey(.rightArrow, modifierFlags: .command)
        app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        app.typeText("x")
        XCTAssertTrue(until(3) { editor.stringValue.hasPrefix("x\n") })
        let after = try await tabIDs()
        XCTAssertEqual(after, order)
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard("terminal.\(shell)"))
        // Back in the terminal, ⌘F is its own Find again.
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(element("find.field")))
        element("find.close").click()
    }

    /// A change on disk while dirty: the toast; Keep Mine keeps the edit and the next ⌘S writes it over the change;
    /// a ⌘S over it offers Overwrite; Reload takes the disk's text and clears the dot.
    private func diskChangesWhileDirty(_ card: String, file: String, shell: String) async throws {
        let editor = element("file.\(card).page").textViews.firstMatch, dirty = element("pane.\(card).dirty")
        let toast = element("pane.\(card).toast")
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("mine")
        XCTAssertTrue(dirty.exists(within: 3))
        try await send("printf 'let z = 3\\n' >\(file)\r", to: shell)
        XCTAssertTrue(toast.has(\.stringValue, "main.swift changed on disk.", within: 5))
        element("pane.\(card).toast.main").click()
        XCTAssertTrue(toast.vanishes(within: 2))
        XCTAssertTrue(editor.stringValue.contains("mine"))
        editor.click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 3))
        try await send("grep -q mine \(file) && ! grep -q 'z = 3' \(file) && echo kept-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("\nkept-42") }

        // ⌘S over the toast: the disk changed since the read, so the save asks; Overwrite writes.
        app.typeText("over")
        XCTAssertTrue(dirty.exists(within: 3))
        try await send("printf 'let v = 5\\n' >\(file)\r", to: shell)
        XCTAssertTrue(toast.has(\.stringValue, "main.swift changed on disk.", within: 5))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(toast.has(\.stringValue, "main.swift changed on disk since you opened it.", within: 5))
        element("pane.\(card).toast.other").click()
        XCTAssertTrue(dirty.vanishes(within: 3))
        try await send("grep -q over \(file) && ! grep -q 'v = 5' \(file) && echo overwrote-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("\noverwrote-42") }

        app.typeText("again")
        XCTAssertTrue(dirty.exists(within: 3))
        try await send("printf 'let w = 4\\n' >\(file)\r", to: shell)
        XCTAssertTrue(toast.exists(within: 5))
        element("pane.\(card).toast.other").click()
        XCTAssertTrue(until(3) { editor.stringValue.hasPrefix("let w = 4") })
        XCTAssertTrue(dirty.vanishes(within: 3))
    }

    /// An image at Fit, Actual Size and zoomed in, and again after a change on disk; a PDF's page `n of m`, which
    /// follows a scroll; the info view of
    /// another file and of an image that does not decode; audio's player; the overview's tile shows it.
    func testAPreviewCardShowsImagesPDFsAndOtherFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("preview")
        try await waitForPrompt(left)
        let folder = "/tmp/oriel-e2e-preview"
        try await send("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && { printf 'P6\\n1200 900\\n255\\n'; "
            + "head -c 3240000 /dev/zero | tr '\\0' '\\200'; } >gray.ppm && sips -s format png gray.ppm --out icon.png "
            + ">/dev/null && seq 1 150 >lines.txt && cupsfilter lines.txt >lines.pdf 2>/dev/null "
            + "&& head -c 3000 /dev/urandom >notes.bin && printf nope >broken.png "
            + "&& say -o hi.m4a --data-format=aac hi && clear && echo ready-$((6*7))\r", to: left)
        try await waitFor(left) { $0.contains("ready-42") }
        addTeardownBlock { [one] in _ = try? await Self.call(
            one,
            "pane.send_text",
            ["pane_id": left, "text": "rm -rf \(folder)\r"],
        ) }
        element("tab.\(tab)").click()
        let card = try await split(left)
        let label = "oriel:preview#e2eprv \(folder)/"
        try await relabel(card, label + "icon.png")
        let page = element("preview.\(card).page"), image = page.images["icon.png"]
        XCTAssertTrue(image.exists(within: 10))
        // Fit: as wide as the card at most.
        XCTAssertTrue(until(3) { image.frame.width > 100 && image.frame.width <= page.frame.width + 1 })
        element("pane.\(card).zoom.actual").click()
        XCTAssertTrue(until(3) { abs(image.frame.width - 1200) < 2 })
        element("pane.\(card).zoom.fit").click()
        XCTAssertTrue(until(3) { image.frame.width <= page.frame.width + 1 })
        let fit = image.frame.width
        element("pane.\(card).zoom.in").click()
        XCTAssertTrue(until(3) { abs(image.frame.width - fit * 1.25) < 2 })
        XCTAssertFalse(element("pane.\(card).page").exists)
        keepScreenshot("preview card, image")
        // A change on disk shows the new image, at Fit.
        try await send("sips -z 200 300 icon.png >/dev/null\r", to: left)
        XCTAssertTrue(until(5) { abs(image.frame.width - 300) < 2 })

        try await relabel(card, label + "lines.pdf")
        let pages = element("pane.\(card).page")
        XCTAssertTrue(until(10) { pages.exists && pages.stringValue.hasPrefix("1 of ") && pages.stringValue != "1 of 1"
        })
        let first = pages.stringValue
        page.scroll(byDeltaX: 0, deltaY: -3000)
        XCTAssertTrue(until(3) { pages.stringValue != first })
        keepScreenshot("preview card, PDF")

        // The info view: another file, and an image that does not decode (never an empty card).
        for file in ["notes.bin", "broken.png"] {
            try await relabel(card, label + file)
            let name = page.staticTexts.matching(NSPredicate(format: "value == %@", file)).firstMatch
            XCTAssertTrue(name.exists(within: 10), file)
        }
        XCTAssertFalse(pages.exists)
        // Audio in WebKit's player.
        try await relabel(card, label + "hi.m4a")
        XCTAssertTrue(until(10) { page.buttons.firstMatch.exists })
        tiled(card, "preview")
    }
}
