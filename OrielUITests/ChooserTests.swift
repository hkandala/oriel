import XCTest

/// A new pane's chooser (ui/new-pane): Terminal, Agent or Browser, with the keyboard from the start; and the commands
/// that change a pane's kind.
extension OrielUITests {
    /// A pane the app made shows the chooser: Return picks Terminal.
    func pickTerminal(_ pane: String) {
        let terminal = element("pane.\(pane).chooser.terminal")
        XCTAssertTrue(terminal.has(\.isSelected, true, within: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(terminal.vanishes(within: 2))
    }

    /// ⌘T: the new tab's card shows the chooser with Terminal selected and the keyboard. Keys type nothing into the
    /// shell; Return gives the terminal, which takes keys.
    func testNewTabShowsTheChooserAndReturnGivesATerminal() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        app.typeKey("t", modifierFlags: .command)
        let tab = try await newTabID(after: before), pane = try await pane(of: tab)
        let terminal = element("pane.\(pane).chooser.terminal")
        XCTAssertTrue(terminal.has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("pane.\(pane).chooser.browser").exists)
        let title = element("pane.\(pane).title")
        XCTAssertTrue(until(2) { [title.label, title.stringValue].contains("New Pane") }, title.debugDescription)
        keepScreenshot("new pane chooser")
        try await waitForPrompt(pane)
        // "New Tab" while it asks, also once the shell is up; the shell's title after the pick.
        let capsule = element("tab.\(tab)")
        XCTAssertFalse(until(1.5) { capsule.label != "New Tab" }, capsule.label)
        app.typeText("echo leaked")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(terminal.vanishes(within: 2))
        // The shell and the folder: "zsh tmp" here, "bash tmp" on CI.
        XCTAssertTrue(until(3) { capsule.label.hasSuffix(" tmp") }, capsule.label)
        try await typeAndRead(pane)
        let text = try await read(pane)
        XCTAssertFalse(text.contains("leaked"), text)

        // ⌘T then Return at once, before herdr made the pane: the Return is the new card's, not the old shell's (which
        // keeps the first responder meanwhile).
        let tabs = try await tabIDs()
        app.typeKey("t", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        let next = try await self.pane(of: newTabID(after: tabs))
        XCTAssertTrue(element("pane.\(next)").exists(within: 3))
        XCTAssertFalse(element("pane.\(next).chooser.terminal").exists)
        try await waitForPrompt(next)
        try await typeAndRead(next)
        let old = try await read(pane)
        XCTAssertEqual(old, text, "the Return went to the old shell")
    }

    /// ⌘D on a pane made outside the app (no chooser): the split's card shows it. ↑ ↓ move the selection and stop at
    /// the ends, → opens Agent's agents under it and ← closes them; Esc gives the terminal.
    func testSplitShowsTheChooserArrowsMoveAndEscGivesATerminal() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("chooser split")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(left)").has(\.isHittable, true, within: 3))
        XCTAssertFalse(element("pane.\(left).chooser.terminal").exists)
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        app.typeKey("d", modifierFlags: .command)
        let right = try await replaced(left, in: tab, besides: [left])
        let options = ["terminal", "agent", "browser", "claude"].map { element("pane.\(right).chooser.\($0)") }
        func selected(_ index: Int) -> Bool {
            until(2) { options.map { $0.exists && $0.isSelected } == options.indices.map { $0 == index } }
        }
        XCTAssertTrue(options[0].exists(within: 3))
        XCTAssertTrue(selected(0))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(selected(1))
        XCTAssertFalse(options[3].exists)
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(selected(3))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(selected(1))
        XCTAssertTrue(options[3].vanishes(within: 2))
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(selected(2))
        for _ in 0 ..< 3 {
            app.typeKey(.upArrow, modifierFlags: [])
        }
        XCTAssertTrue(selected(0))
        // The card's menu over the list too.
        options[1].rightClick()
        let main = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).firstMatch
        XCTAssertTrue(main.menuItems["Split Right"].exists(within: 2))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(main.menuItems["Split Right"].vanishes(within: 2))
        XCTAssertTrue(options[0].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(options[0].vanishes(within: 2))
        try await waitForPrompt(right)
        try await typeAndRead(right)
    }

    /// An agent's pick types its command into the shell and shows the loader until herdr reports the agent; one whose
    /// command ends shows the terminal with what it printed. CI has no agents: the test defines stand-ins in the
    /// pane's shell, which the app's typed commands run.
    func testPickingAnAgentStartsItBehindTheLoader() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        func newPane(_ name: String, _ body: String) async throws -> String {
            let tabs = try await tabIDs()
            app.typeKey("t", modifierFlags: .command)
            let pane = try await pane(of: newTabID(after: tabs))
            XCTAssertTrue(element("pane.\(pane).chooser.terminal").exists(within: 3))
            try await waitForPrompt(pane)
            try await send("\(name)() { \(body); }\r", to: pane)
            return pane
        }

        let report = #""$HERDR_BIN_PATH" --session "$HERDR_SESSION" pane report-agent --source oriel-e2e "#
            + #"--agent claude --state idle "$HERDR_PANE_ID""#
        let agent = try await newPane("claude", "echo oriel-stand-in; sleep 2; \(report); sleep 100")
        // 2 opens Agent with its first agent selected: Return picks it.
        app.typeKey("2", modifierFlags: [])
        XCTAssertTrue(element("pane.\(agent).chooser.claude").has(\.isSelected, true, within: 2))
        XCTAssertEqual(element("pane.\(agent).chooser.agent").stringValue, "expanded")
        app.typeKey(.return, modifierFlags: [])
        let loader = element("pane.\(agent).loader")
        XCTAssertTrue(loader.exists(within: 2))
        try await waitFor(agent) { $0.contains("oriel-stand-in") }
        XCTAssertTrue(loader.exists, "the loader went before herdr reported the agent")
        keepScreenshot("agent loader")
        XCTAssertTrue(loader.vanishes(within: 5))
        let reported = try await pane(agent)["agent"] as? String
        XCTAssertEqual(reported, "claude")
        XCTAssertTrue(hasKeyboard("terminal.\(agent)"))

        let failing = try await newPane("opencode", "echo oriel-no-agent")
        app.typeKey("2", modifierFlags: [])
        app.typeKey("4", modifierFlags: [])
        let failed = element("pane.\(failing).loader")
        XCTAssertTrue(failed.exists(within: 2))
        XCTAssertTrue(failed.vanishes(within: 8))
        try await waitFor(failing) { $0.contains("\noriel-no-agent") }
    }

