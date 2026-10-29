import XCTest

/// The chat view with Codex's stand-in (`scripts/codex-stand-in.py`; CI has no Codex), started by the chooser with
/// Oriel's flags: it checks the hook's trust hash as Codex does, runs the hook at the first prompt, writes a rollout in
/// Codex's format, reports its state to herdr and draws Codex's input box above its status row.
extension OrielUITests {
    /// Sends, stops, the live terminal for a picker herdr calls idle and for an approval, the chat again after a
    /// relaunch, and a new session, on This Mac.
    func testACodexChatSendsStopsAndShowsTheTerminalWhileItWaits() async throws {
        let (tab, pane) = try await startChat(agent: 1)
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        // At Steps the turn's quiet line opens to its calls.
        XCTAssertTrue(element("chat.\(pane).stack").label.contains(" · 1 command"))

        // Stop sends Esc while it works.
        try await say("slow", in: pane)
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        // A picker: herdr says idle, the screen has no input box: the terminal, with the keyboard, until Esc.
        try await say("model", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertFalse(element("chat.\(pane).composer").exists)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 3))

        // An approval: herdr says blocked.
        try await say("wait", in: pane)
        XCTAssertTrue(drawer.exists(within: 5))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        // No state kept in the app: the marker comes back from pane.process_info.
        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 10))

        // A new session (`/new`, then a message): its rollout is the history, and the old rows go.
        try await say("new", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **new**").exists(within: 5))
        XCTAssertFalse(row(pane, "reply", "Allowed.").exists)
    }

    /// The same chat on a remote machine: the hook, the rollout and the screen over the relay.
    func testACodexChatOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        let pane = try await startChat(["-machines", Self.keyHost, "-machine", "e2e-key"], agent: 1).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("model", in: pane)
        XCTAssertTrue(element("chat.\(pane).drawer").exists(within: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("chat.\(pane).drawer").vanishes(within: 5))
    }
}
