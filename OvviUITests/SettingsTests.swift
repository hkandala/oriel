import XCTest

/// The Settings window (ui/settings): ⌘, opens it; each page's setting takes effect in the main window. Settings live
/// in the defaults the tests share with the user's Ovvi, and New Pane's switches in the tests' config folder, so each
/// test puts back what it changes.
extension OvviUITests {
    /// The Settings window, by its sidebar.
    var settingsWindow: XCUIElement {
        app.windows.containing(.any, identifier: "settings.sidebar").firstMatch
    }

    /// ⌘, opens Settings (or brings it forward) at a page.
    func openSettings(_ page: String) {
        app.typeKey(",", modifierFlags: .command)
        let row = element("settings.page.\(page)", in: settingsWindow)
        XCTAssertTrue(row.exists(within: 3), "no Settings window")
        row.click()
    }

    /// Picks an item of a Settings pop-up or segmented control.
    func choose(_ id: String, _ item: String) {
        let control = element(id, in: settingsWindow)
        XCTAssertTrue(control.exists(within: 3), id)
        if control.elementType == .popUpButton {
            control.click()
            control.menuItems[item].click()
        } else {
            control.buttons[item].firstMatch.click()
        }
    }

    /// Sets a Settings switch, whatever it was.
    func turn(_ id: String, _ isOn: Bool) {
        let toggle = element(id, in: settingsWindow)
        XCTAssertTrue(toggle.exists(within: 3), id)
        if (toggle.value as? Int == 1) != isOn {
            toggle.click()
        }
        XCTAssertTrue(until(2) { (toggle.value as? Int == 1) == isOn }, "\(id): \(String(describing: toggle.value))")
    }

