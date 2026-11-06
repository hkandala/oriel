import XCTest

/// The Agents view's Archived shelf (ui/window#archived): the closed sessions in the agents' stores of a fixture home
/// (`OvviUITests.archivedHome`), never the user's.
extension OvviUITests {
    /// Newest first with the title and folder, the agent menu, then Resume: the agent's resume line in a new workspace
    /// in the session's folder (no workspace holds it). The resume only past a check for Claude Code: the new pane's
    /// shell would start the real one.
    func testArchivedListsClosedSessionsFiltersAndResumes() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let id = UUID().uuidString.lowercased()
        // herdr names /tmp by its real path.
        let folder = "/private/tmp/ovvi-e2e-archived-cwd/\(id.prefix(8))"
        let (_, shell) = try await newTab("archived")
        try await waitForPrompt(shell)
        try await writeSessions(id, in: folder, shell)
        app.typeKey(".", modifierFlags: .command)
        addTeardownBlock { [app] in app.typeKey(".", modifierFlags: .command) }
        let shelf = element("agents.shelf.Archived")
        XCTAssertTrue(shelf.exists(within: 3))
        if shelf.value as? String == "collapsed" {
            shelf.click()
        }
        XCTAssertTrue(shelf.has(\.stringValue, "expanded", within: 2))
        let first = element("agents.archived.claude.\(id)"), second = element("agents.archived.pi.2026_\(id).jsonl")
        XCTAssertTrue(first.exists(within: 5))
        XCTAssertTrue(second.exists(within: 2))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertEqual(first.label, "Rename the CLI, \(folder)")
        XCTAssertEqual(second.label, "Trip notes, \(folder)")
        keepScreenshot("archived shelf")

        filters(first, second)
        pins(first, id, below: shelf)
        try await resumes(first, id, in: folder, shell)
    }

    /// The menu shows Pi's sessions only, then all again.
    private func filters(_ claude: XCUIElement, _ piRow: XCUIElement) {
        let menu = element("agents.archived.filter")
        menu.click()
        menu.menuItems["Pi"].click()
        XCTAssertTrue(claude.vanishes(within: 2))
        XCTAssertTrue(piRow.exists)
        XCTAssertEqual(menu.value as? String, "Pi")
        menu.click()
        menu.menuItems["All Agents"].click()
        XCTAssertTrue(claude.exists(within: 2))
    }

    /// Pinned, it leaves Archived for the top of the list, with Resume; unpinned, it comes back.
    private func pins(_ row: XCUIElement, _ id: String, below shelf: XCUIElement) {
        row.rightClick()
        app.menus.menuItems["Pin"].firstMatch.click()
        let pinned = element("agents.pinned.claude.\(id)")
        XCTAssertTrue(pinned.exists(within: 2))
        XCTAssertTrue(row.vanishes(within: 2))
        XCTAssertLessThan(pinned.frame.maxY, shelf.frame.minY)
        pinned.hover()
        XCTAssertTrue(element("agents.pinned.claude.\(id).resume").exists(within: 2))
        keepScreenshot("pinned closed session")
        element("agents.pinned.claude.\(id).pin").click()
        XCTAssertTrue(pinned.vanishes(within: 2))
        XCTAssertTrue(row.exists(within: 2))
    }

    /// A Claude Code session two hours old and a pi session two days old, in the folder, written by the shell (the
    /// test runner may not write to /tmp).
    private func writeSessions(_ id: String, in folder: String, _ shell: String) async throws {
        let home = Self.archivedHome
        let files = [
            (".claude/projects/x/\(id).jsonl", 2 * 3600.0, """
            {"type":"user","message":{"role":"user","content":"rename it"},"cwd":"\(folder)","sessionId":"\(id)"}
            {"type":"custom-title","customTitle":"Rename the CLI","sessionId":"\(id)"}
            """),
            (".pi/agent/sessions/--x--/2026_\(id).jsonl", 2 * 86400.0, """
            {"type":"session","version":3,"id":"\(id)","cwd":"\(folder)"}
            {"type":"message","id":"a","message":{"role":"user","content":[{"type":"text","text":"Trip notes"}]}}
            """),
        ]
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "yyyyMMddHHmm.ss"
        let writes = files.map { path, age, text in
            let file = "\(home)/\(path)", dir = (file as NSString).deletingLastPathComponent
            return "mkdir -p \(dir) && echo \(Data(text.utf8).base64EncodedString()) | base64 -d >\(file) && "
                + "touch -t \(time.string(from: Date(timeIntervalSinceNow: -age))) \(file)"
        }
        try await send("rm -rf \(home) /private/tmp/ovvi-e2e-archived-cwd && mkdir -p \(folder) && "
            + writes.joined(separator: " && ") + " && clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
    }

    /// A click on Claude Code's row types its resume line in a new workspace in the folder.
    private func resumes(_ row: XCUIElement, _ id: String, in folder: String, _ pane: String) async throws {
        try await send("command -v claude >/dev/null; echo installed-$((6*7))-$?\r", to: pane)
        try await waitFor(pane) { $0.contains("\ninstalled-42-") }
        if try await read(pane).contains("\ninstalled-42-0") {
            throw XCTSkip("this Mac has claude, which the resume would start")
        }
        let before = try await workspaceIDs()
        closeNew("workspace", besides: before)
        row.click()
        var resumed: String?
        try await expect("a new workspace in the folder") {
            let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
            resumed = panes.first { pane in
                !before.contains { pane["workspace_id"] as? String == $0 } && pane["cwd"] as? String == folder
            }?["pane_id"] as? String
            return resumed != nil
        }
        // Wrapped at the pane's width.
        try await waitFor(XCTUnwrap(resumed)) { $0.replacing("\n", with: "").contains("claude --resume \(id)") }
    }
}
