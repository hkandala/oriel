import XCTest

/// Remote machines over SSH (phase 26), against CI's sshd on localhost (`scripts/ci-sshd.sh`): oriel-key is this
/// user with a key, so its sessions are the e2e ones; oriel-pw asks a host key and a password and has no herdr. They
/// skip where no such sshd runs.
extension OrielUITests {
    /// Key Host, for a launch that starts on it (`-machine e2e-key`).
    private static let keyHost = #"[{"id":"e2e-key","name":"Key Host","target":"oriel-key","icon":"server.rack"}]"#

    func testAddingAKeyHostOpensItInANewWindowWithoutAsking() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        addHost("Key Host", "oriel-key")
        // A new window on it (user, phase 28), with session one from herdr over SSH; this one keeps its page.
        let remote = try otherWindow(than: identifier)
        XCTAssertEqual(machine(of: remote), "Key Host")
        XCTAssertEqual(machine(of: first), "This Mac")
        XCTAssertTrue(element("terminal.w1:p1", in: first).exists)
        XCTAssertFalse(element("ask.text").exists)
        keepScreenshot("remote window", of: remote)
        // Its own machine in its menu: nothing opens.
        element("titlebar.machine", in: remote).click()
        app.menuItems["Key Host"].click()
        XCTAssertFalse(app.windows.element(boundBy: 2).exists(within: 2))
        // Picked in the first window's menu, it opens another window on it (the new one lies over the first).
        raise(first)
        element("titlebar.machine", in: first).click()
        app.menuItems["Key Host"].click()
        XCTAssertTrue(app.windows.element(boundBy: 2).exists(within: 3))
        XCTAssertTrue(until(3) { machine(of: app.windows.firstMatch) == "Key Host" })
        XCTAssertEqual(machine(of: first), "This Mac")
        // ⌘N in a Key Host window stays on Key Host.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.element(boundBy: 3).exists(within: 3))
        XCTAssertTrue(until(3) { machine(of: app.windows.firstMatch) == "Key Host" })
        XCTAssertEqual(app.windows.count, 4)
        // It went through the host's ControlMaster.
        let dropped = try await Self.post("\(one)/ssh-drop", Data("oriel-key".utf8))
        XCTAssertFalse(dropped.isEmpty)
    }

    func testAPasswordHostAsksAndNeverRetriesByItself() async throws {
        try await skipWithoutSSH()
        // Not one an earlier test left: it would need no password. Its host key is new again.
        try await Self.post("\(one)/ssh-drop", Data("oriel-pw".utf8))
        try await Self.post("\(one)/ssh-forget", Data("oriel-pw".utf8))
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let identifier = app.windows.firstMatch.identifier
        let first = app.windows[identifier]
        addHost("Password Host", "oriel-pw")
        // A new host key, asked in the new window: its fingerprint on a line of its own, and Connect instead of
        // ssh's yes or no.
        let text = element("ask.text")
        XCTAssertTrue(text.exists(within: connect))
        XCTAssertFalse(element("ask.text", in: first).exists)
        XCTAssertTrue(element("terminal.w1:p1", in: first).exists)
        let facts = text.value as? String ?? ""
        XCTAssertTrue(facts.contains("fingerprint is:\nSHA256:"), facts)
        XCTAssertFalse(facts.contains("yes/no"), facts)
        keepScreenshot("host key")
        element("ask.ok").click()
        // A wrong password: ssh asks again.
        try typePassword("wrong")
        try typePassword()
        let missing = app.staticTexts["herdr is not installed on Password Host"]
        XCTAssertTrue(missing.exists(within: connect))

        // The connection dies: one try without a prompt, then Connect, and no more tries.
        let before = try await connections()
        let dropped = try await Self.post("\(one)/ssh-drop", Data("oriel-pw".utf8))
        XCTAssertFalse(dropped.isEmpty)
        XCTAssertTrue(element("detail.connect").exists(within: connect))
        XCTAssertFalse(element("ask.text").exists)
        // ssh's own error, without the server's login banner (CI's sshd has one).
        let failure = element("detail.text").value as? String ?? ""
        XCTAssertTrue(failure.contains("Permission denied"), failure)
        XCTAssertFalse(failure.contains("Authorized users only"), failure)
        let after = try await connections()
        XCTAssertLessThanOrEqual(after, before + 1)
        for _ in 0 ..< 30 {
            try await Task.sleep(for: .milliseconds(200))
            let now = try await connections()
            XCTAssertEqual(now, after, "a retry connected by itself")
        }
        keepScreenshot("disconnected")

        // Connect asks again.
        element("detail.connect").click()
        try typePassword()
        XCTAssertTrue(missing.exists(within: connect))
    }

    func testARemotePageComesBackAfterItsConnectionDies() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        let terminal = element("terminal.w1:p2")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p2")
        terminal.click()
        XCTAssertTrue(hasKeyboard(terminal))
        app.typeText("echo oriel-$((40+2))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor("w1:p2") { $0.contains("\noriel-42") }

        let first = try await Self.post("\(one)/ssh-drop", Data("oriel-key".utf8))
        XCTAssertFalse(first.isEmpty)
        // A new master without a prompt; the card streams again and takes keys.
        try await poll("typing to reach the pane again", times: 20) { () async throws -> Bool? in
            app.typeText("echo oriel-$((40+3))")
            app.typeKey(.return, modifierFlags: [])
            try await Task.sleep(for: .seconds(1))
            return try await read("w1:p2").contains("\noriel-43") ? true : nil
        }
        XCTAssertFalse(element("ask.text").exists)
        XCTAssertFalse(element("detail.reconnecting").exists)
        let second = try await Self.post("\(one)/ssh-drop", Data("oriel-key".utf8))
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second)
    }

    /// CI's sshd allows 2 sessions per connection (a strict server's limit): six panes, the events stream and every
    /// call still go through, over the one session of the relay.
    func testAHostThatAllowsTwoSessionsStreamsEveryPane() async throws {
        try await skipWithoutSSH()
        let (tab, first) = try await createWorkspace("many")
        var panes = [first]
        for (target, direction) in [(0, "right"), (0, "down"), (1, "down"), (1, "right"), (3, "down")] {
            let created = try await Self.call(
                one,
                "pane.split",
                ["target_pane_id": panes[target], "direction": direction,
                 "cwd": "/tmp", "focus": false],
            )
            try panes.append(id(created, "pane"))
        }
        var terminals: [String] = []
        for pane in panes {
            try await terminals.append(terminalID(pane))
        }
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("workspace.\(workspace(of: tab))").click()
        try await expect("every pane of \(tab) to stream", times: 100) {
            let running = try await streams(one)
            return terminals.allSatisfy { terminal in running.contains { $0.contains(terminal) } }
        }
        keepScreenshot("six panes over two sessions")
        let last = element("terminal.\(panes[5])")
        XCTAssertTrue(last.exists)
        try await waitForPrompt(panes[5])
        last.click()
        XCTAssertTrue(hasKeyboard(last))
        app.typeText("echo oriel-$((40+5))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(panes[5]) { $0.contains("\noriel-45") }
    }

    /// The dialog in the palette's glass in each look (screenshots), and its icon picker's search.
    func testTheRemoteHostDialogInEveryLook() {
        for (appearance, style) in [("dark", "glass"), ("light", "glass"), ("dark", "classic"), ("light", "classic")] {
            relaunch(one, ["-appearance", appearance, "-interfaceStyle", style, "-machines", "[]"])
            XCTAssertTrue(element("window.look").has(\.stringValue, "\(style) \(appearance)", within: connect))
            element("titlebar.machine").click()
            // No hosts: nothing to edit.
            XCTAssertFalse(app.menuItems["Edit Remote Host"].exists)
            app.menuItems["Add Remote Host…"].click()
            XCTAssertTrue(element("host.name").exists(within: 3))
            keepScreenshot("add remote host \(style) \(appearance)")
            if style == "classic", appearance == "light" {
                break
            }
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("host.name").vanishes(within: 2))
        }
        let icon = element("host.icon")
        XCTAssertEqual(icon.value as? String, "server.rack")
        icon.click()
        XCTAssertTrue(element("host.icon.gamecontroller").exists(within: 3))
        element("host.icon.search").click()
        app.typeText("globe")
        XCTAssertTrue(element("host.icon.gamecontroller").vanishes(within: 2))
        keepScreenshot("icon search")
        element("host.icon.globe.europe.africa").click()
        XCTAssertTrue(element("host.icon.globe").vanishes(within: 2))
        XCTAssertEqual(icon.value as? String, "globe.europe.africa")
    }

    /// The machine menu's Edit Remote Host: a rename, a new target and icon reach the open window of the machine;
    /// Remove takes it off the menu.
    func testEditingARemoteHostRenamesItAndRemoveTakesItOff() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        editHost("Key Host")
        let name = element("host.name")
        XCTAssertEqual(name.value as? String, "Key Host")
        XCTAssertEqual(element("host.target").value as? String, "oriel-key")
        name.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Build Box")
        element("host.icon").click()
        element("host.icon.search").click()
        app.typeText("flask")
        element("host.icon.flask").click()
        keepScreenshot("edit remote host")
        element("host.save").click()
        XCTAssertTrue(name.vanishes(within: 2))
        let window = app.windows.firstMatch
        XCTAssertEqual(machine(of: window), "Build Box")
        XCTAssertEqual(element("titlebar.machine").value as? String, "flask")
        XCTAssertTrue(element("terminal.w1:p1").exists)

        editHost("Build Box") {
            XCTAssertFalse(app.menuItems["Key Host"].exists)
        }
        element("host.remove").click()
        XCTAssertTrue(name.vanishes(within: 2))
        element("titlebar.machine").click()
        XCTAssertTrue(app.menuItems["Add Remote Host…"].exists(within: 2))
        XCTAssertFalse(app.menuItems["Build Box"].exists)
        XCTAssertFalse(app.menuItems["Edit Remote Host"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// The machine menu's Edit Remote Host ▸ ‹name›.
    private func editHost(_ name: String, menu: () -> Void = {}) {
        element("titlebar.machine").click()
        let edit = app.menuItems["Edit Remote Host"]
        XCTAssertTrue(edit.exists(within: 2))
        XCTAssertTrue(app.menuItems[name].exists)
        menu()
        edit.hover()
        edit.menuItems[name].click()
        XCTAssertTrue(element("host.name").exists(within: 3))
    }

    /// The machine button's Add Remote Host, filled and added.
    private func addHost(_ name: String, _ target: String) {
        element("titlebar.machine").click()
        app.menuItems["Add Remote Host…"].click()
        let field = element("host.name")
        XCTAssertTrue(field.exists(within: 3))
        field.click()
        app.typeText(name)
        element("host.target").click()
        app.typeText(target)
        keepScreenshot("add remote host")
        element("host.save").click()
    }

    /// oriel-pw's password (or another), in the hidden field of ssh's question; Return answers.
    private func typePassword(_ password: String = "oriel-e2e-pw") throws {
        let answer = element("ask.answer")
        XCTAssertTrue(answer.exists(within: connect))
        XCTAssertEqual(answer.elementType, .secureTextField)
        keepScreenshot("password")
        answer.click()
        app.typeText(password)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(answer.vanishes(within: 3))
    }

    /// The window's machine, by name.
    private func machine(of window: XCUIElement) -> String {
        element("window.machine", in: window).value as? String ?? ""
    }

    /// How many connections CI's sshd has seen.
    private func connections() async throws -> Int {
        try await field(Int(String(decoding: Self.post("\(one)/ssh-connections"), as: UTF8.self)), "sshd connections")
    }

    private func skipWithoutSSH() async throws {
        if await (try? Self.post("\(one)/ssh-connections")) == nil {
            throw XCTSkip("no sshd on 127.0.0.1:2222 (scripts/ci-sshd.sh, CI only)")
        }
    }
}
