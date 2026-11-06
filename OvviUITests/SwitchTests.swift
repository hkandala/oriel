import XCTest

/// Tab and workspace switches never wait for a card (ui/window#switching-tabs): the tabs shown last stay made, so a
/// switch back to a chat, a long Markdown file or a Git diff draws in the key's own turn and shows the card as it was.
extension OvviUITests {
    /// A chat of long replies, a long Markdown file in File Explorer and a Git diff, each in its own tab. The chat
    /// builds only its newest rows (about two views of text, not 34 rows); after Show Earlier and a scroll, switches to
    /// the other tabs, to another workspace and back, and the overview's round trip show it with the same rows and the
    /// same messages at its top. The kept Markdown card still scrolls, and the reply box gives up the keyboard as its
    /// page leaves view. The switches' times are in the result bundle (`latency`).
    func testSwitchesKeepHeavyCardsAsTheyWere() async throws {
        let (chatTab, pane) = try await startChat(["-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        // 12 turns of 31 or 32 paragraphs each: about 50 rows, each reply 85 lines or more.
        app.typeText("many 12 30\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let chat = element("chat.\(pane)"), earlier = element("chat.\(pane).earlier")
        let kinds = ["user", "reply", "stack", "worked"].map { "chat.\(pane).\($0)" }
        let rows = { try self.nodes(of: chat).count { kinds.contains($0.identifier) } }
        // The last two replies hold 120 lines: 7 rows with the rows between them.
        XCTAssertLessThanOrEqual(try rows(), 10)

        let tabs = try await heavyTabs()
        // Each shown once, until its page drew.
        for (tab, kind) in zip(tabs, ["markdown", "git"]) {
            try await select(tab)
            let card = try await self.pane(of: tab)
            XCTAssertTrue(element("\(kind).\(card).page").exists(within: 30), tab)
        }
        try await select(chatTab)
        XCTAssertTrue(until(5) { last.exists && last.isHittable })

        // Up to Show Earlier, and its rows: the messages at the top once the scroll rests.
        for _ in 0 ..< 5 where !earlier.isHittable {
            chat.scroll(byDeltaX: 0, deltaY: 5000)
        }
        earlier.click()
        XCTAssertTrue(until(3) { (try? rows()) ?? 0 > 10 })
        var top: Set<String> = []
        XCTAssertTrue(until(3) {
            let seen = atTop(of: chat, pane)
            defer { top = seen }
            return !seen.isEmpty && seen == top
        })
        let built = try rows()

        // To each other tab and back, then to another workspace and back.
        for tab in tabs + [chatTab] {
            element("tab.\(tab)").click()
            XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3), tab)
        }
        element("workspace.w1").click()
        XCTAssertTrue(last.vanishes(within: 3))
        element("workspace.w2").click()
        let same = {
            XCTAssertTrue(until(3) { last.exists })
            XCTAssertEqual(try rows(), built)
            XCTAssertEqual(self.atTop(of: chat, pane), top)
        }
        try same()
        XCTAssertTrue(element("chat.\(pane).bottom").exists)
        // The overview's round trip.
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 5))
        try same()

        try await replyBoxLetsGo(pane, in: chatTab)
        try await scrolls(tabs[0])
    }

    /// The reply box has the keyboard; a tab whose card takes none (its pane floats) gets the keys, not the box.
    private func replyBoxLetsGo(_ pane: String, in chatTab: String) async throws {
        let (floatTab, floated) = try await createTab(in: "w2", label: "float")
        closeAfter("tab", floatTab)
        try await select(floatTab)
        XCTAssertTrue(element("terminal.\(floated)").exists(within: 3))
        _ = try float(floated)
        // The main window takes the keys again.
        element("workspace.w2").click()
        try await select(chatTab)
        let composer = element("chat.\(pane).composer")
        composer.click()
        XCTAssertTrue(hasKeyboard(composer))
        try await select(floatTab)
        XCTAssertTrue(element("pane.\(floated).show").exists(within: 3))
        app.typeText("blur")
        try await select(chatTab)
        XCTAssertTrue(composer.exists(within: 3))
        XCTAssertFalse(composer.stringValue.contains("blur"), composer.stringValue)
    }

    /// w2's tab, by its ⌘ number once the app has every tab: the row makes only the capsules in view, and it has more
    /// tabs than CI's window shows.
    private func select(_ tab: String) async throws {
        let tabs = try await (Self.call(one, "tab.list", ["workspace_id": "w2"])["tabs"] as? [[String: Any]] ?? [])
            .compactMap { $0["tab_id"] as? String }
        let index = try XCTUnwrap(tabs.firstIndex(of: tab))
        XCTAssertTrue(element("tabs.count").has(\.stringValue, "\(tabs.count)", within: 5))
        app.typeKey("\(index + 1)", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3), tab)
    }

    /// The kept Markdown card takes the wheel: its first heading scrolls out of view.
    private func scrolls(_ tab: String) async throws {
        try await select(tab)
        let markdown = try await element("markdown.\(pane(of: tab)).page")
        let heading = markdown.staticTexts.matching(NSPredicate(format: "value == 'Part 1'")).firstMatch
        XCTAssertTrue(until(5) { heading.exists && heading.frame.minY >= markdown.frame.minY })
        markdown.scroll(byDeltaX: 0, deltaY: -2000)
        // Above the card, or gone: WebKit leaves text far out of view out of the tree.
        XCTAssertTrue(until(3) { !heading.exists || heading.frame.maxY < markdown.frame.minY })
    }

    /// A tab in w2 with a Markdown file of 1000 sections in File Explorer, and one with a Git diff of 40 changed files,
    /// made by w1's shell in a subshell (the fixture pane keeps its folder); the folder goes after the test.
    func heavyTabs() async throws -> [String] {
        let folder = "/tmp/ovvi-e2e-switch"
        let markdown = "for i in $(seq 1000); do printf '## Part %s\\n\\nSome *text*, `code` and "
            + "[a link](https://ovvi.dev).\\n\\n' $i; done >big.md"
        let repo = "mkdir repo && cd repo && git init -q && for i in $(seq 40); do seq 300 >f$i.txt; done && "
            + "git add -A && git -c user.name=e2e -c user.email=e2e@ovvi.dev commit -qm one && "
            + "for i in $(seq 40); do seq 0 3 600 >f$i.txt; done"
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": "w1:p1", "text": "rm -rf \(folder)\r"])
        }
        try await send("(rm -rf \(folder) && mkdir \(folder) && cd \(folder) && \(markdown) && \(repo)); clear; "
            + "echo made-$((1+1))\r", to: "w1:p1")
        try await waitFor("w1:p1", times: 100) { $0.contains("made-2") }
        var tabs: [String] = []
        for (kind, arg) in [("explorer", "\(folder)/big.md"), ("git", "\(folder)/repo/ uncommitted")] {
            let root: [String: Any] = ["type": "pane", "cwd": folder, "label": "ovvi:\(kind)#e2esw\(tabs.count) \(arg)",
                                       "command": ["sh", "-c", "cat", "sh"]]
            let layout = try await Self.call(one, "layout.apply", ["workspace_id": "w2", "focus": false, "root": root])
            try tabs.append(field((layout["layout"] as? [String: Any])?["tab_id"], "tab"))
        }
        return tabs
    }
}
