import XCTest

/// The chat view (ui/chat-view) with Claude Code's stand-in (`scripts/claude-stand-in.py`; CI has no Claude
/// Code), started by the chooser with Oriel's flags: it runs their hooks, writes a transcript in Claude Code's format
/// and reports its state to herdr.
extension OrielUITests {
    /// In this checkout, which the pane's shell reads (the runner itself is sandboxed).
    private static let scripts = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts")

    /// Sends, stops, levels, slash text to the terminal, and "Not sent", on This Mac.
    func testAChatSendsStopsAndShowsItsLevels() async throws {
        let pane = try await startChat().pane
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        try await waitFor(pane) { $0.contains("Echo: **hello**") }

        XCTAssertTrue(twoRows(pane, above: "pane.\(pane).view.chat"))
        // Steps: the turn's command as a stack, which a click opens; Replies: only the quiet line; All: open.
        let before = element("chat.\(pane).level").stringValue
        addTeardownBlock { @MainActor in
            if !before.isEmpty, self.element("chat.\(pane).level").exists {
                self.level(before, in: pane)
            }
        }
        level("Steps", in: pane)
        let stacks = app.descendants(matching: .any).matching(identifier: "chat.\(pane).stack")
        let stack = stacks.element(boundBy: 0)
        XCTAssertTrue(stack.has(\.stringValue, "closed", within: 2))
        // The turn's quiet line holds its run of calls.
        XCTAssertTrue(stack.label.hasPrefix("Worked ") && stack.label.contains(" · 1 command"), stack.label)
        stack.click()
        XCTAssertTrue(stack.has(\.stringValue, "open", within: 2))
        level("Replies", in: pane)
        XCTAssertTrue(stack.vanishes(within: 2))
        XCTAssertTrue(element("chat.\(pane).summary").stringValue.hasSuffix(" · 1 command"))
        // Clicked open, it stays open; All opens every stack.
        level("Steps", in: pane)
        XCTAssertTrue(stack.has(\.stringValue, "open", within: 2))
        stack.click()
        XCTAssertTrue(stack.has(\.stringValue, "closed", within: 2))
        try await say("again", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **again**").exists(within: 5))
        level("All", in: pane)
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

    /// A floated chat pane's window shows the chat with the keyboard, and its title row has the switch.
    func testAFloatingWindowShowsTheChat() async throws {
        let pane = try await startChat().pane
        let window = try float(pane)
        let composer = element("chat.\(pane).composer", in: window)
        XCTAssertTrue(composer.exists(within: 5))
        XCTAssertTrue(hasKeyboard(composer))
        try await say("hello", in: pane)
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        keepScreenshot("floating chat", of: window)
        element("pane.\(pane).view.terminal", in: window).click()
        XCTAssertTrue(composer.vanishes(within: 3))
        XCTAssertTrue(hasKeyboard("terminal.\(pane)", in: window))
        element("pane.\(pane).view.chat", in: window).click()
        XCTAssertTrue(hasKeyboard(composer))
        element("float.\(pane).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 3))
    }

    /// A tool call opens on its own to its input and output. A click on a reply or on the chat's empty side gives the
    /// card the keyboard in its reply box, which grows with its lines up to 10 and then scrolls.
    func testAChatTakesTheKeyboardOnAnyClickAndItsBoxGrows() async throws {
        let (tab, pane) = try await startChat()
        try await say("hello", in: pane)
        let reply = row(pane, "reply", "Echo: **hello**")
        XCTAssertTrue(reply.exists(within: 5))
        // At Steps (open at All).
        let stack = element("chat.\(pane).stack")
        XCTAssertTrue(stack.exists(within: 2))
        if stack.stringValue == "closed" {
            stack.click()
        }
        let tool = element("chat.\(pane).tool")
        XCTAssertTrue(tool.has(\.stringValue, "closed", within: 2))
        tool.click()
        XCTAssertTrue(tool.has(\.stringValue, "open", within: 2))
        XCTAssertTrue(row(pane, "tool.input", "command: echo hello").exists(within: 2))
        XCTAssertTrue(row(pane, "tool.output", "hello").exists)
        let composer = element("chat.\(pane).composer")
        let one = composer.frame.height
        var heights: [Int: CGFloat] = [:]
        app.typeText("1")
        for line in 2 ... 12 {
            app.typeKey(.return, modifierFlags: .option)
            app.typeText("\(line)")
            XCTAssertTrue(until(2) { composer.stringValue.hasSuffix("\n\(line)") })
            heights[line] = composer.frame.height
        }
        XCTAssertGreaterThan(heights[3] ?? 0, one * 2.5, "\(one) \(heights)")
        XCTAssertGreaterThan(heights[10] ?? 0, heights[9] ?? 0, "\(heights)")
        XCTAssertEqual(heights[12], heights[10], "\(heights)")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        // A new pane beside it takes the keyboard; a click on the reply's text gives it back.
        app.typeKey("d", modifierFlags: .command)
        let chooser = try await replaced(pane, in: tab, besides: [pane])
        XCTAssertTrue(element("pane.\(chooser).chooser.terminal").exists(within: 3))
        let unfocused = NSPredicate(format: "hasKeyboardFocus == false")
        XCTAssertTrue(until(2) { unfocused.evaluate(with: composer) })
        // On its first word.
        let word = reply.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 12, dy: 0))
        word.click()
        XCTAssertTrue(hasKeyboard(composer))
        // A word selected with a double click keeps the keyboard, so Copy copies it.
        NSPasteboard.general.clearContents()
        word.doubleClick()
        XCTAssertTrue(until(2) { unfocused.evaluate(with: composer) })
        app.typeKey("c", modifierFlags: .command)
        composer.click()
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(until(2) { composer.stringValue == "Echo" }, composer.stringValue)
        // And from the chooser again, a click on the chat's empty side.
        element("pane.\(chooser).chooser.terminal").click()
        XCTAssertTrue(until(2) { unfocused.evaluate(with: composer) })
        element("chat.\(pane)").coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.2)).click()
        XCTAssertTrue(hasKeyboard(composer))
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

