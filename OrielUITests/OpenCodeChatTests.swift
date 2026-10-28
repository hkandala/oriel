import XCTest

/// OpenCode's chat (future-work/chat-view) with its stand-in (`scripts/opencode-stand-in.py`; CI has no OpenCode),
/// started by the chooser with Oriel's line: it serves opencode's history, events and requests behind the password
/// from the launch's file, and appends the plugin's state lines.
extension OrielUITests {
    /// A permission and a question answered in the chat, a picker in the live terminal, and Stop, on This Mac.
    func testAnOpenCodeChatAnswersPermissionsAndQuestions() async throws {
        let pane = try await startChat(agent: 3).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))

        try await say("allow", in: pane)
        let allow = element("chat.\(pane).option.Allow once")
        XCTAssertTrue(allow.exists(within: 5))
        keepScreenshot("opencode-permission")
        allow.click()
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))
        XCTAssertTrue(allow.vanishes(within: 3))

        try await say("ask", in: pane)
        let blue = element("chat.\(pane).option.Blue")
        XCTAssertTrue(blue.exists(within: 5))
        blue.click()
        XCTAssertTrue(row(pane, "reply", "You chose Blue.").exists(within: 5))

        // A dialog (a picker) has no card: the live terminal, which 1 closes.
        try await say("pick", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Picked.").exists(within: 5))

        // Stop presses Esc twice while it works.
        try await say("slow", in: pane)
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
    }

    /// The same over the relay: the files written first, curl on the machine, a permission answered.
    func testAnOpenCodeChatOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        let pane = try await startChat(["-machines", Self.keyHost, "-machine", "e2e-key"], agent: 3).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("allow", in: pane)
        let allow = element("chat.\(pane).option.Allow once")
        XCTAssertTrue(allow.exists(within: 5))
        allow.click()
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))
    }
}