    /// Every page opens with its first control, in dark and in light (pictures for people reviewing a run); Open at
    /// login flips; a search pick opens the page of the row it found; Appearance's tiles change the main window's look.
    func testSettingsPagesSearchAndLook() {
        for appearance in ["dark", "light"] {
            relaunch(one, ["-appearance", appearance])
            XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
            let controls = ["general": "settings.general.open-at-login", "appearance": "settings.style.glass",
                            "terminal": "settings.terminal.font", "agents": "settings.agents.view",
                            "machines": "settings.machines.add", "plugins": "plugins.source"]
            for page in ["general", "appearance", "terminal", "agents", "machines", "plugins"] {
                openSettings(page)
                XCTAssertTrue(element(controls[page] ?? "", in: settingsWindow).exists(within: 3), page)
                keepScreenshot("settings \(page) \(appearance)", of: settingsWindow)
            }
        }
        // Open at login flips (a run with a test config folder never registers the build for login).
        openSettings("general")
        turn("settings.general.open-at-login", true)
        turn("settings.general.open-at-login", false)
        // A search lists the rows it finds; a pick opens their page.
        let search = settingsWindow.searchFields.firstMatch
        search.click()
        search.typeText("blink")
        let found = element("settings.search.terminal.blink", in: settingsWindow)
        XCTAssertTrue(found.exists(within: 2))
        XCTAssertFalse(element("settings.search.terminal.font", in: settingsWindow).exists)
        keepScreenshot("settings search", of: settingsWindow)
        found.click()
        XCTAssertTrue(element("settings.terminal.blink", in: settingsWindow).exists(within: 2))
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])

        // The style's tiles (the appearance is pinned by the launch argument), from Glass to Classic.
        openSettings("appearance")
        addTeardownBlock { @MainActor [self] in
            openSettings("appearance")
            element("settings.style.glass", in: settingsWindow).click()
        }
        element("settings.style.glass", in: settingsWindow).click()
        XCTAssertTrue(element("window.look").has(\.stringValue, "glass light", within: 3))
        element("settings.style.classic", in: settingsWindow).click()
        XCTAssertTrue(element("window.look").has(\.stringValue, "classic light", within: 3))
        // ⌘W closes Settings.
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))
    }

    /// Terminal ▸ Font changes every terminal's grid at once, and the stream stays open; a selection copies itself;
    /// Option acts as Meta.
    func testSettingsTerminalFontAndOptionKey() async throws {
        relaunch(one, pin: false)
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await expectPTYSize("w1:p1")
        let grid = terminal.stringValue
        addTeardownBlock { @MainActor [self] in
            openSettings("terminal")
            choose("settings.terminal.font", "SF Mono")
            choose("settings.terminal.option", "Types special characters")
            turn("settings.terminal.copy", false)
        }
        openSettings("terminal")
        // Monaco's line is taller than SF Mono's: fewer rows.
        choose("settings.terminal.font", "Monaco")
        try await expect("the grid to change from \(grid)") { terminal.stringValue != grid }
        try await expectPTYSize("w1:p1")
        choose("settings.terminal.option", "Acts as Meta")
        turn("settings.terminal.copy", true)
        keepScreenshot("settings terminal", of: settingsWindow)
        // Out of the way of the terminal on CI's small screen.
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))

        // A drag over the first line puts it on the clipboard, with no ⌘C.
        keepClipboard()
        NSPasteboard.general.clearContents()
        try await send("clear; echo ovvi-copy-$((6*7))\r", to: "w1:p1")
        // `clear` runs first: the first line is the output.
        try await waitFor("w1:p1") { $0.hasPrefix("ovvi-copy-42") }
        let line = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.01))
        line.click(
            forDuration: 0.1,
            thenDragTo: terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.01)),
        )
        XCTAssertTrue(until(3) { NSPasteboard.general.string(forType: .string)?.contains("copy-42") == true },
                      NSPasteboard.general.string(forType: .string) ?? "nothing copied")

        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_keys", ["pane_id": "w1:p1", "keys": ["ctrl+c"]])
        }
        try await send("clear; cat -v\r", to: "w1:p1")
        try await expect("cat to run") { try await foreground("w1:p1").contains("cat") }
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        app.typeKey("b", modifierFlags: .option)
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p1") { $0.split(separator: "\n").contains("^[b") }
    }

    /// Agents: a switched-off agent leaves New Pane, extra arguments go into the agent's line, and a new agent opens
    /// on its chat.
    func testSettingsAgentsSwitchArgumentsAndChat() async throws {
        relaunch(one, pin: false)
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        addTeardownBlock { @MainActor [self] in
            openSettings("agents")
            turn("settings.agents.codex.new-pane", true)
            let field = element("settings.agents.claude.arguments", in: settingsWindow)
            field.click()
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(.delete, modifierFlags: [])
            choose("settings.agents.view", "Terminal")
        }
        openSettings("agents")
        turn("settings.agents.codex.new-pane", false)
        let field = element("settings.agents.claude.arguments", in: settingsWindow)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        // The quote is refused: it would go into a typed line.
        field.typeText("--model e2e-\"opus")
        XCTAssertTrue(field.has(\.stringValue, "--model e2e-opus", within: 2), field.stringValue)
        choose("settings.agents.view", "Chat")
        keepScreenshot("settings agents", of: settingsWindow)
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settingsWindow.vanishes(within: 2))

        // Codex is off: Agent lists Claude Code, Pi and OpenCode.
        element("workspace.w2").click()
        let tabs = try await tabIDs()
        closeNew("tab", besides: tabs)
        app.typeKey("t", modifierFlags: .command)
        let pane = try await pane(of: newTabID(after: tabs))
        XCTAssertTrue(element("pane.\(pane).chooser.terminal").exists(within: 3))
        try await waitForPrompt(pane)
        let standIn = Self.scripts.appending(path: "claude-stand-in.py").path
        try await send("function claude { python3 '\(standIn)' \"$@\"; }\r", to: pane)
        app.typeKey("2", modifierFlags: [])
        XCTAssertTrue(element("pane.\(pane).chooser.pi").exists(within: 2))
        XCTAssertFalse(element("pane.\(pane).chooser.codex").exists)
        XCTAssertTrue(element("pane.\(pane).chooser.claude").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let composer = element("chat.\(pane).composer")
        XCTAssertTrue(composer.exists(within: 15), "the card did not open on its chat")
        let info = try await Self.call(one, "pane.process_info", ["pane_id": pane])["process_info"]
        let lines = ((info as? [String: Any])?["foreground_processes"] as? [[String: Any]] ?? [])
            .compactMap { $0["cmdline"] as? String }
        XCTAssertTrue(lines.contains { $0.contains("--model e2e-opus --session-id") }, "\(lines)")
    }

    /// Machines: a machine's page saves a new name on Return, which its row shows; Add Machine says what is wrong
    /// with a target, and Esc leaves it.
    func testSettingsMachinePageSavesAnEdit() {
        let machines = #"[{"id":"e2e-m1","name":"devbox","target":"ovvi-e2e@localhost","icon":"server.rack"},"#
            + #"{"id":"e2e-m2","name":"gpubox","target":"ovvi-e2e@127.0.0.1","icon":"cpu"}]"#
        relaunch(one, ["-machines", machines])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        openSettings("machines")
        let row = element("settings.machine.e2e-m1", in: settingsWindow)
        XCTAssertTrue(element("settings.machine.e2e-m2", in: settingsWindow).exists(within: 3))
        row.click()
        let name = element("settings.machine.name", in: settingsWindow)
        XCTAssertTrue(name.exists(within: 3))
        keepScreenshot("settings machine", of: settingsWindow)
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("buildbox\r")
        settingsWindow.buttons["Back"].click()
        XCTAssertTrue(until(3) { row.exists && row.label.hasPrefix("buildbox,") }, row.label)

        element("settings.machines.add", in: settingsWindow).click()
        let target = element("settings.machine.target", in: settingsWindow)
        XCTAssertTrue(target.exists(within: 3))
        target.click()
        target.typeText("me@build box")
        XCTAssertTrue(element("settings.machine.problem", in: settingsWindow).exists(within: 2))
        XCTAssertFalse(element("settings.machine.save", in: settingsWindow).isEnabled)
        target.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(target.vanishes(within: 2), "Esc left Add Machine open")
    }
}
