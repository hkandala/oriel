import XCTest

/// `oriel notify`, `oriel agent` and `oriel chat` (agent-control/cli): a notification on the Mac, an agent in a new
/// pane, and Relaunch with Chat, asked from a pane.
extension OrielUITests {
    /// A split beside the asking pane, then a tab after its tab: each shell gets Claude Code's line with Oriel's flags,
    /// the answer comes once it is typed, and the keyboard and the selected tab stay. CI only past the errors: a new
    /// pane's shell has no stand-in and runs the real `claude` when there is one, and CI has none.
    func testAgentStartsAnAgentWithChatBesideThePane() async throws {
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let (tab, pane) = try await newTab("agent")
        element("tab.\(tab)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        try await waitForPrompt(pane)
        try await expectOpen("w2")
        let oriel = Self.orielCommand
        try await run("\(oriel) agent nobody", in: pane, "nobody", 1, "oriel: no agent nobody; there are claude")
        try await run("\(oriel) agent claude --replace w1:p1", in: pane, "replace", 2, "oriel: --replace takes")
        try await send("command -v claude >/dev/null; echo installed-$((6*7))-$?\r", to: pane)
        try await waitFor(pane) { $0.contains("\ninstalled-42-") }
        if try await read(pane).contains("\ninstalled-42-0") {
            throw XCTSkip("this Mac has claude, which the new pane would start")
        }

        for (place, marker) in [("", "split"), (" --tab", "tab")] {
            try await send("clear\r", to: pane)
            try await run("\(oriel) --json agent claude\(place)", in: pane, marker, 0, #"{"agent":"claude""#)
            let text = try await read(pane)
            let id = try String(XCTUnwrap(text.firstMatch(of: /"pane":"(w\d+:p\d+)"/)?.1, text))
            let new = try await self.pane(id)["tab_id"] as? String
            XCTAssertEqual(new == tab, place.isEmpty, "\(id) in \(new ?? "no tab")")
            // Wrapped at the pane's width (about 45 columns on CI).
            try await waitFor(id) { $0.replacing("\n", with: "").contains("claude --session-id ") }
            XCTAssertTrue(element("tab.\(tab)").isSelected, marker)
            XCTAssertTrue(hasKeyboard("terminal.\(pane)"), marker)
        }
    }

    /// One notification per pane every 10 s, none while Notifications ▸ From Agents is off. A banner cannot be read or
    /// clicked from a test: only the answers are.
    func testNotifyIsOncePerPaneEveryTenSecondsAndFollowsItsSwitch() async throws {
        let (_, pane) = try await newTab("notify")
        try await waitForPrompt(pane)
        try await expectOpen("w2")
        let oriel = Self.orielCommand
        try await run("\(oriel) notify", in: pane, "usage", 2, "oriel: missing <title>")
        try await run("\(oriel) notify Done --pane w9:p9", in: pane, "none", 1, "oriel: pane w9:p9 is not in")
        // macOS may not allow Oriel's notifications (CI): the first one's answer can be either.
        try await run("\(oriel) notify 'Tests pass' '42 passed' >/dev/null 2>&1; \(oriel) notify Again --pane w1:p1",
                      in: pane, "again", 1, "oriel: one notification per pane every 10 s")

        relaunch(one, ["-notifyFromAgents", "NO"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        try await run("\(oriel) notify Done", in: pane, "off", 0, "notified: false")
    }

    /// Never on the asking pane, a pane with no agent, or an agent that works; an idle one starts again with the chat
    /// (Claude Code's stand-in, started by hand), and the command answers once its line is typed.
    func testChatRelaunchesAnIdleAgentOnly() async throws {
        let (_, agent) = try await startChat(chat: false, plain: true)
        let asking = try await split(agent)
        let busy = try await split(asking, "down")
        try await waitForPrompt(busy)
        // Reported working before its session: herdr takes no state report after the session.
        let herdr = #""$HERDR_BIN_PATH" --session "$HERDR_SESSION" pane"#
        try await send("\(herdr) report-agent --source oriel-e2e --agent claude --state working \"$HERDR_PANE_ID\"; "
            + "\(herdr) report-agent-session \"$HERDR_PANE_ID\" --source herdr:claude --agent claude "
            + "--agent-session-id \(UUID().uuidString.lowercased())\r", to: busy)
        XCTAssertTrue(element("pane.\(busy).enable-chat").exists(within: 10))
        XCTAssertTrue(element("pane.\(agent).enable-chat").exists(within: 10))
        try await waitForPrompt(asking)

        let oriel = "\(Self.orielCommand) --timeout 30"
        try await run("\(oriel) chat $HERDR_PANE_ID", in: asking, "self", 1, "oriel: pane \(asking) is the asking one")
        try await run("\(oriel) chat w1:p1", in: asking, "plain", 1, "oriel: pane w1:p1 runs no agent")
        try await run("\(oriel) chat \(busy)", in: asking, "busy", 1, "oriel: Claude Code in pane \(busy) is working")
        try await run("\(oriel) chat \(agent)", in: asking, "chat", 0, "agent: claude")
        XCTAssertTrue(element("chat.\(agent).composer").exists(within: 20))
        XCTAssertFalse(element("pane.\(agent).enable-chat").exists)
    }
}
