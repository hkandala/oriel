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
        XCTAssertTrue(element("titlebar.machine").has(\.label, "Machine: Key Host", within: 3))
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
        // Not one an earlier test left: it would need no password.
        try await Self.post("\(one)/ssh-drop", Data("oriel-pw".utf8))
        relaunch(one, ["-machines", "[]"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        addHost("Password Host", "oriel-pw")
        // A new host key: its fingerprint, and yes or no (accepted once per CI machine).
        let text = element("ask.text")
        XCTAssertTrue(text.exists(within: connect))
        if (text.value as? String ?? "").contains("fingerprint") {
            keepScreenshot("host key")
            element("ask.ok").click()
        }
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
        XCTAssertTrue(element("titlebar.machine").has(\.label, "Machine: Key Host", within: 3))
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
