import XCTest

/// `ovvi notify`, `ovvi agent`, `ovvi chat`, `ovvi view` and `ovvi balance` (agent-control/cli): a notification on
/// the Mac, an agent in a new pane, Relaunch with Chat, the Chat | TUI switch and Balance Splits, asked from a pane.
extension OvviUITests {
    /// A split beside the asking pane, then a tab right after its tab: each shell gets Claude Code's line with Ovvi's
    /// flags, the answer comes once it is typed, and the keyboard and the selected tab stay. CI only past the errors: a
    /// new pane's shell has no stand-in and runs the real `claude` when there is one, and CI has none.
    func testAgentStartsAnAgentWithChatBesideThePane() async throws {
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let (tab, pane) = try await newTab("agent")
        element("tab.\(tab)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        try await waitForPrompt(pane)
        try await expectOpen("w2")
        let ovvi = Self.ovviCommand
        try await run("\(ovvi) agent nobody --beside w9:p9", in: pane, "nobody", 1,
                      "ovvi: no agent nobody; there are claude")
        try await run("\(ovvi) agent claude --replace w9:p9", in: pane, "replace", 2, "ovvi: --replace takes")
        try await send("command -v claude >/dev/null; echo installed-$((6*7))-$?\r", to: pane)
        try await waitFor(pane) { $0.contains("\ninstalled-42-") }
        if try await read(pane).contains("\ninstalled-42-0") {
            throw XCTSkip("this Mac has claude, which the new pane would start")
        }

        for (place, marker) in [("", "split"), (" --tab", "tab")] {
            try await send("clear\r", to: pane)
            try await run("\(ovvi) --json agent claude\(place)", in: pane, marker, 0, #"{"agent":"claude""#)
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

    /// One notification per pane every 10 s, none while Settings ▸ Agents ▸ When an agent sends one is off. A banner
    /// cannot be read or clicked from a test: only the answers are.
    func testNotifyIsOncePerPaneEveryTenSecondsAndFollowsItsSwitch() async throws {
        let (_, pane) = try await newTab("notify")
        try await waitForPrompt(pane)
        try await expectOpen("w2")
        let ovvi = Self.ovviCommand
        try await run("\(ovvi) notify", in: pane, "usage", 2, "ovvi: missing <title>")
        try await run("\(ovvi) notify Done --pane w9:p9", in: pane, "none", 1, "ovvi: pane w9:p9 is not in")
        // macOS may not allow Ovvi's notifications (CI): the first one's answer can be either.
        try await run("\(ovvi) notify 'Tests pass' '42 passed' >/dev/null 2>&1; \(ovvi) notify Again --pane w1:p1",
                      in: pane, "again", 1, "ovvi: one notification per pane every 10 s")

        relaunch(one, ["-notifyFromAgents", "NO"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        try await run("\(ovvi) notify Done", in: pane, "off", 0, "notified: false")
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
        try await send("\(herdr) report-agent --source ovvi-e2e --agent claude --state working \"$HERDR_PANE_ID\"; "
            + "\(herdr) report-agent-session \"$HERDR_PANE_ID\" --source herdr:claude --agent claude "
            + "--agent-session-id \(UUID().uuidString.lowercased())\r", to: busy)
        XCTAssertTrue(element("pane.\(busy).enable-chat").exists(within: 10))
        XCTAssertTrue(element("pane.\(agent).enable-chat").exists(within: 10))
        try await waitForPrompt(asking)

        let ovvi = "\(Self.ovviCommand) --timeout 30"
        try await run("\(ovvi) chat $HERDR_PANE_ID", in: asking, "self", 1, "ovvi: pane \(asking) is the asking one")
        try await run("\(ovvi) chat w1:p1", in: asking, "plain", 1, "ovvi: pane w1:p1 runs no agent")
        try await run("\(ovvi) chat \(busy)", in: asking, "busy", 1, "ovvi: Claude Code in pane \(busy) is working")
        try await run("\(ovvi) chat \(agent)", in: asking, "chat", 0, "agent: claude")
        XCTAssertTrue(element("chat.\(agent).composer").exists(within: 20))
        XCTAssertFalse(element("pane.\(agent).enable-chat").exists)
    }

    /// The card's Chat | TUI switch from a pane, which `card` reports; a pane with no chat view and a third word are
    /// refused.
    func testViewSwitchesAChatAgentsCard() async throws {
        let (_, agent) = try await startChat(chat: false)
        XCTAssertTrue(element("pane.\(agent).view.tui").exists(within: 15))
        let asking = try await split(agent)
        try await waitForPrompt(asking)
        let ovvi = Self.ovviCommand, composer = element("chat.\(agent).composer")
        try await run("\(ovvi) view \(agent) chat", in: asking, "chat", 0, "view: chat")
        XCTAssertTrue(composer.exists(within: 5))
        try await run("\(ovvi) --json card \(agent) | grep -o '\"view\":\"[a-z]*\"'", in: asking, "card", 0,
                      #""view":"chat""#)
        try await run("\(ovvi) view \(agent) tui", in: asking, "tui", 0, "view: tui")
        XCTAssertTrue(composer.vanishes(within: 5))
        XCTAssertTrue(element("pane.\(agent).view.tui").isSelected)
        // Wrapped at the pane's width (about 45 columns on CI).
        try await run("\(ovvi) view \(asking) chat", in: asking, "plain", 1, "ovvi: pane \(asking) runs no agent")
        try await run("\(ovvi) view \(agent) both", in: asking, "both", 2, "ovvi: both is not chat or tui")
    }

    /// Balance Splits from a pane: its own tab by default, another pane's tab by name.
    func testBalanceEvensOutAPanesTab() async throws {
        let (tab, pane) = try await newTab("balance")
        try await split(pane)
        try await waitForPrompt(pane)
        let (otherTab, far) = try await newTab("balance-other")
        try await split(far)
        try await expectOpen("w2")
        let ovvi = Self.ovviCommand
        for (marker, target, ratioTab) in [("own", "", tab), ("other", " \(far)", otherTab)] {
            try await Self.call(one, "layout.set_split_ratio", ["tab_id": ratioTab, "path": [Bool](), "ratio": 0.3])
            try await run("\(ovvi) balance\(target)", in: pane, marker, 0, "tab: \(ratioTab)")
            let ratio = try await root(ratioTab)["ratio"] as? Double ?? 0
            XCTAssertEqual(ratio, 0.5, accuracy: 0.01, "\(ratioTab) after balance\(target)")
        }
        try await run("\(ovvi) balance w9:p9", in: pane, "none", 1, "ovvi: pane w9:p9 is not in")
    }
}
