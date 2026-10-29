import XCTest

/// The file and preview cards (phase 43, track A): a file's text that edits, saves and follows the disk; images, PDFs,
/// audio and other files in the preview.
extension OrielUITests {
    /// The tree behind the jump bar's symbol; an edit shows the dirty dot and ⌘S writes it; a change on disk reloads a
    /// clean card and asks on a dirty one; a save over a changed disk asks; undo, find, and the overview's tile.
    func testFileCardEditsSavesAndFollowsTheDisk() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, shell) = try await newTab("file")
        let folder = "/tmp/oriel-e2e-file"
        let swift = #"struct Box {\n    func open() {}\n}\n"#
        try await run("rm -rf \(folder) && mkdir \(folder) && printf '\(swift)' >\(folder)/main.swift", in: shell)
        let pane = try await openPlugin("file", "\(folder)/main.swift")
        let text = element("file.\(pane).text"), dirty = element("pane.\(pane).dirty")
        XCTAssertTrue(text.has(\.stringValue, "struct Box {\n    func open() {}\n}\n", within: 5))

        // The caret's declaration, from the tree: the struct at the top, the function inside it.
        text.click()
        app.typeKey(.upArrow, modifierFlags: .command)
        let jump = element("pane.\(pane).jump")
        XCTAssertTrue(jump.has(\.stringValue, "oriel-e2e-file › main.swift › Box", within: 3))
        app.typeKey(.downArrow, modifierFlags: [])
        for _ in 0 ..< 6 {
            app.typeKey(.rightArrow, modifierFlags: [])
        }
        XCTAssertTrue(jump.has(\.stringValue, "oriel-e2e-file › main.swift › open", within: 3))

        XCTAssertFalse(dirty.exists)
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("// edited")
        XCTAssertTrue(dirty.exists(within: 3))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 5))
        try await run("grep -q '^// edited$' \(folder)/main.swift", in: shell)

        // Clean: the disk's text replaces it.
        try await run("printf 'let changed = 1\\n' >\(folder)/main.swift", in: shell)
        XCTAssertTrue(text.has(\.stringValue, "let changed = 1\n", within: 5))

        // Dirty: the toast asks; Reload takes the disk's.
        text.click()
        app.typeText("x")
        XCTAssertTrue(dirty.exists(within: 3))
        try await run("printf 'let disk = 2\\n' >\(folder)/main.swift", in: shell)
        XCTAssertTrue(element("pane.\(pane).toast").has(\.stringValue, "main.swift changed on disk.", within: 5))
        element("pane.\(pane).toast.other").click()
        XCTAssertTrue(text.has(\.stringValue, "let disk = 2\n", within: 3))
        XCTAssertTrue(dirty.vanishes(within: 3))

        try await keepMineAndOverwrite(pane, shell: shell, folder: folder)
        try await undoFindAndOverview(pane)
        try await crlfStays(shell, folder: folder)

        // A terminal's ⌘F is still its own find bar.
        element("tab.\(tab)").click()
        element("terminal.\(shell)").click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard("find.field"))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Keep Mine keeps the edit for the next ⌘S; a ⌘S over a disk changed since asks, and Overwrite writes.
    private func keepMineAndOverwrite(_ pane: String, shell: String, folder: String) async throws {
        let text = element("file.\(pane).text"), dirty = element("pane.\(pane).dirty")
        let toast = element("pane.\(pane).toast")
        text.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("// mine")
        try await run("printf 'let again = 3\\n' >\(folder)/main.swift", in: shell)
        XCTAssertTrue(toast.exists(within: 5))
        element("pane.\(pane).toast.main").click()
        XCTAssertTrue(text.stringValue.hasSuffix("// mine"))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(dirty.vanishes(within: 5))
        try await run("grep -q '^// mine$' \(folder)/main.swift", in: shell)

        text.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText(" over")
        try await run("printf 'let other = 4\\n' >\(folder)/main.swift", in: shell)
        XCTAssertTrue(toast.exists(within: 5))
        // The toast's question is left; the save finds the disk changed.
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(toast.has(\.stringValue, "main.swift changed on disk since you opened it.", within: 5))
        XCTAssertTrue(dirty.exists)
        element("pane.\(pane).toast.other").click()
        XCTAssertTrue(dirty.vanishes(within: 5))
        try await run("grep -q '^// mine over$' \(folder)/main.swift", in: shell)
    }

    /// ⌘Z takes an edit back; ⌘F shows the find bar; the overview borrows the text view, and the card has it back.
    private func undoFindAndOverview(_ pane: String) async throws {
        let text = element("file.\(pane).text")
        let before = text.stringValue
        text.click()
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeText("q")
        XCTAssertTrue(text.has(\.stringValue, "q" + before, within: 2))
        XCTAssertTrue(element("pane.\(pane).dirty").exists(within: 3))
        // Back to the disk's text: not dirty.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(text.has(\.stringValue, before, within: 2))
        XCTAssertTrue(element("pane.\(pane).dirty").vanishes(within: 3))

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(element("file.\(pane).card").searchFields.firstMatch.exists(within: 3))
        keepScreenshot("file card, find")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(pane)").has(\.stringValue, "file", within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(text.has(\.isHittable, true, within: 5))
        text.click()
        app.typeText("w")
        XCTAssertTrue(element("pane.\(pane).dirty").exists(within: 3))
    }

    /// A CRLF file keeps CRLF after a Return and a save.
    private func crlfStays(_ shell: String, folder: String) async throws {
        try await run("printf 'a\\r\\nb\\r\\n' >\(folder)/crlf.txt", in: shell)
        let pane = try await openPlugin("file", "\(folder)/crlf.txt")
        let text = element("file.\(pane).text")
        XCTAssertTrue(text.has(\.stringValue, "a\r\nb\r\n", within: 5))
        text.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        app.typeText("c")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(pane).dirty").vanishes(within: 5))
        try await run("[ \"$(tr -cd '\\r' <\(folder)/crlf.txt | wc -c)\" -eq 3 ]", in: shell)
    }

    /// An image with zoom that reloads from disk, a PDF's pages, audio, another file's info view; a click gives a
    /// preview the keyboard.
    func testPreviewCardShowsImagesPDFsAudioAndOtherFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("preview")
        let folder = "/tmp/oriel-e2e-preview"
        let icon = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns"
        // A WAV of silence: its header, then 2048 bytes.
        let wav = #"RIFF\x24\x08\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00"#
            + #"\x01\x00\x08\x00data\x00\x08\x00\x00"#
        try await run("""
        rm -rf \(folder) && mkdir \(folder) && cd \(folder) && sips -s format png \(icon) --out icon.png >/dev/null && \
        seq 1 150 >n.txt && cupsfilter n.txt >three.pdf 2>/dev/null && printf 'zip' >data.zip && \
        printf '\(wav)' >a.wav && head -c 2048 /dev/zero >>a.wav
        """, in: shell)

        try await imageZoomsAndReloads(folder, shell: shell)

        let pdf = try await openPlugin("preview", "\(folder)/three.pdf")
        let pages = element("preview.\(pdf).pdf"), page = element("pane.\(pdf).page")
        XCTAssertTrue(page.has(\.stringValue, "1 of 3", within: 5))
        // Down, whichever way the wheel goes here.
        pages.scroll(byDeltaX: 0, deltaY: -3000)
        if !until(1, { page.stringValue != "1 of 3" }) {
            pages.scroll(byDeltaX: 0, deltaY: 3000)
        }
        XCTAssertTrue(until(2) { page.stringValue != "1 of 3" }, page.stringValue)
        try await clickTakesTheKeyboard(pdf, pages)

        let audio = try await openPlugin("preview", "\(folder)/a.wav")
        XCTAssertTrue(element("preview.\(audio).player").exists(within: 5))
        XCTAssertFalse(element("pane.\(audio).zoom.fit").exists)

        let other = try await openPlugin("preview", "\(folder)/data.zip")
        let info = element("preview.\(other).info")
        XCTAssertTrue(info.exists(within: 5))
        XCTAssertTrue(info.label.contains("data.zip"), info.label)
        try await clickTakesTheKeyboard(other, info)
    }

    /// A click on the content gives it the keyboard from the terminal beside it: ⌘W closes the preview.
    private func clickTakesTheKeyboard(_ pane: String, _ content: XCUIElement) async throws {
        let terminal = try await split(pane)
        element("terminal.\(terminal)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(terminal)"))
        content.click()
        app.typeKey("w", modifierFlags: .command)
        try await expect("\(pane) closed") {
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            let ids = panes.compactMap { $0["pane_id"] as? String }
            return !ids.contains(pane) && ids.contains(terminal)
        }
        let tab: String = try await field(self.pane(terminal)["tab_id"], "\(terminal)'s tab")
        _ = try await Self.call(one, "tab.close", ["tab_id": tab])
    }

    /// Actual Size, then bigger; a smaller image on disk replaces it.
    private func imageZoomsAndReloads(_ folder: String, shell: String) async throws {
        let image = try await openPlugin("preview", "\(folder)/icon.png")
        let picture = element("preview.\(image).image").images.firstMatch
        XCTAssertTrue(picture.exists(within: 5))
        XCTAssertEqual(element("pane.\(image).path").stringValue, "\(folder)/icon.png")
        element("pane.\(image).zoom.actual").click()
        XCTAssertTrue(until(2) { picture.frame.width > 0 })
        let actual = picture.frame.width
        element("pane.\(image).zoom.in").click()
        XCTAssertTrue(until(2) { picture.frame.width > actual * 1.2 }, "\(picture.frame.width) after \(actual)")
        keepScreenshot("preview card, image")
        try await run("sips -z 64 64 \(folder)/icon.png >/dev/null", in: shell)
        XCTAssertTrue(until(5) { picture.frame.width < actual / 4 }, "\(picture.frame.width) after \(actual)")
    }

    /// Runs the command in the shell pane and waits for it to succeed.
    private func run(_ command: String, in shell: String) async throws {
        try await waitForPrompt(shell)
        try await send("clear; \(command) && echo done-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("\ndone-42") || $0.hasPrefix("done-42") }
    }

    /// A tab with a plugin pane made as Oriel makes one (`layout.apply` with the label), selected: its pane.
    private func openPlugin(_ kind: String, _ path: String) async throws -> String {
        // One plugin tab at a time: CI's narrow tab bar clips a fourth capsule, and a click on it misses.
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        for tab in Set(panes.filter { ($0["label"] as? String)?.hasPrefix("oriel:") == true }
            .compactMap { $0["tab_id"] as? String }) where tab.hasPrefix("w2:")
        {
            _ = try? await Self.call(one, "tab.close", ["tab_id": tab])
        }
        let iid = String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": "oriel:\(kind)#\(iid) \(path)",
            "command": ["sh", "-c", "cat", "sh"],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        // The capsule at rest (it slides in), then its card.
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.has(\.isHittable, true, within: 3))
        var frame = CGRect.null
        XCTAssertTrue(until(3) {
            defer { frame = capsule.frame }
            return capsule.frame == frame
        })
        capsule.click()
        XCTAssertTrue(element("\(kind).\(pane).card").has(\.isHittable, true, within: 5))
        return pane
    }
}
