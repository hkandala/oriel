import XCTest

/// The file and preview cards (phase 43, track A): a file's text that edits, saves and follows the disk; images, PDFs
/// and other files in the preview.
extension OrielUITests {
    /// The text with colors' tree behind the jump bar's symbol; an edit shows the dirty dot and ⌘S writes it; a change
    /// on disk reloads a clean card and asks on a dirty one; ⌘F shows the find bar; the overview's tile is a file.
    func testFileCardEditsSavesAndFollowsTheDisk() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("file")
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
        let toast = element("pane.\(pane).toast")
        XCTAssertTrue(toast.has(\.stringValue, "main.swift changed on disk.", within: 5))
        element("pane.\(pane).toast.other").click()
        XCTAssertTrue(text.has(\.stringValue, "let disk = 2\n", within: 3))
        XCTAssertTrue(dirty.vanishes(within: 3))
        try await keepMineFindAndOverview(pane, shell: shell, folder: folder)
    }

    private func keepMineFindAndOverview(_ pane: String, shell: String, folder: String) async throws {
        let text = element("file.\(pane).text")
        // Keep Mine keeps the edit, and the next ⌘S writes it over the disk's.
        text.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeText("// mine")
        try await run("printf 'let again = 3\\n' >\(folder)/main.swift", in: shell)
        XCTAssertTrue(element("pane.\(pane).toast").exists(within: 5))
        element("pane.\(pane).toast.main").click()
        XCTAssertTrue(text.stringValue.hasSuffix("// mine"))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(pane).dirty").vanishes(within: 5))
        try await run("grep -q '^// mine$' \(folder)/main.swift", in: shell)

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(element("file.\(pane).card").searchFields.firstMatch.exists(within: 3))
        keepScreenshot("file card, find")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview.card.\(pane)").has(\.stringValue, "file", within: 5))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// An image with zoom that reloads from disk, a PDF with its page, another file's info view.
    func testPreviewCardShowsImagesPDFsAndOtherFiles() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (_, shell) = try await newTab("preview")
        let folder = "/tmp/oriel-e2e-preview"
        let icon = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns"
        try await run("""
        rm -rf \(folder) && mkdir \(folder) && cd \(folder) && sips -s format png \(icon) --out icon.png >/dev/null && \
        sips -s format pdf icon.png --out doc.pdf >/dev/null && printf 'zip' >data.zip
        """, in: shell)

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
        // A smaller image on disk: shown at its actual size.
        try await run("sips -z 64 64 \(folder)/icon.png >/dev/null", in: shell)
        XCTAssertTrue(until(5) { abs(picture.frame.width - 64) < 2 }, "\(picture.frame.width)")

        let pdf = try await openPlugin("preview", "\(folder)/doc.pdf")
        XCTAssertTrue(element("preview.\(pdf).pdf").exists(within: 5))
        XCTAssertTrue(element("pane.\(pdf).page").has(\.stringValue, "1 of 1", within: 3))
        XCTAssertTrue(element("pane.\(pdf).zoom.fit").exists)

        let other = try await openPlugin("preview", "\(folder)/data.zip")
        let info = element("preview.\(other).info")
        XCTAssertTrue(info.exists(within: 5))
        XCTAssertTrue(info.label.contains("data.zip"), info.label)
        XCTAssertFalse(element("pane.\(other).zoom.fit").exists)
    }

    /// Runs the command in the shell pane and waits for it to succeed.
    private func run(_ command: String, in shell: String) async throws {
        try await waitForPrompt(shell)
        try await send("clear; \(command) && echo done-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("\ndone-42") || $0.hasPrefix("done-42") }
    }

    /// A tab with a plugin pane made as Oriel makes one (`layout.apply` with the label), selected: its pane.
    private func openPlugin(_ kind: String, _ path: String) async throws -> String {
        let iid = String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
        let reply = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": [
            "type": "pane", "cwd": "/tmp", "label": "oriel:\(kind)#\(iid) \(path)", "command": [
                "sh",
                "-c",
                "cat",
                "sh",
            ],
        ]])
        let layout = reply["layout"] as? [String: Any]
        let tab: String = try field(layout?["tab_id"], "layout's tab")
        let pane: String = try field((layout?["root"] as? [String: Any])?["pane_id"], "layout's pane")
        closeAfter("tab", tab)
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.has(\.isHittable, true, within: 3))
        capsule.click()
        XCTAssertTrue(element("\(kind).\(pane).card").exists(within: 5))
        return pane
    }
}
