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

    /// A build that refuses Oriel's flags (the company build may) still starts: the chooser types the plain command
    /// once, and its pane has no chat.
    func testAnOpenCodeThatRefusesTheFlagsStartsPlain() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let tabs = try await tabIDs()
        closeNew("tab", besides: tabs)
        app.typeKey("t", modifierFlags: .command)
        let pane = try await pane(of: newTabID(after: tabs))
        XCTAssertTrue(element("pane.\(pane).chooser.terminal").exists(within: 3))
        try await waitForPrompt(pane)
        let standIn = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "scripts/opencode-stand-in.py").path
        try await send("function opencode { ORIEL_STAND_IN_REFUSE=1 python3 '\(standIn)' \"$@\"; }\r", to: pane)
        app.typeKey("2", modifierFlags: [])
        app.typeKey("4", modifierFlags: [])
        try await waitFor(pane, times: 100) { $0.contains("OpenCode stand-in plain") }
        let text = try await read(pane)
        XCTAssertTrue(text.contains("Unrecognized flag: --port"), text)
        // Once the loader went (herdr saw the agent, its marker was asked): no switch to a chat.
        XCTAssertTrue(element("pane.\(pane).loader").vanishes(within: 5))
        XCTAssertFalse(element("pane.\(pane).view.chat").exists)
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
