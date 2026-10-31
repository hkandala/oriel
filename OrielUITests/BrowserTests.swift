import XCTest

/// Browser panes (ui/browser): a herdr pane labeled `oriel:browser#<iid> <url>` with a placeholder, shown
/// as a web view card. The test pages are files a shell of the session writes (the runner is sandboxed).
extension OrielUITests {
    /// Two pages: one links to two (also in a new window) and opens a popup that closes itself.
    func writePages(from pane: String, in session: String? = nil) async throws -> String {
        let folder = "/tmp/oriel-e2e-browser"
        try await Self.call(session ?? one, "pane.send_text", ["pane_id": pane, "text": """
        mkdir -p \(folder) && printf '<title>One</title><link rel="icon" href="data:image/svg+xml,<svg \
        xmlns=%%22http://www.w3.org/2000/svg%%22 \
        viewBox=%%220 0 16 16%%22><rect width=%%2216%%22 height=%%2216%%22/></svg>"> \
        <p>oriel-page-one</p><a href="two.html">Two</a> <a href="two.html" target="_blank">Blank</a> \
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
        // Its `<link rel=icon>`, a `data:` SVG with spaces and escapes.
        XCTAssertTrue(element("browser.\(browser).icon").has(\.stringValue, "page", within: 5))
        try await expect("the typed address in the label") { try await paneLabel(browser) == "\(made) \(page)" }
        keepScreenshot("browser card")
        // window.open: over the card, gone on window.close().
        app.webViews.buttons["Pop"].click()
        let popup = element("browser.\(browser).popup")
        // Over the accessibility timeout (6 s), as in testLinksOpenInNewTabsAndPopupsClose.
        XCTAssertTrue(popup.exists(within: 10))
        popup.buttons["Done"].click()
        XCTAssertTrue(popup.vanishes(within: 3))
        app.webViews.links["Two"].click()
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(browser).back").isEnabled)

        showInspector(browser)

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

    /// A link opens in a new tab, in the background, from the page's menu (which has no New Window or download items),
    /// by ⌘-click and as a `target=_blank` link: each a browser pane on two.html. A `window.open` popup stays over the
    /// card and closes by Esc and by its close button.
    func testLinksOpenInNewTabsAndPopupsClose() async throws {
        let (tab, shell) = try await newTab("links")
        try await waitForPrompt(shell)
        let page = try await writePages(from: shell)
        let pane = try await split(shell)
        try await Self.call(one, "pane.rename", ["pane_id": pane, "label": "oriel:browser#e2e1ab \(page)"])
        try await Self.call(one, "pane.report_metadata", ["pane_id": pane, "source": "oriel-panes",
                                                          "tokens": ["oriel-label": "1"], "ttl_ms": 1000])
        element("tab.\(tab)").click()
        XCTAssertTrue(pageText("oriel-page-one").exists(within: 5))
        let two = page.replacing("one.html", with: "two.html")
        var tabs = try await tabIDs()
        func expectTab(_ how: String) async throws {
            let new = try await newTabID(after: tabs)
            closeAfter("tab", new)
            tabs.append(new)
            let pane = try await self.pane(of: new)
            try await expect("\(how): two.html in \(new)") {
                let label = try await paneLabel(pane)
                return label.hasPrefix("oriel:browser#") && label.hasSuffix(" \(two)")
            }
            XCTAssertTrue(element("tab.\(tab)").isSelected, how)
            XCTAssertTrue(pageText("oriel-page-one").exists, how)
        }

        app.webViews.links["Two"].rightClick()
        let menu = app.windows.firstMatch.menuItems
        XCTAssertTrue(menu["Open Link in New Tab"].exists(within: 2))
        XCTAssertFalse(menu["Open Link in New Window"].exists)
        XCTAssertFalse(menu["Download Linked File"].exists)
        keepScreenshot("page menu")
        menu["Open Link in New Tab"].click()
        try await expectTab("the menu")
        XCUIElement.perform(withKeyModifiers: .command) { app.webViews.links["Two"].click() }
        try await expectTab("⌘-click")
        app.webViews.links["Blank"].click()
        try await expectTab("target=_blank")

        // Over 6 s: an accessibility query that reaches the popup's web view as it starts can wait out the
        // accessibility timeout (6 s; CI took 6.1 s), and the popup draws only after it.
        let popup = element("browser.\(pane).popup")
        app.webViews.buttons["Pop"].click()
        XCTAssertTrue(popup.exists(within: 10))
        keepScreenshot("popup")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(popup.vanishes(within: 3))
        app.webViews.buttons["Pop"].click()
        XCTAssertTrue(popup.exists(within: 10))
        element("browser.\(pane).card").buttons["Close"].click()
        XCTAssertTrue(popup.vanishes(within: 3))
    }

    /// Web Inspector, docked: the page gives it the card's lower part, also after the card changes size.
    func showInspector(_ browser: String) {
        let web = element("browser.\(browser)"), height = web.frame.height, top = web.frame.minY
        let window = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Web Inspector'")).firstMatch
        element("browser.\(browser).inspector").click()
        // Under the page: the page keeps its top.
        XCTAssertTrue(until(5) { web.frame.height < height * 0.8 && abs(web.frame.minY - top) < 1 || window.exists })
        keepScreenshot("web inspector")
        if window.exists {
            window.buttons[XCUIIdentifierCloseWindow].click()
        } else {
            // Docked, it stays under the page as the card changes size: the page keeps its inset.
            let card = element("browser.\(browser).card"), before = card.frame.width
            let inset = before - web.frame.width
            element("titlebar.sidebar").click()
            XCTAssertTrue(until(3) {
                card.frame.width > before && abs(card.frame.width - web.frame.width - inset) < 1
                    && web.frame.height < card.frame.height * 0.8 && abs(web.frame.minY - top) < 1
            }, "\(web.frame) in \(card.frame)")
            element("titlebar.sidebar").click()
        }
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
        // A site a machine put in a label waits for Open (ui/browser#when-a-page-loads-by-itself);
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
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "Browser One", within: 3))
        XCTAssertTrue(twoRows(pane, title: "One", above: "browser.\(pane).address"))
        // An agent changes the address with the skill's commands: a rename, then a metadata token so Oriel reads the
        // layout again (a rename sends no event). The card loads it as a new page of its history.
        let two = page.replacing("one.html", with: "two.html")
        try await Self.call(five, "pane.rename", ["pane_id": pane, "label": "oriel:browser#e2e5ab \(two)"])
        try await Self.call(five, "pane.report_metadata", ["pane_id": pane, "source": "oriel-panes",
                                                           "tokens": ["oriel-label": "1"], "ttl_ms": 1000])
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 5))
        XCTAssertTrue(element("browser.\(pane).back").has(\.isEnabled, true, within: 3))
        XCTAssertTrue(element("tab.\(tab)").has(\.label, "Browser Two", within: 3))
        try floatAndBack(pane)
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 3))
        try await expectSaved("two.html", iid: "e2e5ab", shell: shell, in: five)

        try await Self.post("\(five)/stop")
        XCTAssertTrue(element("detail.start").exists(within: 10))
        try await Self.post("\(five)/start")
        XCTAssertTrue(pageText("oriel-page-two").exists(within: 15))
    }

    /// Floated and back, the same page. The window's title row has no place: the tab's title is the shell's.
    func floatAndBack(_ pane: String) throws {
        let window = try float(pane)
        XCTAssertTrue(window.webViews.staticTexts.matching(NSPredicate(format: "value == 'oriel-page-two'")).firstMatch
            .exists(within: 3))
        keepScreenshot("floated browser", of: window)
        XCTAssertFalse(element("float.\(pane).place", in: window).exists)
        element("float.\(pane).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
    }

    /// A browser's or an agent's header: row 1's title (any when nil), and row 2's `control` under it.
    func twoRows(_ pane: String, title: String? = nil, above control: String) -> Bool {
        let row1 = element("pane.\(pane).title")
        return title.map { row1.stringValue == $0 } != false && element(control).frame.minY >= row1.frame.maxY
    }

    func waitForPrompt(_ pane: String, in session: String) async throws {
        try await waitFor(pane, in: session) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

extension OrielUITests {
    /// Past the kept web cards (`-spareWebCards 0`), a browser's card is dropped as its tab hides and keeps its
    /// picture: its overview tile shows the page, and the card comes back from its label when shown (the page loads
    /// again: its title, stamped as it loads, is a new one).
    func testADroppedBrowserKeepsItsPictureAndComesBack() async throws {
        relaunch(nil, ["-spareWebCards", "0"])
        let (tab, pane) = try await newTab("dropped")
        try await waitForPrompt(pane)
        let folder = "/tmp/oriel-e2e-dropped"
        try await send("mkdir -p \(folder) && printf '<script>document.title = \\x27Light \\x27 + Date.now()</script>' "
            + ">\(folder)/light.html && clear\r", to: pane)
        try await waitFor(pane) { !$0.contains("printf") }
        let iid = String(format: "e2e%03x", Int.random(in: 0 ..< 4096)), title = element("pane.\(pane).title")
        try await Self.call(
            one,
            "pane.rename",
            ["pane_id": pane, "label": "oriel:browser#\(iid) file://\(folder)/light.html"],
        )
        XCTAssertTrue(until(connect) { title.stringValue.hasPrefix("Light ") }, title.stringValue)
        let first = title.stringValue
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, false, within: 3))
        app.typeKey("o", modifierFlags: [.command, .control])
        let tile = element("overview.card.\(pane)")
        XCTAssertTrue(tile.has(\.stringValue, "browser", within: 3), tile.stringValue)
        scrollOverview(to: tile, whole: true)
        XCTAssertGreaterThan(mean(tile), 150, "the dropped page's picture")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 2))
        try await show(tab)
        XCTAssertTrue(until(connect) { title.stringValue.hasPrefix("Light ") && title.stringValue != first },
                      "\(first) then \(title.stringValue)")
    }
}
