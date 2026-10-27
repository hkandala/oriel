import XCTest

/// Right clicks, drops and a program's copy in a terminal.
extension OrielUITests {
    func testAProgramsCopyReachesTheClipboard() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await expectCopy(from: "w1:p1")
    }

    /// herdr gives a remote program's OSC 52 only to a client of its own, never to a terminal stream.
    func testAProgramsCopyOnARemoteMachineReachesTheClipboard() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await expectCopy(from: "w1:p1")
    }

    /// An OSC 52 write in the pane (what vim's "+y, pi's copy key and an agent's copy on select send) lands on the
    /// Mac's clipboard. It is sent again each second: the app's client of herdr may still be connecting.
    private func expectCopy(from pane: String) async throws {
        try await waitForPrompt(pane)
        // The user's clipboard, every type of it, back after the test.
        let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        addTeardownBlock {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types {
                    item.setData(data, forType: type)
                }
                return item
            })
        }
        NSPasteboard.general.clearContents()
        for _ in 0 ..< 10 where NSPasteboard.general.string(forType: .string) != "oriel-osc52-42" {
            try await send("printf '\\033]52;c;%s\\a' $(printf oriel-osc52-$((6*7)) | base64)\r", to: pane)
            try? await expect("the copy on the clipboard", times: 10) {
                NSPasteboard.general.string(forType: .string) == "oriel-osc52-42"
            }
        }
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "oriel-osc52-42")
    }

    /// A right click opens the card's menu, also in a mouse app, as herdr opens its pane menu; ⌥ sends it to the app.
    func testRightClickInATerminalOpensThePaneMenu() async throws {
        let (tab, first) = try await newTab("menu")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").has(\.isHittable, true, within: 3))
        try await waitForPrompt(first)

        element("terminal.\(first)").rightClick()
        let menu = app.windows.firstMatch.menuItems
        for item in ["Copy", "Select All", "Split Right", "Close Pane"] {
            XCTAssertTrue(menu[item].exists(within: 2), item)
        }
        keepScreenshot("terminal menu")
        menu["Split Right"].click()
        let second = try await poll("a second pane in \(tab)") { () async throws -> String? in
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            return panes.first { $0["tab_id"] as? String == tab && $0["pane_id"] as? String != first }?["pane_id"]
                as? String
        }
        try await waitForPrompt(second)

        // Paste goes into the clicked terminal, not the one with the keyboard.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let (pane, other) = focused.evaluate(with: element("terminal.\(first)")) ? (second, first) : (first, second)
        let terminal = element("terminal.\(pane)")
        let command = "echo oriel-$((6*4))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        terminal.rightClick()
        XCTAssertTrue(menu["Paste"].exists(within: 2))
        menu["Paste"].click()
        // pane.read wraps lines at the pane's width.
        try await waitFor(pane) { $0.replacing("\n", with: "").contains(command) }
        let elsewhere = try await read(other)
        XCTAssertFalse(elsewhere.replacing("\n", with: "").contains(command))

        // A program that reads clicks (SGR mouse mode) sees the ⌥-right click as a plain right press: button 2, not
        // 10 (Alt adds 8). Without ⌥ the menu opens over it.
        try await send("\u{15}clear; printf '\\033[?1000h\\033[?1006h'; cat -v\r", to: pane)
        try await expect("cat to run") { try await foreground(pane).contains("cat") }
        XCUIElement.perform(withKeyModifiers: .option) { terminal.rightClick() }
        try await waitFor(pane) { $0.contains("[<2;") }
        XCTAssertFalse(menu["Copy"].exists)
        terminal.rightClick()
        XCTAssertTrue(menu["Copy"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A dragged file pastes its shell-escaped path, as a drop on Ghostty (herdr's usual terminal) does. The drag comes
    /// from a window of the helper's: from Finder, now and then no drag started on CI.
    func testDroppingAFilePastesItsPath() async throws {
        let (tab, pane) = try await newTab("drop")
        element("tab.\(tab)").click()
        let terminal = element("terminal.\(pane)")
        XCTAssertTrue(terminal.has(\.isHittable, true, within: 3))
        try await waitForPrompt(pane)

        // From over the sidebar onto the card.
        let from = element("sidebar").frame, card = terminal.frame
        let points = "\(from.midX) \(from.midY) \(card.midX) \(card.midY)"
        let path = try await String(decoding: Self.post("\(one)/file-drag", Data(points.utf8)), as: UTF8.self)
        let folder = URL(filePath: path).deletingLastPathComponent().lastPathComponent
        try await waitFor(pane) { $0.replacing("\n", with: "").contains(#"\#(folder)/drop\ me\'s\ \(1\).txt"#) }
    }
}
