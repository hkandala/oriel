import XCTest

/// Browser panes (future-work/web-page): a herdr pane labeled `oriel:browser#<iid> <url>` with a placeholder, shown
/// as a web view card. The test pages are files a shell of the session writes (the runner is sandboxed).
extension OrielUITests {
    /// Two pages: one links to two and opens a popup that closes itself.
    func writePages(from pane: String, in session: String? = nil) async throws -> String {
        let folder = "/tmp/oriel-e2e-browser"
        try await Self.call(session ?? one, "pane.send_text", ["pane_id": pane, "text": """
        mkdir -p \(folder) && printf '<title>One</title><p>oriel-page-one</p><a href="two.html">Two</a> \
        <button onclick="window.open(\\x27pop.html\\x27)">Pop</button>' >\(folder)/one.html && \
        printf '<title>Two</title><p>oriel-page-two</p>' >\(folder)/two.html && \
        printf '<p>oriel-pop</p><button onclick="window.close()">Done</button>' >\(folder)/pop.html && clear\r
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

    /// Waits until the pane's state file on This Mac holds the address, read with `cat` in a shell of the session.
    /// A short marker, not the file: a narrow pane wraps the JSON (CI's screen), and the typed command holds no "42".
    func expectSaved(_ text: String, iid: String, shell: String, in session: String? = nil) async throws {
        let path = "~/.local/state/oriel/\(session ?? one)/browser/\(iid).json"
        try await poll("\(text) in \(path)") { () async throws -> Bool? in
            try await Self.call(session ?? one, "pane.send_text", [
                "pane_id": shell, "text": "clear; grep -q \(text) \(path) && echo saved-$((6*7))\r",
            ])
            try await Task.sleep(for: .milliseconds(200))
            return try await read(shell, in: session).contains("saved-42") ? true : nil
        }
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
        XCTAssertTrue(hasKeyboard(element("browser.\(browser).address")))
        return (browser, label)
    }

    /// The chooser's Browser makes a labeled browser pane in the pane's place, its empty address with the keyboard; a
    /// typed address loads and goes into the label; the placeholder shows in herdr. A link's page comes back after a
    /// relaunch with its history (the state file), and a click selects the address. Web Inspector docks under the page.
    /// Open Browser Here from the palette.
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
        XCTAssertTrue(element("browser.\(browser).empty").exists)
        keepScreenshot("browser card, empty")

        app.typeText(page)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(pageText("oriel-page-one").exists(within: 5))
        try await expect("the typed address in the label") { try await paneLabel(browser) == "\(made) \(page)" }
        keepScreenshot("browser card")
        // window.open: over the card, gone on window.close().
        app.webViews.buttons["Pop"].click()
        let popup = element("browser.\(browser).popup")
        XCTAssertTrue(popup.exists(within: 5))
        popup.buttons["Done"].click()
        XCTAssertTrue(popup.vanishes(within: 3))
        app.webViews.links["Two"].click()
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(browser).back").isEnabled)

        // Web Inspector, docked: the page gives it the card's lower part. WebKit docks it only in a card tall enough,
        // else it opens its own window (CI's small screen).
        let web = element("browser.\(browser)"), height = web.frame.height
        let window = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Web Inspector'")).firstMatch
        element("browser.\(browser).inspector").click()
        XCTAssertTrue(until(5) { web.frame.height < height * 0.8 || window.exists })
        keepScreenshot("web inspector")
        if window.exists {
            window.buttons[XCUIIdentifierCloseWindow].click()
        }

        // The saved address, not the label's.
        try await expectSaved("two.html", iid: String(made.dropFirst("oriel:browser#".count)), shell: left)
        relaunch()
        element("workspace.w2").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(pageText("oriel-page-two").exists(within: connect))
        let kept = try await paneLabel(browser)
        XCTAssertEqual(kept, "\(made) \(page)")
        // A click selects the address, as ⌘L does; Esc gives the page the keyboard.
        let address = element("browser.\(browser).address")
        address.click()
        XCTAssertTrue(hasKeyboard(address))
        app.typeKey(.escape, modifierFlags: [])
        // The history came back with it.
        XCTAssertTrue(element("browser.\(browser).back").has(\.isEnabled, true, within: 3))
        element("browser.\(browser).back").click()
        XCTAssertTrue(pageText("oriel-page-one").exists(within: 5))

        try await openBrowserHere(on: left, in: tab, besides: browser)
    }

    /// Open Browser Here from the palette on a terminal: a browser pane in its place. Not offered on a browser pane,
    /// where ⇧⌘R gives a shell with the chooser.
    func openBrowserHere(on left: String, in tab: String, besides browser: String) async throws {
        element("terminal.\(left)").click()
        openPalette()
        app.typeText("open browser here")
        XCTAssertTrue(element("palette.command.Open Browser Here").has(\.isSelected, true, within: 2))
        app.typeKey(.return, modifierFlags: [])
        let other = try await replaced(left, in: tab, besides: [browser])
        let otherLabel = try await paneLabel(other)
        XCTAssertTrue(otherLabel.hasPrefix("oriel:browser#"), otherLabel)
        XCTAssertTrue(hasKeyboard("browser.\(other).address"))
        // Not on a browser pane, where Open Terminal Here is.
        openPalette()
        app.typeText("here")
        XCTAssertTrue(element("palette.command.Open Terminal Here").exists(within: 2))
        XCTAssertFalse(element("palette.command.Open Browser Here").exists)
        app.typeKey(.escape, modifierFlags: [])
        // ⇧⌘R on a browser card: a shell with the chooser.
        XCTAssertTrue(hasKeyboard("browser.\(other).address"))
        app.typeKey("r", modifierFlags: [.command, .shift])
        let shell = try await replaced(other, in: tab, besides: [browser])
        XCTAssertTrue(element("pane.\(shell).chooser.terminal").exists(within: 3))
        let shellLabel = try await paneLabel(shell)
        XCTAssertEqual(shellLabel, "")
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
        // A site a machine put in a label waits for Open (future-work/web-page#when-a-page-loads-by-itself);
        // `.invalid`:
        // approvals live in the defaults the tests share with the user's Oriel.
        let site = try await id(Self.call(five, "pane.split", ["target_pane_id": pane, "direction": "down",
                                                               "cwd": "/tmp", "focus": false]), "pane")
        addTeardownBlock { _ = try? await Self.call(five, "pane.close", ["pane_id": site]) }
        try await Self.call(
            five,
            "pane.rename",
            ["pane_id": site, "label": "oriel:browser#e2e5ac https://oriel.invalid/"],
        )
        let tab: String = try await field(self.pane(pane, in: five)["tab_id"], "\(pane)'s tab")
        // The question in both appearances, for people reviewing a run.
        relaunch(five, ["-appearance", "light"])
        XCTAssertTrue(element("browser.\(site).open").exists(within: connect))
        keepScreenshot("open this page, light")
        relaunch(five, ["-appearance", "dark"])
        XCTAssertTrue(pageText("oriel-page-one").exists(within: connect))
        XCTAssertTrue(element("browser.\(site).open").exists(within: 3))
        XCTAssertEqual(element("browser.\(site).message").value as? String, "oriel.invalid/")
        keepScreenshot("open this page, dark")
        element("browser.\(site).not-now").click()
        XCTAssertTrue(element("browser.\(site).empty").exists(within: 3))
        XCTAssertFalse(element("browser.\(site).open").exists)
        // A click gives the card the keyboard; the tab (herdr's number label) takes its page's title.
        pageText("oriel-page-one").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "One", within: 3))
        // An agent changes the address with the skill's commands: a rename, then a metadata token so Oriel reads the
        // layout again (a rename sends no event). The card loads it as a new page of its history.
        let two = page.replacing("one.html", with: "two.html")
        try await Self.call(five, "pane.rename", ["pane_id": pane, "label": "oriel:browser#e2e5ab \(two)"])
        try await Self.call(five, "pane.report_metadata", ["pane_id": pane, "source": "oriel-panes",
                                                           "tokens": ["oriel-label": "1"], "ttl_ms": 1000])
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(pane).back").has(\.isEnabled, true, within: 3))
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "Two", within: 3))
        // Floated and back, the same page.
        let window = try float(pane)
        XCTAssertTrue(window.webViews.staticTexts.matching(NSPredicate(format: "value == 'oriel-page-two'")).firstMatch
            .exists(within: 3))
        keepScreenshot("floated browser", of: window)
        element("float.\(pane).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 3))
        try await expectSaved("two.html", iid: "e2e5ab", shell: shell, in: five)

        try await Self.post("\(five)/stop")
        XCTAssertTrue(element("detail.start").exists(within: 10))
        try await Self.post("\(five)/start")
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 15))
    }

    func waitForPrompt(_ pane: String, in session: String) async throws {
        try await waitFor(pane, in: session) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
