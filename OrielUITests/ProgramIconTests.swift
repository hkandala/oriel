import XCTest

/// Program icons (phase 12): tab capsules list their panes' icons, card headers name the program.
extension OrielUITests {
    func testTabsShowTheirProgramsIcons() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        // A workspace of its own: one three-pane tab and three one-pane tabs, each running something else.
        let (first, vim) = try await createWorkspace("icons")
        let workspace = workspace(of: first)
        let sleep = try await split(vim), nano = try await split(sleep)
        var tabs: [(tab: String, pane: String)] = []
        for label in ["pager", "logs", "agent"] {
            try await tabs.append(createTab(in: workspace, label: label))
        }
        // Not top: it is setuid root, and herdr then sees no foreground process. macOS's nano is pico.
        let commands = [(vim, "vim", ["vim"]), (sleep, "sleep 600", ["sleep"]), (nano, "nano", ["nano", "pico"]),
                        (tabs[0].pane, "less /etc/hosts", ["less"]), (tabs[1].pane, "tail -f /dev/null", ["tail"]),
                        (tabs[2].pane, "sleep 601", ["sleep"])]
        for (pane, command, _) in commands {
            try await send("\(command)\r", to: pane)
        }
        for (pane, _, names) in commands {
            try await expect("\(names) to run") { try await foreground(pane).contains(where: names.contains) }
        }
        try await report(tabs[2].pane, "idle", agent: "claude")

        // Shown for the first time: the app asks herdr what runs.
        element("workspace.\(workspace)").click()
        element("titlebar.sidebar").click()
        // New panes: up to 4 s until only a program, not the shell's startup, runs.
        try await expectIcons(first, within: 6) { Set($0) == ["vim", "sleep", "nano"] }
        XCTAssertTrue(element("pane.\(vim)").label.hasPrefix("vim "))
        XCTAssertTrue(element("pane.\(sleep)").label.hasPrefix("sleep "))
        // Each card asks as it shows; in the agent's tab herdr's agent wins over the process (sleep). Keys, not clicks:
        // the fourth tab is past the row's end on CI's window.
        for (index, (tab, icon)) in zip(tabs.map(\.tab), ["pager", "logs", "claude"]).enumerated() {
            app.typeKey("\(index + 2)", modifierFlags: .command)
            try await expectIcons(tab) { $0 == [icon] }
        }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("pane.\(vim)").has(\.isHittable, true, within: 2))
        keepScreenshot("program icons")

        // Quitting vim from its card: Return asks again, and the keyboard card's icon is in front.
        element("terminal.\(vim)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(vim)"))
        app.typeText(":q")
        app.typeKey(.return, modifierFlags: [])
        try await expectIcons(first, within: 2) { $0 == ["terminal", "sleep", "nano"] }
    }

    /// A shell's startup runs short-lived programs (a .zshrc's `gh auth token`): the new tab's icon is the shell's
    /// from the start, not theirs for a moment (phase 24).
    func testANewTabShowsNoIconOfItsShellsStartup() async throws {
        let (tabs, pane) = try await newWorkspace("startup")
        // A home whose rc files sleep 2 s, past the first second, for zsh and bash, written by a shell.
        let home = "/tmp/\(one)-startup"
        try await send("mkdir -p \(home) && echo 'sleep 2' | tee \(home)/.zshrc \(home)/.bashrc > \(home)/.bash_profile"
            + " && echo rc-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("\nrc-42") }
        let created = try await Self.call(one, "tab.create", ["workspace_id": workspace(of: tabs[0]), "cwd": "/tmp",
                                                              "env": ["HOME": home, "ZDOTDIR": home], "focus": false])
        let tab = try id(created, "tab"), capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.exists(within: 2))
        // Shown at once: its card asks as it shows.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(capsule.has(\.isSelected, true, within: 1))
        let running = try await foreground(id(created, "root_pane"))
        XCTAssertTrue(running.contains("sleep"), "the startup ended before the card showed: \(running)")
        XCTAssertFalse(until(2) { (capsule.value as? String)?.contains("sleep") == true }, "the startup's icon")
        try await expectIcons(tab) { $0 == ["terminal"] }
    }

    /// A program without a logo shows its letter in the logos' square, so the names after them line up (phase 29).
    func testLetterIconsTakeTheLogosBox() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, vim) = try await createWorkspace("letters")
        let cat = try await split(vim)
        // vim has a logo; cat is not in the catalog, so it shows "C".
        try await send("vim\r", to: vim)
        try await send("cat\r", to: cat)
        for (pane, name) in [(vim, "vim"), (cat, "cat")] {
            try await expect("\(name) to run") { try await foreground(pane).contains(name) }
        }
        // Shown after they run, so the cards ask herdr what runs as they show (as above).
        element("workspace.\(workspace(of: tab))").click()
        try await expectIcons(tab, within: 6) { Set($0) == ["vim", "placeholder"] }
        XCTAssertTrue(element("pane.\(cat).title").exists(within: 2))
        keepScreenshot("logo and letter")
        // Where each header's name starts in its card: the same with a letter as with a logo.
        let starts = [vim, cat].map { element("pane.\($0).title").frame.minX - element("pane.\($0)").frame.minX }
        XCTAssertEqual(starts[0], starts[1])
    }

    /// Waits for the capsule's icon ids (front first) to pass `check`.
    private func expectIcons(_ tab: String, within seconds: Int = 3, _ check: ([String]) -> Bool) async throws {
        let capsule = element("tab.\(tab)")
        try await expect("\(tab)'s icons", times: seconds * 10) {
            let icons = (capsule.value as? String)?.components(separatedBy: "icons: ").last?
                .components(separatedBy: ", ")
            return icons.map(check) == true
        }
    }
}
