import XCTest

/// The chat view (future-work/chat-view) with Claude Code's stand-in (`scripts/claude-stand-in.py`; CI has no Claude
/// Code), started by the chooser with Oriel's flags: it runs their hooks, writes a transcript in Claude Code's format
/// and reports its state to herdr.
extension OrielUITests {
    /// In this checkout, which the pane's shell reads (the runner itself is sandboxed).
    private static let standIn = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts/claude-stand-in.py").path

    /// Sends, stops, levels, slash text to the terminal, and "Not sent", on This Mac.
    func testAChatSendsStopsAndShowsItsLevels() async throws {
        let pane = try await startChat().pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await waitFor(pane) { $0.contains("Echo: **hello**") }

        // Steps: the turn's command as a stack, which a click opens; Replies: only the quiet line; All: open.
        let levels = ["replies", "steps", "all"].map { element("chat.\(pane).level.\($0)") }
        let before = levels.first(where: \.isSelected) ?? levels[1]
        addTeardownBlock { @MainActor in
            if before.exists {
                before.click()
            }
        }
        levels[1].click()
        let stacks = app.descendants(matching: .any).matching(identifier: "chat.\(pane).stack")
        let stack = stacks.element(boundBy: 0)
        XCTAssertTrue(stack.has(\.stringValue, "closed", within: 2))
        XCTAssertTrue(stack.label.hasPrefix("Ran 1 command"), stack.label)
        stack.click()
        XCTAssertTrue(stack.has(\.stringValue, "open", within: 2))
        levels[0].click()
        XCTAssertTrue(stack.vanishes(within: 2))
        XCTAssertTrue(element("chat.\(pane).summary").stringValue.hasSuffix(" · 1 command"))
        // Clicked open, it stays open; All opens every stack.
        levels[1].click()
        XCTAssertTrue(stack.has(\.stringValue, "open", within: 2))
        stack.click()
        XCTAssertTrue(stack.has(\.stringValue, "closed", within: 2))
        try await say("again", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **again**").exists(within: 5))
        levels[2].click()
        XCTAssertTrue(stacks.element(boundBy: 1).has(\.stringValue, "open", within: 2))
        XCTAssertEqual(stack.stringValue, "closed")
        keepScreenshot("chat")

        // Stop sends Esc while it works.
        try await say("slow", in: pane)
        let stop = element("chat.\(pane).stop")
        XCTAssertTrue(stop.exists(within: 5))
        stop.click()
        XCTAssertTrue(row(pane, "note", "Interrupted").exists(within: 5))
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))

        // Not confirmed by the transcript within 5 s: "Not sent", and the draft comes back.
        try await say("mute", in: pane)
        app.typeText("lost\r")
        XCTAssertTrue(element("chat.\(pane).not-sent").exists(within: 8))
        XCTAssertEqual(element("chat.\(pane).composer").stringValue, "lost")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        // Slash text goes to the terminal, which the card shows.
        app.typeText("/help\r")
        XCTAssertTrue(element("chat.\(pane).composer").vanishes(within: 3))
        try await waitFor(pane) { $0.contains("/help") }
        XCTAssertTrue(element("pane.\(pane).view.terminal").isSelected)
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 3))
    }

    /// The live terminal while it waits; a question answered in the chat; the chat again after a relaunch.
    func testAChatShowsTheTerminalWhileItWaitsAndAnswersQuestions() async throws {
        let (tab, pane) = try await startChat()
        try await say("wait", in: pane)
        let drawer = element("chat.\(pane).drawer")
        XCTAssertTrue(drawer.exists(within: 5))
        XCTAssertFalse(element("chat.\(pane).composer").exists)
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("1")
        XCTAssertTrue(drawer.vanishes(within: 5))
        XCTAssertTrue(row(pane, "reply", "Allowed.").exists(within: 5))

        try await say("ask", in: pane)
        let pear = element("chat.\(pane).option.Pear")
        XCTAssertTrue(pear.exists(within: 5))
        keepScreenshot("question")
        pear.click()
        XCTAssertTrue(row(pane, "reply", "You chose Pear.").exists(within: 5))

        // No state kept in the app: the marker comes back from pane.process_info.
        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(row(pane, "reply", "You chose Pear.").exists(within: 10))
    }

    /// The same chat on a remote machine: hooks, transcript and answers over the relay.
    func testAChatOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        let pane = try await startChat(["-machines", Self.keyHost, "-machine", "e2e-key"]).pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await say("ask", in: pane)
        let pear = element("chat.\(pane).option.Pear")
        XCTAssertTrue(pear.exists(within: 5))
        pear.click()
        XCTAssertTrue(row(pane, "reply", "You chose Pear.").exists(within: 5))
    }

    /// A new tab of w2 whose chooser starts the stand-in as Claude Code, once the chat shows with the keyboard in its
    /// reply box.
    private func startChat(_ arguments: [String] = []) async throws -> (tab: String, pane: String) {
        if !arguments.isEmpty {
            relaunch(one, arguments)
        }
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        let tabs = try await tabIDs()
        closeNew("tab", besides: tabs)
        app.typeKey("t", modifierFlags: .command)
        let tab = try await newTabID(after: tabs)
        let pane = try await pane(of: tab)
        XCTAssertTrue(element("pane.\(pane).chooser.terminal").exists(within: 3))
        try await waitForPrompt(pane)
        // `function`: a user's own `claude` alias does not expand in it.
        try await send("function claude { python3 '\(Self.standIn)' \"$@\"; }\r", to: pane)
        app.typeKey("2", modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        let composer = element("chat.\(pane).composer")
        XCTAssertTrue(composer.exists(within: 15))
        XCTAssertTrue(hasKeyboard(composer))
        return (tab, pane)
    }

    /// Types a message into the reply box and waits until the transcript has it.
    private func say(_ text: String, in pane: String) async throws {
        app.typeText(text + "\r")
        XCTAssertTrue(row(pane, "user", text).exists(within: 5))
    }

    /// The chat's row of this kind with this text.
    private func row(_ pane: String, _ kind: String, _ value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "chat.\(pane).\(kind)", value)).firstMatch
    }
}
