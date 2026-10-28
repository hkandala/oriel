import XCTest

/// Browser panes (future-work/web-page): a herdr pane labeled `oriel:browser#<iid> <url>` with a placeholder, shown
/// as a web view card. The test pages are files a shell of the session writes (the runner is sandboxed).
extension OrielUITests {
    /// Two pages: one links to two.
    func writePages(from pane: String, in session: String? = nil) async throws -> String {
        let folder = "/tmp/oriel-e2e-browser"
        try await Self.call(session ?? one, "pane.send_text", ["pane_id": pane, "text": """
        mkdir -p \(folder) && printf '<title>One</title><p>oriel-page-one</p><a href="two.html">Two</a>' \
        >\(folder)/one.html && printf '<title>Two</title><p>oriel-page-two</p>' >\(folder)/two.html && clear\r
        """])
        try await waitFor(pane, in: session) { !$0.contains("printf") }
        return "file://\(folder)/one.html"
    }

    func waitFor(_ pane: String, in session: String?, _ done: @escaping (String) -> Bool) async throws {
        try await poll("\(pane)'s screen") { try await done(read(pane, in: session)) ? true : nil }
    }

    /// The page's text, in its web view.
    func pageText(_ text: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "value == %@", text)).firstMatch
    }

    func paneLabel(_ pane: String, in session: String? = nil) async throws -> String {
        try await self.pane(pane, in: session)["label"] as? String ?? ""
    }

    /// ⌘D on the pane, then 3 (Browser) in the chooser: the browser pane, labeled with no address, its address field
    /// with the keyboard. Its id and label.
    func chooseBrowser(besides left: String, in tab: String) async throws -> (pane: String, label: String) {
        app.typeKey("d", modifierFlags: .command)
        let chooser = try await replaced(left, in: tab, besides: [left])
        XCTAssertTrue(element("pane.\(chooser).chooser.browser").exists(within: 3))
        app.typeKey("3", modifierFlags: [])
        let browser = try await replaced(chooser, in: tab, besides: [left])
        let label = try await paneLabel(browser)
        XCTAssertTrue(label.hasPrefix("oriel:browser#") && !label.contains(" "), label)
        if !hasKeyboard(element("browser.\(browser).address")) {
            print("DEBUGTREE", app.windows.firstMatch.debugDescription)
            XCTFail("no keyboard")
        }
        return (browser, label)
    }

    /// The chooser's Browser makes a labeled browser pane in the pane's place, its empty address with the keyboard; a
    /// typed address loads and goes into the label; the placeholder shows in herdr. A link's page comes back after a
    /// relaunch (the state file). Web Inspector opens its window. Open Browser Here from the palette.
    func testBrowserFromTheChooserLoadsATypedAddressAndKeepsItsPage() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, left) = try await newTab("browser")
        try await waitForPrompt(left)
        let page = try await writePages(from: left)
        element("tab.\(tab)").click()
        element("terminal.\(left)").click()
        XCTAssertTrue(hasKeyboard("terminal.\(left)"))
        let (browser, made) = try await chooseBrowser(besides: left, in: tab)
        try await waitFor(browser, in: nil) { $0.contains("Browser") && $0.contains("Shown in Oriel") }
        keepScreenshot("browser card, empty")

        app.typeText(page)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(pageText("oriel-page-one").exists(within: 5))
        try await expect("the typed address in the label") { try await paneLabel(browser) == "\(made) \(page)" }
        keepScreenshot("browser card")
        app.webViews.links["Two"].click()
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(browser).back").isEnabled)

        // Web Inspector, in its own window.
        element("browser.\(browser).inspector").click()
        let inspector = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Web Inspector'")).firstMatch
        XCTAssertTrue(inspector.exists(within: 5))
        keepScreenshot("web inspector", of: inspector)
        inspector.buttons[XCUIIdentifierCloseWindow].click()

        // The saved address (500 ms after the load), not the label's.
        try await Task.sleep(for: .seconds(1))
        relaunch()
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(pageText("oriel-page-two").exists(within: connect))
        let kept = try await paneLabel(browser)
        XCTAssertEqual(kept, "\(made) \(page)")

        // Open Browser Here on the terminal.
        element("terminal.\(left)").click()
        openPalette()
        app.typeText("open browser here")
        XCTAssertTrue(element("palette.command.Open Browser Here").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let other = try await replaced(left, in: tab, besides: [browser])
        let otherLabel = try await paneLabel(other)
        XCTAssertTrue(otherLabel.hasPrefix("oriel:browser#"), otherLabel)
        XCTAssertTrue(hasKeyboard("browser.\(other).address"))
        // Not on a browser pane.
        openPalette()
        app.typeText("open browser here")
        XCTAssertFalse(element("palette.command.Open Browser Here").exists(within: 1))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A pane an agent labels with the herdr CLI shows its page; after a session stop and start (a plain shell, a new
    /// terminal id) the card comes back with the page it was on.
    func testAPaneLabeledInHerdrShowsItsPageAfterARestart() async throws {
        let five = try env("ORIEL_SESSION5")
        let (_, shell) = try await shown(running(five))
        try await waitForPrompt(shell, in: five)
        let page = try await writePages(from: shell, in: five)
        let pane = try await id(Self.call(five, "pane.split", ["target_pane_id": shell, "direction": "right",
                                                               "cwd": "/tmp", "focus": false]), "pane")
        addTeardownBlock { _ = try? await Self.call(five, "pane.close", ["pane_id": pane]) }
        try await Self.call(five, "pane.rename", ["pane_id": pane, "label": "oriel:browser#e2e5ab \(page)"])
        let tab: String = try await field(self.pane(pane, in: five)["tab_id"], "\(pane)'s tab")
        relaunch(five)
        XCTAssertTrue(pageText("oriel-page-one").exists(within: connect))
        // A click gives the card the keyboard; the tab (herdr's number label) takes its page's title.
        pageText("oriel-page-one").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "One", within: 3))
        app.webViews.links["Two"].click()
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 5))
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "Two", within: 3))
        // Floated and back, the same page.
        let window = try float(pane)
        XCTAssertTrue(window.webViews.staticTexts.matching(NSPredicate(format: "value == 'oriel-page-two'")).firstMatch
            .exists(within: 3))
        keepScreenshot("floated browser", of: window)
        element("float.\(pane).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 3))
        try await Task.sleep(for: .seconds(1))

        try await Self.post("\(five)/stop")
        XCTAssertTrue(element("detail.start").exists(within: 10))
        try await Self.post("\(five)/start")
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 15))
    }

    func waitForPrompt(_ pane: String, in session: String) async throws {
        try await waitFor(pane, in: session) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
