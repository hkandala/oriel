import XCTest

/// The Agents view's Archived shelf (ui/window#archived): the closed sessions in the agents' stores of a fixture home
/// (`OvviUITests.archivedHome`), never the user's.
extension OvviUITests {
    /// The home folder whose agents' stores the Archived shelf reads (`-archivedHome`).
    static let archivedHome = "/tmp/ovvi-e2e-archived"

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
        let shelf = openArchived()
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

    /// Many sessions: the open shelf builds only the rows in view, and reads an agent's next page (pi's 51st to 55th
    /// sessions, the oldest) once its end scrolls into view.
    func testArchivedReadsTheNextPageAtItsEnd() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (_, shell) = try await newTab("archived-pages")
        try await waitForPrompt(shell)
        let dir = "\(Self.archivedHome)/.pi/agent/sessions/--p--"
        let line = #"{"type":"session","version":3,"cwd":"/tmp"}"#
        let prompt = #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Page '$i'"}]}}"#
        let write = "f=\(dir)/page-$i.jsonl; printf '%s\\n' '\(line)' '\(prompt)' >$f; "
            + "touch -t $(date -v-${i}H +%Y%m%d%H%M.%S) $f"
        try await send("rm -rf \(Self.archivedHome) && mkdir -p \(dir) && for i in $(seq 1 55); do \(write); done && "
            + "clear && echo ready-$((6*7))\r", to: shell)
        try await waitFor(shell) { $0.contains("ready-42") }
        let shelf = openArchived()
        let first = element("agents.archived.pi.page-1.jsonl"), last = element("agents.archived.pi.page-55.jsonl")
        XCTAssertTrue(first.exists(within: 5))
        XCTAssertEqual(first.label, "Page 1, /tmp")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'agents.archived.pi.page-'"))
        XCTAssertLessThan(rows.count, 20, "the lazy shelf built every row")
        let inside = shelf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 100))
        XCTAssertTrue(until(20) {
            inside.scroll(byDeltaX: 0, deltaY: -2000)
            return last.exists
        }, "the 55th session never came")
    }

    /// Opens the Agents view and its Archived shelf, which shows all agents; back to the workspaces after the test.
    private func openArchived() -> XCUIElement {
        app.typeKey(".", modifierFlags: .command)
        addTeardownBlock { [app] in app.typeKey(".", modifierFlags: .command) }
        let shelf = element("agents.shelf.Archived")
        XCTAssertTrue(shelf.exists(within: 3))
        if shelf.value as? String == "collapsed" {
            shelf.click()
        }
        XCTAssertTrue(shelf.has(\.stringValue, "expanded", within: 2))
        // A run that stopped in the middle left another agent picked.
        let menu = element("agents.archived.filter")
        if menu.value as? String != "All Agents" {
            menu.click()
            menu.menuItems["All Agents"].click()
        }
        return shelf
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

    /// A click on Claude Code's row types its resume line in a new workspace in the folder. Not where the new pane's
    /// shell would start a real Claude Code (this Mac); CI's is the stand-in (`OvviUITests.agents`), which only exits.
    private func resumes(_ row: XCUIElement, _ id: String, in folder: String, _ pane: String) async throws {
        try await send(
            "case $(command -v claude) in \(Self.agents)/*) echo stand-$((6*7));; *) echo real-$((6*7));; "
                + "esac\r",
            to: pane,
        )
        try await waitFor(pane) { $0.contains("\nstand-42") || $0.contains("\nreal-42") }
        if try await read(pane).contains("\nreal-42") {
            throw XCTSkip("this Mac has claude, which the resume would start")
        }
        let before = try await workspaceIDs()
        closeNew("workspace", besides: before)
        row.click()
        // Out of Archived while it starts: a second click cannot start it twice.
        XCTAssertTrue(row.vanishes(within: 2))
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
        // The stand-in exits, or the shell has no claude: the session is closed again, back in Archived.
        XCTAssertTrue(row.exists(within: 15))
    }
}