    /// Claude Code started by hand has no chat: Enable Chat starts it again with the flags, in the same session (its
    /// reply from before shows in the chat). Its tab shows the session's title, none yet.
    func testEnableChatStartsAnAgentAgainInItsSession() async throws {
        let (tab, pane) = try await startChat(["-appearance", "dark"], chat: false, plain: true)
        let enable = element("pane.\(pane).enable-chat")
        XCTAssertTrue(enable.exists(within: 10))
        // Row 1 the session's title, row 2 the button where Chat | Terminal sits.
        XCTAssertTrue(until(3) { self.twoRows(pane, title: "Untitled", above: "pane.\(pane).enable-chat") })
        let label = { self.element("tab.\(tab)").label }
        XCTAssertTrue(until(3) { label().contains("Claude Code Untitled") }, label())
        try await send("hello\r", to: pane)
        try await waitFor(pane) { $0.contains("Echo: **hello**") }
        keepScreenshot("enable-chat")
        enable.click()
        XCTAssertTrue(element("chat.\(pane).composer").exists(within: 20))
        XCTAssertTrue(row(pane, "reply", "Echo: **hello**").exists(within: 5))
        // The reply's model and effort, from the transcript.
        XCTAssertEqual(element("chat.\(pane).model").stringValue, "claude-stand-in · high")
        XCTAssertFalse(enable.exists)
    }

    /// A new tab of w2 whose chooser starts the agent at `agent` (its place in the chooser) as its stand-in,
    /// `scripts/<command>-stand-in.py`, once the chat shows with the keyboard in its reply box.
    /// `environment`: assignments before the stand-in's command; `chat: false` returns once the agent was picked.
    /// `plain`: typed into the shell with no flags instead, the chooser closed.
    func startChat(_ arguments: [String] = [], agent: Int = 0, environment: String = "", chat: Bool = true,
                   plain: Bool = false) async throws -> (tab: String, pane: String)
    {
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
        // `function`: a user's own alias of the command does not expand in it.
        let command = ["claude", "codex", "pi", "opencode"][agent]
        let standIn = Self.scripts.appending(path: "\(command)-stand-in.py").path
        try await send("function \(command) { \(environment)python3 '\(standIn)' \"$@\"; }\r", to: pane)
        if plain {
            app.typeKey(.escape, modifierFlags: [])
            try await send("\(command)\r", to: pane)
            return (tab, pane)
        }
        app.typeKey("2", modifierFlags: [])
        app.typeKey("\(agent + 1)", modifierFlags: [])
        guard chat else { return (tab, pane) }
        let composer = element("chat.\(pane).composer")
        XCTAssertTrue(composer.exists(within: 15))
        XCTAssertTrue(hasKeyboard(composer))
        return (tab, pane)
    }

    /// Picks the detail level in the card's Show pull-down.
    func level(_ title: String, in pane: String) {
        let menu = element("chat.\(pane).level")
        menu.click()
        menu.menuItems[title].click()
        XCTAssertTrue(menu.has(\.stringValue, title, within: 2))
    }

    /// Types a message into the reply box and waits until the transcript has it (the bubble on its way is `sending`).
    func say(_ text: String, in pane: String) async throws {
        app.typeText(text + "\r")
        XCTAssertTrue(row(pane, "user", text).exists(within: 5))
    }

    /// The chat's row of this kind with this text.
    func row(_ pane: String, _ kind: String, _ value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "chat.\(pane).\(kind)", value)).firstMatch
    }
}
