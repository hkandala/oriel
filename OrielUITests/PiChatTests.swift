import XCTest

/// pi's chat view with its stand-in (`scripts/pi-stand-in.py`; CI has no pi), started by the chooser with Oriel's
/// flags: it needs the pi-oriel file the app wrote first, writes pi-oriel's state lines and a session file in pi's
/// format, and reports its state to herdr.
extension OrielUITests {
    /// Sends, the live terminal during a dialog, stops, and `/tree` moving the branch, on This Mac.
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

        try await say("slow", in: pane)
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        // /tree in the terminal back before the last turn: the chat shows that branch, and the next turn grows on it.
        app.typeText("/tree\r")
        XCTAssertTrue(element("chat.\(pane).composer").vanishes(within: 3))
        try await send("\r", to: pane)
        try await waitFor(pane) { $0.contains("Navigated to selected point") }
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(row(pane, "user", "slow").vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists)
        try await say("again", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **again**").exists(within: 5))
        XCTAssertFalse(row(pane, "user", "slow").exists)
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