    /// ⌘R on a terminal gives a shell with no chooser; on an agent pane, the chooser. Open Terminal Here shows only
    /// on an agent pane, Start Agent Here on every pane.
    func testReplacePaneAndThePaletteFollowThePanesKind() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("chooser kinds")
        try await settle([tab])
        element("tab.\(tab)").click()
        element("terminal.\(pane)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        func commands(here terminal: Bool) {
            openPalette()
            app.typeText("here")
            XCTAssertTrue(element("palette.command.Start Agent Here").exists(within: 2))
            XCTAssertEqual(element("palette.command.Open Terminal Here").exists, terminal)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("palette.filter").vanishes(within: 2))
        }
        commands(here: false)

        app.typeKey("r", modifierFlags: .command)
        let shell = try await replaced(pane, in: tab, besides: [])
        XCTAssertTrue(element("pane.\(shell)").exists(within: 3))
        XCTAssertFalse(element("pane.\(shell).chooser.terminal").exists)

        try await Self.call(one, "pane.report_agent", [
            "pane_id": shell, "source": "oriel-e2e", "agent": "claude", "state": "idle",
        ])
        XCTAssertTrue(until(3) { element("pane.\(shell)").label.hasPrefix("claude") })
        XCTAssertTrue(hasKeyboard("terminal.\(shell)"))
        commands(here: true)
        app.typeKey("r", modifierFlags: .command)
        let chosen = try await replaced(shell, in: tab, besides: [])
        let terminal = element("pane.\(chosen).chooser.terminal")
        XCTAssertTrue(terminal.has(\.isSelected, true, within: 3))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(terminal.vanishes(within: 2))
        try await waitForPrompt(chosen)
        try await typeAndRead(chosen)
    }
}
