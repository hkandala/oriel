import XCTest

/// `oriel open`, `reveal`, `card` and `shown` (agent-control/cli): cards an agent opens and points at, typed in a
/// pane, checked through herdr's labels and the window, which never moves without the user.
extension OrielUITests {
    /// A file's default plugin beside the asking pane, the same card again, a browser below another pane, a Git card in
    /// a tab that is not selected (its notice's Show selects it), and a float.
    func testOpenPutsCardsWithoutMovingTheView() async throws {
        let (tab, first) = try await newTab("cards")
        try await closeNew("tab", besides: tabIDs())
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let folder = try await cardsFolder(in: first)

        let file = try await open("./notes.md", from: first, "file", ["kind: explorer", "reused: false", "shown: true"])
        let label = try await paneLabel(file)
        XCTAssertTrue(label.hasPrefix("oriel:explorer#") && label.hasSuffix(" \(folder)/notes.md"), label)
        XCTAssertTrue(element("pane.\(file)").exists(within: 3))
        XCTAssertLessThan(element("pane.\(first)").frame.maxX, element("pane.\(file)").frame.minX)
        let again = try await open("explorer notes.md", from: first, "again", ["reused: true"])
        XCTAssertEqual(again, file)

        let below = try await open("browser http://127.0.0.1:65530 --beside \(file) --down", from: first, "down",
                                   ["kind: browser"])
        XCTAssertTrue(element("pane.\(below)").exists(within: 3))
        XCTAssertLessThan(element("pane.\(file)").frame.maxY, element("pane.\(below)").frame.minY)

        // Not selected: the notice's Show selects it. Clicked before the answer is read, within the notice's 4 s.
        try await send("clear; \(Self.orielCommand) open git . --tab; echo tab-$((6*7))-$?\r", to: first)
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value CONTAINS 'opened Git oriel-e2e-cards'"))
            .firstMatch.exists(within: 10))
        XCTAssertTrue(element("tab.\(tab)").isSelected)
        keepScreenshot("open notice")
        notice.buttons["notice.show"].click()
        try await waitFor(first) { $0.contains("tab-42-0") }
        let tabbed = try await answered(first)
        let opened: String = try await field(pane(tabbed)["tab_id"], "the Git card's tab")
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 3))
        let index = try await order(of: opened), asking = try await order(of: tab)
        XCTAssertEqual(index, asking.map { $0 + 1 })

        let floated = try await open("explorer notes.md --float --new", from: first, "float", ["reused: false"])
        XCTAssertTrue(app.windows.containing(.any, identifier: "float.\(floated)").firstMatch.exists(within: 5))
        try await run("cd /tmp && rm -rf \(folder)", in: first, "clean", 0)
    }

    /// --replace on a card (not on a terminal), card for both, reveal's flash in view and its notice out of view, and
    /// shown.
    func testRevealCardShownAndReplace() async throws {
        let (tab, first) = try await newTab("reveal")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let folder = try await cardsFolder(in: first), oriel = Self.orielCommand

        let browser = try await open("http://127.0.0.1:65530", from: first, "web", ["kind: browser"])
        let iid = try await paneLabel(browser).prefix { $0 != " " }.dropFirst("oriel:browser".count)
        try await run("\(oriel) open git . --replace \(first)", in: first, "terminal", 1,
                      "oriel: pane \(first) is no browser or plugin card")
        _ = try await open("git . --replace \(browser)", from: first, "replace", ["kind: git"])
        let label = try await paneLabel(browser)
        XCTAssertEqual(label, "oriel:git\(iid) /private\(folder)/")
        try await run("clear; \(oriel) card \(browser)", in: first, "card", 0, "kind: git", "shown: true")
        try await run("clear; \(oriel) card \(first)", in: first, "terminal-card", 0, "kind: terminal")
        try await run("clear; \(oriel) shown", in: first, "shown", 0, "windows: 1")
        let shown = try await read(first).split(separator: "\n").first { $0.hasPrefix("shown: ") } ?? ""
        XCTAssertTrue(shown.contains(first) && shown.contains(browser), String(shown))

        try await send("\(oriel) reveal \(browser)\r", to: first)
        XCTAssertTrue(element("pane.\(browser).flash").exists(within: 5))

        // Out of view: the notice, whose Show brings the tab back.
        element("tab.w2:t1").click()
        XCTAssertTrue(element("tab.w2:t1").has(\.isSelected, true, within: 3))
        try await send("clear; \(oriel) reveal \(browser)\r", to: first)
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value CONTAINS 'points to oriel-e2e-cards'"))
            .firstMatch.exists(within: 10))
        notice.buttons["notice.show"].click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
        try await run("cd /tmp && rm -rf \(folder)", in: first, "clean", 0)
    }

    /// A git repository with one file, the pane's shell in it; its path as the shell has it.
    private func cardsFolder(in pane: String) async throws -> String {
        let folder = "/tmp/oriel-e2e-cards"
        try await run("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && git init -q && echo hi >notes.md",
                      in: pane, "folder", 0)
        return folder
    }

    /// `oriel open ‹args›` from the pane, which exits 0 with these lines: the card's pane.
    private func open(_ args: String, from pane: String, _ marker: String, _ lines: [String]) async throws -> String {
        try await run("clear; \(Self.orielCommand) open \(args)", in: pane, marker, 0)
        let text = try await read(pane)
        for line in lines {
            XCTAssertTrue(text.contains("\n\(line)"), "\(line) in:\n\(text)")
        }
        return try await answered(pane)
    }

    /// The pane an answer on the pane's screen names.
    private func answered(_ pane: String) async throws -> String {
        let text = try await read(pane)
        guard let match = text.firstMatch(of: /\npane: (\S+)/)
        else { throw Failed(description: "no pane in:\n\(text)") }
        return String(match.1)
    }
}
