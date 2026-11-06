import XCTest

/// The Git diff's keys (phase 56): ] and [ step through the changes, from the top of the view after a scroll, and ⌘F's
/// find bar filters the files by path.
extension OvviUITests {
    /// In a working tree that changes a.txt's lines 10, 200 and 290 and adds b.md: ] steps to each change, [ back;
    /// after
    /// a scroll to the top, ] goes to the first change there, not past the last one stepped to. ⌘F filters the files;
    /// Esc closes the bar and shows them all again.
    func testGitDiffStepsWithBracketsAndFilters() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("git-keys")
        try await waitForPrompt(left)
        let repo = "/tmp/ovvi-e2e-git-keys", root = "/private/tmp/ovvi-e2e-git-keys"
        try await send("rm -rf \(repo) && mkdir \(repo) && cd \(repo) && git init -q -b main "
            + "&& git config user.name e2e && git config user.email e2e@ovvi && git config commit.gpgsign false "
            + "&& seq 300 | sed 's/^/line /' >a.txt && git add a.txt && git commit -qm first "
            + "&& sed -i '' 's/^line 10$/ten/; s/^line 200$/far200/; s/^line 290$/far290/' a.txt && echo new >b.md "
            + "&& clear && echo ready-$((6*7))\r", to: left)
        try await waitFor(left) { $0.contains("ready-42") }
        try await show(tab)
        let card = try await split(left)
        try await Self.call(one, "pane.rename", ["pane_id": card, "label": "ovvi:git#e2ekey \(root)/ uncommitted"])
        let page = element("git.\(card).page")
        let line = { (text: String) in page.staticTexts.matching(NSPredicate(format: "value == %@", text)).firstMatch }
        // The first card of a run waits for the default plugins to install and build.
        XCTAssertTrue(line("ten").has(\.isHittable, true, within: 30))

        // A click gives the page the keyboard.
        line("ten").click()
        for _ in 0 ..< 3 {
            app.typeKey("]", modifierFlags: [])
        }
        XCTAssertTrue(line("far290").has(\.isHittable, true, within: 3))
        app.typeKey("[", modifierFlags: [])
        XCTAssertTrue(line("far200").has(\.isHittable, true, within: 3))
        page.scroll(byDeltaX: 0, deltaY: 100_000)
        XCTAssertTrue(line("ten").has(\.isHittable, true, within: 3))
        app.typeKey("]", modifierFlags: [])
        XCTAssertFalse(until(0.5) { !line("ten").isHittable }, "] left the first change")
        app.typeKey("]", modifierFlags: [])
        XCTAssertTrue(line("far200").has(\.isHittable, true, within: 3))

        app.typeKey("f", modifierFlags: .command)
        let field = page.textFields["Filter"]
        XCTAssertTrue(field.exists(within: 3))
        app.typeText("B.M")
        XCTAssertTrue(page.buttons["Open a.txt"].vanishes(within: 3))
        XCTAssertTrue(page.buttons["Open b.md"].exists)
        keepScreenshot("git diff filter")
        app.typeText("x")
        XCTAssertTrue(line("No matching files").exists(within: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.vanishes(within: 3))
        XCTAssertTrue(page.buttons["Open a.txt"].exists(within: 3))
        try await send("cd / && rm -rf \(repo)\r", to: left)
    }
}
