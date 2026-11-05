import XCTest

/// pi's chat view with its stand-in (`scripts/pi-stand-in.py`; CI has no pi), started by the chooser with Ovvi's
/// flags: it needs the pi-ovvi file the app wrote first, writes pi-ovvi's state lines and a session file in pi's
/// format, and reports its state to herdr.
extension OvviUITests {
    /// Sends, the live terminal during a dialog, a message sent while it works, stops, and `/tree` moving the branch,
    /// on This Mac.
    func testPiChatSendsWaitsStopsAndFollowsTheTree() async throws {
        let pane = try await startChat(agent: 2).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))

        // An extension dialog: the live terminal until it closes.
        try await say("wait", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertFalse(element("chat.\(pane).composer").exists)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        // Sent while it works, pi takes it after the running tool: no "Not sent" meanwhile.
        try await say("slow", in: pane)
        app.typeText("later\r")
        XCTAssertFalse(element("chat.\(pane).not-sent").exists(within: 7))
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists)
        stop.click()
        XCTAssertTrue(row(pane, "user", "later").exists(within: 5))
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        // /tree in the terminal back before the last message: the chat shows that branch, and the next turn grows on
        // it.
        app.typeText("/tree\r")
        XCTAssertTrue(element("chat.\(pane).composer").vanishes(within: 3))
        // The app types it after the composer goes: an Enter before it reached pi first, alone.
        try await waitFor(pane) { $0.contains("/tree") }
        try await send("\r", to: pane)
        try await waitFor(pane) { $0.contains("Navigated to selected point") }
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(row(pane, "user", "later").vanishes(within: 5))
        XCTAssertTrue(row(pane, "user", "slow").exists)
        try await say("again", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **again**").exists(within: 5))
        XCTAssertFalse(row(pane, "user", "later").exists)
    }

    /// An opened run lists every tool call in order, as pi writes them: read, write, edit, grep, find, ls, bash,
    /// codemode with the read its script made, and agent_start.
    func testAPiRunListsEveryKindOfTool() async throws {
        let pane = try await startChat(agent: 2).pane
        try await say("tools", in: pane)
        XCTAssertTrue(row(pane, "reply", "All tools.").exists(within: 5))
        let stack = element("chat.\(pane).stack")
        XCTAssertEqual(stack.label, "Read 2 files, searched 2 patterns, ran 2 commands, +4 more")
        stack.click()
        let tools = app.descendants(matching: .any).matching(identifier: "chat.\(pane).tool")
        XCTAssertTrue(until(2) { tools.count == 10 }, "\(tools.count)")
        keepScreenshot("every tool")
        XCTAssertEqual(tools.allElementsBoundByIndex.map(\.label), [
            "read, a.txt, 1 line", "write, b.txt, ok", "edit, b.txt, +1 -1", "grep, needle, ok", "find, *.txt, ok",
            "ls, ., ok", "bash, echo hi, ok", "codemode, await tools.read({path: 'c.txt'}), ok", "read, c.txt",
            "agent_start, helper, ok",
        ])
    }

    /// The same chat on a remote machine: the extension written there, the state file and the transcript over the
    /// relay.
    func testPiChatOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        let pane = try await startChat(["-machines", Self.keyHost, "-machine", "e2e-key"], agent: 2).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("wait", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))
    }
}
