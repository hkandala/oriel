import XCTest

/// The File and Preview plugins (phase 44, web): a pane labeled `oriel:file#<iid> <path>` or `oriel:preview#…` shows
/// its kind's page over `oriel-plugin://`, which reads the file over the bridge.
extension OrielUITests {
    /// The file in CodeMirror; the jump bar follows the caret; an edit shows the dirty dot and ⌘Z clears it; ⌘S
    /// saves; a change on disk reloads a clean file, and a dirty one gets the toast (Keep Mine, then Reload); ⌘F opens
    /// the editor's search. ⇧⌘← selects in the editor, not Move Tab Left; ⌘[ reaches the app before CodeMirror.
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
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "oriel:file#e2efile \(file)"])
        let editor = element("file.\(card).page").textViews.firstMatch
        XCTAssertTrue(until(10) { editor.stringValue.contains("let x = 1") })
        let jump = element("pane.\(card).jump"), dirty = element("pane.\(card).dirty")
        XCTAssertEqual(jump.stringValue, "oriel-e2e-file › main.swift")
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

        editor.click()
        app.typeKey("f", modifierFlags: .command)
        let search = element("file.\(card).page").textFields.firstMatch
        XCTAssertTrue(search.exists(within: 2) && hasKeyboard(search))
        app.typeKey(.escape, modifierFlags: [])

        try await keysStayInTheEditor(card, shell: left)
    }

    /// ⇧⌘← (Move Tab Left) selects the line in the editor; ⌘[ (Select Previous Pane) reaches the app.
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
    }

    /// A change on disk while dirty: the toast; Keep Mine keeps the edit and the next ⌘S writes it over the change;
    /// Reload takes the disk's text and clears the dot.
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

        app.typeText("again")
        XCTAssertTrue(dirty.exists(within: 3))
        try await send("printf 'let w = 4\\n' >\(file)\r", to: shell)
        XCTAssertTrue(toast.exists(within: 5))
        element("pane.\(card).toast.other").click()
        XCTAssertTrue(until(3) { editor.stringValue.hasPrefix("let w = 4") })
        XCTAssertTrue(dirty.vanishes(within: 3))
    }

    /// An image at Fit, Actual Size and zoomed in; a PDF's page `n of m`, which follows a scroll; the info view of
    /// another file, with no zoom.
    func testAPreviewCardShowsImagesPDFsAndOtherFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("preview")
        try await waitForPrompt(left)
        let folder = "/tmp/oriel-e2e-preview"
        try await send("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && sips -s format png -z 900 1200 "
            + "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns "
            + "--out icon.png >/dev/null && seq 1 150 >lines.txt && cupsfilter lines.txt >lines.pdf 2>/dev/null "
            + "&& head -c 3000 /dev/urandom >notes.bin && clear && echo ready-$((6*7))\r", to: left)
        try await waitFor(left) { $0.contains("ready-42") }
        addTeardownBlock { [one] in _ = try? await Self.call(
            one,
            "pane.send_text",
            ["pane_id": left, "text": "rm -rf \(folder)\r"],
        ) }
        element("tab.\(tab)").click()
        let card = try await split(left)
        let label = "oriel:preview#e2eprev \(folder)/"
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": label + "icon.png"])
        let page = element("preview.\(card).page"), image = page.images["icon.png"]
        XCTAssertTrue(image.exists(within: 10))
        XCTAssertTrue(until(3) { image.frame.width > 100 && image.frame.width < page.frame.width })
        element("pane.\(card).zoom.actual").click()
        XCTAssertTrue(until(3) { abs(image.frame.width - 1200) < 2 })
        element("pane.\(card).zoom.fit").click()
        XCTAssertTrue(until(3) { image.frame.width < page.frame.width })
        let fit = image.frame.width
        element("pane.\(card).zoom.in").click()
        XCTAssertTrue(until(3) { abs(image.frame.width - fit * 1.25) < 2 })
        XCTAssertFalse(element("pane.\(card).page").exists)
        keepScreenshot("preview card, image")

        try await Self.call(one, "pane.rename", ["pane_id": card, "label": label + "lines.pdf"])
        let pages = element("pane.\(card).page")
        XCTAssertTrue(until(10) { pages.stringValue.hasPrefix("1 of ") && pages.stringValue != "1 of 1" })
        let first = pages.stringValue
        page.scroll(byDeltaX: 0, deltaY: -3000)
        XCTAssertTrue(until(3) { pages.stringValue != first })
        keepScreenshot("preview card, PDF")

        try await Self.call(one, "pane.rename", ["pane_id": card, "label": label + "notes.bin"])
        let name = page.staticTexts.matching(NSPredicate(format: "value == %@", "notes.bin")).firstMatch
        XCTAssertTrue(name.exists(within: 10))
        XCTAssertFalse(element("pane.\(card).zoom.fit").exists)
        XCTAssertFalse(pages.exists)
    }
}
