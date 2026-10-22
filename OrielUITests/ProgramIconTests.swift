import XCTest

/// Program icons (phase 12): tab capsules list their panes' icons, card headers name the program.
extension OrielUITests {
    func testTabsShowTheirProgramsIcons() async throws {
        XCTAssertTrue(element("workspace.w2").waitForExistence(timeout: connect))
        // A workspace of its own: one three-pane tab and three one-pane tabs, each running something else.
        let created = try await Self.call(one, "workspace.create", ["label": "icons", "cwd": "/tmp", "focus": false])
        let workspace = try XCTUnwrap((created["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in _ = try? await Self.call(one, "workspace.close", ["workspace_id": workspace]) }
        let first = try XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String)
        let vim = try XCTUnwrap((created["root_pane"] as? [String: Any])?["pane_id"] as? String)
        let sleep = try await split(vim), nano = try await split(sleep)
        var tabs: [(tab: String, pane: String)] = []
        for label in ["pager", "logs", "agent"] {
            let tab = try await Self.call(one, "tab.create", ["workspace_id": workspace, "label": label,
                                                              "cwd": "/tmp", "focus": false])
            try tabs.append((XCTUnwrap((tab["tab"] as? [String: Any])?["tab_id"] as? String),
                             XCTUnwrap((tab["root_pane"] as? [String: Any])?["pane_id"] as? String)))
        }
        // Not top: it is setuid root, and herdr then sees no foreground process. macOS's nano is pico.
        let commands = [(vim, "vim", ["vim"]), (sleep, "sleep 600", ["sleep"]), (nano, "nano", ["nano", "pico"]),
                        (tabs[0].pane, "less /etc/hosts", ["less"]), (tabs[1].pane, "tail -f /dev/null", ["tail"]),
                        (tabs[2].pane, "sleep 601", ["sleep"])]
        for (pane, command, _) in commands {
            try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "\(command)\r"])
        }
        for (pane, _, names) in commands {
            try await poll("\(names) to run") { () async throws -> Bool? in
                try await foreground(pane).contains(where: names.contains) ? true : nil
            }
        }
        try await Self.call(one, "pane.report_agent", ["pane_id": tabs[2].pane, "source": "oriel-e2e",
                                                       "agent": "claude", "state": "idle"])

        // Shown for the first time: the app asks herdr what runs.
        element("workspace.\(workspace)").click()
        element("titlebar.sidebar").click()
        try await expectIcons(first) { Set($0) == ["vim", "sleep", "nano"] }
        XCTAssertTrue(element("pane.\(vim)").label.hasPrefix("vim "))
        XCTAssertTrue(element("pane.\(sleep)").label.hasPrefix("sleep "))
        // Each card asks as it shows; in the agent's tab herdr's agent wins over the process (sleep).
        for (tab, icon) in zip(tabs.map(\.tab), ["pager", "logs", "claude"]) {
            element("tab.\(tab)").click()
            try await expectIcons(tab) { $0 == [icon] }
        }
        element("tab.\(first)").click()
        XCTAssertTrue(element("pane.\(vim)").wait(for: \.isHittable, toEqual: true, timeout: 2))
        keepScreenshot("program icons")

        // Quitting vim from its card: Return asks again, and the keyboard card's icon is in front.
        element("terminal.\(vim)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(vim)")))
        app.typeText(":q")
        app.typeKey(.return, modifierFlags: [])
        try await expectIcons(first, within: 2) { $0 == ["terminal", "sleep", "nano"] }
    }

    /// Waits for the capsule's icon ids (front first) to pass `check`; polls every 100 ms (a predicate
    /// expectation checks only about once a second).
    private func expectIcons(_ tab: String, within seconds: Int = 3, _ check: ([String]) -> Bool) async throws {
        let capsule = element("tab.\(tab)")
        try await poll("\(tab)'s icons", times: seconds * 10) { () -> Bool? in
            let icons = (capsule.value as? String)?.components(separatedBy: "icons: ").last?
                .components(separatedBy: ", ")
            return icons.map(check) == true ? true : nil
        }
    }
}
