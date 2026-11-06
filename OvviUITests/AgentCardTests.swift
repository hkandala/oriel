import XCTest

/// `ovvi open`, `reveal`, `card` and `shown` (agent-control/cli): cards an agent opens and points at, typed in a
/// pane, checked through herdr's labels and the window, which never moves without the user.
extension OvviUITests {
    /// A file's default plugin beside the asking pane, the same card again, an old label word, a browser below another
    /// pane, a Git card in a tab that is not selected (its notice's Show selects it), and a float; herdr's focus stays.
    func testOpenPutsCardsWithoutMovingTheView() async throws {
        relaunch(nil, Self.agentHold)
        let (tab, first) = try await newTab("cards")
        try await closeNew("tab", besides: tabIDs())
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let folder = try await cardsFolder(in: first)
        let focus = try await snapshot()["focused_pane_id"] as? String

        let file = try await open("./notes.md", from: first, "file", ["kind: explorer", "reused: false", "shown: true"])
        let label = try await paneLabel(file)
        XCTAssertTrue(label.hasPrefix("ovvi:explorer#") && label.hasSuffix(" \(folder)/notes.md"), label)
        XCTAssertTrue(element("pane.\(file)").exists(within: 3))
        XCTAssertLessThan(element("pane.\(first)").frame.maxX, element("pane.\(file)").frame.minX)
        let again = try await open("explorer notes.md", from: first, "again", ["reused: true"])
        XCTAssertEqual(again, file)
        try await run("clear; \(Self.ovviCommand) open files .", in: first, "word", 0, "kind: explorer")

        let below = try await open("http://127.0.0.1:65530 --beside \(file) --down", from: first, "down",
                                   ["kind: browser"])
        XCTAssertTrue(element("pane.\(below)").exists(within: 3))
        XCTAssertLessThan(element("pane.\(file)").frame.maxY, element("pane.\(below)").frame.minY)

        // Not selected: the notice's Show selects it. A tab after the asking one, so the place right after it is not
        // the end.
        let (spare, _) = try await createTab(in: "w2")
        closeAfter("tab", spare)
        try await send("clear; \(Self.ovviCommand) open git . --tab; echo tab-$((6*7))-$?\r", to: first)
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value CONTAINS 'opened Git ovvi-e2e-cards'"))
            .firstMatch.exists(within: 10))
        XCTAssertTrue(element("tab.\(tab)").isSelected)
        let unmoved = try await snapshot()["focused_pane_id"] as? String
        XCTAssertEqual(unmoved, focus)
        keepScreenshot("open notice")
        notice.buttons["notice.show"].click()
        try await waitFor(first) { $0.contains("tab-42-0") }
        let tabbed = try await answered(first)
        let opened: String = try await field(pane(tabbed)["tab_id"], "the Git card's tab")
        XCTAssertTrue(element("tab.\(opened)").has(\.isSelected, true, within: 3))
        try await expectBeside(opened, tab)

        let floated = try await open("explorer notes.md --float --new", from: first, "float", ["reused: false"])
        XCTAssertTrue(app.windows.containing(.any, identifier: "float.\(floated)").firstMatch.exists(within: 5))
        let still = try await snapshot()["focused_pane_id"] as? String
        XCTAssertEqual(still, focus)
        try await run("cd /tmp && rm -rf \(folder)", in: first, "clean", 0)
    }

    /// --replace on a card (not on a terminal), card for both, reveal's flash in view and its notice out of view, and
    /// shown.
    func testRevealCardShownAndReplace() async throws {
        relaunch(nil, Self.agentHold)
        let (tab, first) = try await newTab("reveal")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(first)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let folder = try await cardsFolder(in: first), ovvi = Self.ovviCommand

        let browser = try await open("browser ./one.html", from: first, "web", ["kind: browser"])
        let web = try await paneLabel(browser), iid = web.prefix { $0 != " " }.dropFirst("ovvi:browser".count)
        XCTAssertTrue(web.hasSuffix(" file://\(folder)/one.html"), web)
        // Another page in the same card, after the first loaded: Back returns.
        XCTAssertTrue(pageText("ovvi-cards-one").exists(within: 10))
        // A path's query and fragment stay the URL's.
        _ = try await open("browser './two.html?v=2#x' --replace \(browser)", from: first, "page", ["kind: browser"])
        XCTAssertTrue(pageText("ovvi-cards-two").exists(within: 10))
        let query = try await paneLabel(browser)
        XCTAssertTrue(query.hasSuffix(" file://\(folder)/two.html?v=2#x"), query)
        XCTAssertTrue(element("browser.\(browser).back").has(\.isEnabled, true, within: 5))
        try await run("\(ovvi) open git . --replace \(first)", in: first, "terminal", 1,
                      "ovvi: pane \(first) is no")
        _ = try await open("git . --replace \(browser)", from: first, "replace", ["kind: git"])
        let label = try await paneLabel(browser)
        XCTAssertEqual(label, "ovvi:git\(iid) /private\(folder)/")
        try await run("clear; \(ovvi) card \(browser)", in: first, "card", 0, "kind: git", "shown: true")
        try await run("clear; \(ovvi) card \(first)", in: first, "terminal-card", 0, "kind: terminal")
        try await run("clear; \(ovvi) shown", in: first, "shown", 0, "windows: 1")
        let shown = try await read(first).split(separator: "\n").first { $0.hasPrefix("shown: ") } ?? ""
        XCTAssertTrue(shown.contains(first) && shown.contains(browser), String(shown))

        try await run("clear; \(ovvi) reveal \(browser)", in: first, "flash", 0, "shown: true")
        XCTAssertTrue(element("pane.\(browser).flash").exists(within: 3))

        // Out of view: the notice, whose Show brings the tab back.
        let other = try await field(tabIDs().first { $0.hasPrefix("w2:") && $0 != tab }, "another tab of w2") as String
        element("tab.\(other)").click()
        XCTAssertTrue(element("tab.\(other)").has(\.isSelected, true, within: 3))
        try await run("clear; \(ovvi) reveal \(browser)", in: first, "notice", 0, "shown: false")
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts.matching(NSPredicate(format: "value CONTAINS 'points to ovvi-e2e-cards'"))
            .firstMatch.exists(within: 3))
        notice.buttons["notice.show"].click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 3))
        try await run("cd /tmp && rm -rf \(folder)", in: first, "clean", 0)
    }

    /// An agent's notices and flashes last 30 s: a query on CI can take seconds.
    static let agentHold = ["-agentHoldSeconds", "30"]

    /// A git repository with a file and two pages, the pane's shell in it; its path as the shell has it.
    private func cardsFolder(in pane: String) async throws -> String {
        let folder = "/tmp/ovvi-e2e-cards"
        try await run("rm -rf \(folder) && mkdir \(folder) && cd \(folder) && git init -q && echo hi >notes.md "
            + "&& echo '<p>ovvi-cards-one</p>' >one.html && echo '<p>ovvi-cards-two</p>' >two.html",
            in: pane, "folder", 0)
        return folder
    }

    /// `ovvi open ‹args›` from the pane, which exits 0 with these lines: the card's pane.
    private func open(_ args: String, from pane: String, _ marker: String, _ lines: [String]) async throws -> String {
        try await run("clear; \(Self.ovviCommand) open \(args)", in: pane, marker, 0)
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
