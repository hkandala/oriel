import XCTest

/// Remote machines over SSH (phase 26), against CI's sshd on localhost (`scripts/ci-sshd.sh`): oriel-key is this
/// user with a key, so its sessions are the e2e ones; oriel-pw asks a host key and a password and has no herdr. They
/// skip where no such sshd runs.
extension OrielUITests {
    /// Key Host, for a launch that starts on it (`-machine e2e-key`).
    private static let keyHost = #"[{"id":"e2e-key","name":"Key Host","target":"oriel-key","icon":"server.rack"}]"#

    func testAddingAKeyHostConnectsWithoutAskingAndOpensItsSessions() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        addHost("Key Host", "oriel-key")
        // Its sessions come from herdr over SSH; session one opens as a page.
        openPage(one)
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        XCTAssertFalse(element("ask.text").exists)
        keepScreenshot("remote page")
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
        addHost("Password Host", "oriel-pw")
        // A new host key: its fingerprint on a line of its own, and Connect instead of ssh's yes or no.
        let text = element("ask.text")
        XCTAssertTrue(text.exists(within: connect))
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

    /// The machine button's Add Remote Host, filled and added.
    private func addHost(_ name: String, _ target: String) {
        element("titlebar.machine").click()
        app.menuItems["Add Remote Host…"].click()
        let field = element("add-host.name")
        XCTAssertTrue(field.exists(within: 3))
        field.click()
        app.typeText(name)
        element("add-host.target").click()
        app.typeText(target)
        keepScreenshot("add remote host")
        element("add-host.add").click()
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
