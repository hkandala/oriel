import XCTest

/// Floating panes (phase 25, D50): a pane floats in its own window, its card in the tab is a placeholder.
extension OrielUITests {
    func testFloatingAPaneOpensItsWindowAndDetachPutsItBack() async throws {
        let (tab, first) = try await newTab("float")
        let second = try await split(first)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        let window = try float(second)
        XCTAssertTrue(element("terminal.\(second)", in: window).exists(within: 3))
        XCTAssertTrue(element("pane.\(second).show").exists(within: 3))
        // herdr keeps the pane in its tab.
        try await expect("both panes in herdr's tab") { try await order(tab) == [first, second] }
        XCTAssertTrue(element("float.\(second).place").has(\.stringValue, "\(one) › beta › float", within: 3))

        // The main window's keyboard card is never the placeholder, also on ⌘].
        element("tab.\(tab)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))
        XCTAssertTrue(window.exists)

        // The main window covers it now; Show brings it forward with the keyboard, and keys go there.
        element("pane.\(second).show").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)", in: window)))
        app.typeText("echo float-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(second) { $0.contains("\nfloat-42") }

        element("float.\(second).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(element("pane.\(second).show").vanishes(within: 3))
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
    }

    /// A new floating window: 60 % of the main window's width and 75 % of its height (at least 720 × 460 pt) centered
    /// over it, the main window's title row and traffic lights, title-row buttons, a separator between the pane's info
    /// and its place (phases 27, 28); the card in the tab says where the pane is and offers Show Pane (phase 28).
    func testFloatingWindowOpensLargeWithTheMainWindowsTitleRow() async throws {
        let (tab, first) = try await newTab("float-frame")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let main = app.windows.containing(.any, identifier: "tab.\(tab)").firstMatch.frame
        let window = try float(second)
        let frame = window.frame, frames = "\(frame) over \(main)"
        XCTAssertEqual(frame.width, max(720, main.width * 0.6), accuracy: 2, frames)
        XCTAssertEqual(frame.height, max(460, main.height * 0.75), accuracy: 2, frames)
        XCTAssertEqual(frame.midX, main.midX, accuracy: 2, frames)
        XCTAssertEqual(frame.midY, main.midY, accuracy: 2, frames)

        // The lights where the main window has them (testTrafficLightsSitInTheTitleRow); the 28 pt buttons centered
        // on the same 46 pt row.
        let lights = [XCUIIdentifierCloseWindow, XCUIIdentifierMinimizeWindow, XCUIIdentifierFullScreenWindow]
            .map { window.buttons[$0] }
        XCTAssertTrue(until(2) {
            lights.enumerated().allSatisfy { index, light in
                abs(light.frame.minX - frame.minX - (15 + CGFloat(index) * 23)) < 1
                    && abs(light.frame.minY - frame.minY - 15) < 1
            }
        }, "\(lights.map(\.frame)) in \(frame)")
        for button in ["pin", "close", "detach"] {
            let button = element("float.\(second).\(button)").frame
            XCTAssertEqual(button.height, 28, accuracy: 0.5, "\(button)")
            XCTAssertEqual(button.midY - frame.minY, 23, accuracy: 1, "\(button) in \(frame)")
        }

        // The pane's program and folder in the title row, then a 1 pt separator 8 pt from each, then its place.
        let info = element("float.\(second).info", in: window)
        XCTAssertTrue(info.stringValue.hasSuffix("tmp"), info.debugDescription)
        let place = element("float.\(second).place", in: window).frame
        XCTAssertEqual(place.minX - info.frame.maxX, 2 * 8 + 1, accuracy: 1, "\(place) after \(info.frame)")

        // In the tab, under the card's header: a line that says where the pane is, and Show Pane in the middle.
        element("tab.\(tab)").click()
        let show = element("pane.\(second).show"), card = element("pane.\(second)").frame
        XCTAssertTrue(show.exists(within: 3))
        XCTAssertEqual(show.label, "Show Pane")
        XCTAssertEqual(element("pane.\(second).floating").stringValue, "This pane is open in a floating window.")
        XCTAssertEqual(show.frame.midX, card.midX, accuracy: 1, "\(show.frame) in \(card)")
        XCTAssertLessThan(show.frame.width, card.width / 2, "\(show.frame) in \(card)")
        keepScreen("floating window over the main window")
        show.click()
        // Not through `window`: XCUITest dropped that element once the window came forward (CI 40196255503). The
        // card in the tab has no terminal, so this one is the floating window's.
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
    }

    /// Two floating windows, one on top, its own ⌘K, and both back after ⌘Q and a relaunch.
    func testFloatingWindowsHaveTheirOwnCommandsAndComeBackAfterRelaunch() async throws {
        // As testRelaunchRestoresThePagesThatStillRun: ⌘Q saves the window.
        app.launchArguments = ["-session", one, "-NSQuitAlwaysKeepsWindows", "YES"]
        app.launch()
        let (tab, first) = try await newTab("float-keep")
        let second = try await split(first), third = try await split(second)
        element("tab.\(tab)").click()
        // Each through the palette, on the keyboard card: no floating window covers a card's header then.
        element("terminal.\(third)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(third)")))
        openPalette().typeText("float pane")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("float.\(third)").exists(within: 5))
        // Back in the main window, ⌘[ round the start skips the floated last card.
        element("tab.\(tab)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(first)")))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        openPalette().typeText("float pane")
        app.typeKey(.return, modifierFlags: [])
        let pinned = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(pinned.exists(within: 5))

        // ⌘K in the floating window: its commands only, no places.
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)", in: pinned)))
        openPalette()
        XCTAssertTrue(element("palette.command.Detach Pane", in: pinned).exists(within: 2))
        XCTAssertFalse(element("palette.command.New Tab", in: pinned).exists)
        XCTAssertFalse(element("palette.tab.\(tab)", in: pinned).exists)
        app.typeText("stay on top")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 2))
        XCTAssertTrue(element("float.\(third).pin").has(\.stringValue, "off", within: 2))
        keepScreen("two floating windows, one on top")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launchArguments = ["-defaultSession", one]
        app.launch()
        let back = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(back.exists(within: connect))
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 3))
        XCTAssertTrue(element("float.\(third).pin").has(\.stringValue, "off", within: 3))
        XCTAssertTrue(element("pane.\(second).show").exists(within: 3))
        XCTAssertTrue(element("pane.\(third).show").exists)

        // herdr closed a pane: its window closes, the other stays.
        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(back.vanishes(within: 5))
        XCTAssertTrue(element("float.\(third)").exists)
        // ⇧⌘W in a floating window detaches. Show Pane is under the floating window until the main one is in front.
        element("tab.\(tab)").click()
        element("pane.\(third).show").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(third)", in: app.windows.containing(.any, identifier:
            "float.\(third)").firstMatch)))
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(element("float.\(third)").vanishes(within: 3))
        XCTAssertTrue(element("pane.\(third).show").vanishes(within: 3))
    }

    func testClosingAFloatedPaneAsksInItsWindow() async throws {
        let (tab, first) = try await newTab("float-close")
        let second = try await split(first)
        try await runSleep(second)
        element("tab.\(tab)").click()
        let window = try float(second)
        element("float.\(second).close").click()
        let confirm = window.sheets.buttons["Close Pane"]
        XCTAssertTrue(confirm.exists(within: 5))
        confirm.click()
        XCTAssertTrue(window.vanishes(within: 5))
        try await expect("the pane closed in herdr") { try await order(tab) == [first] }

        // Closing the main window closes its floating windows.
        let alone = try float(first)
        element("tab.\(tab)").click()
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Close Window"].click()
        XCTAssertTrue(alone.vanishes(within: 5))
    }

    /// A floating window on top over the main window, in Glass and Classic, dark and light.
    func testFloatingWindowInEachLook() async throws {
        let (tab, first) = try await newTab("float-look")
        let second = try await split(first)
        element("tab.\(tab)").click()
        let window = try float(second)
        element("float.\(second).pin").click()
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 2))
        // The main window's menu bar has the looks; the window on top stays in view.
        element("tab.\(tab)").click()
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        for (menu, item, look) in [("Interface Style", "Glass", "glass dark"), ("Appearance", "Light", "glass light"),
                                   ("Interface Style", "Classic", "classic light"),
                                   ("Appearance", "Dark", "classic dark")]
        {
            pick(menu, item)
            XCTAssertTrue(element("window.look").has(\.stringValue, look, within: 3))
            XCTAssertTrue(window.isHittable)
            keepScreen("floating window, \(look)")
        }
        // The red traffic light detaches.
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
    }

    /// `oriel://float` (phase 28, pi-herd's agents): a pane of a session with no page here floats, and no page comes;
    /// again brings the same window forward; a pane or session that is not there says so; Detach lets the session go.
    /// A page's pane in a tab not in view floats too.
    func testOrielURLFloatsAPaneOfASessionWithNoPage() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        // Two's gamma; one has a w1:p1 too, so always within the floating window.
        let pane = "w1:p1"
        let window = try await floatByURL(two, pane)
        XCTAssertTrue(until(3) { element("float.\(pane).place", in: window).stringValue.hasPrefix("\(two) › gamma › ")
        })
        XCTAssertFalse(element("sidebar.dot.\(two)").exists)
        app.typeText("echo url-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await expect("the keys in two's pane") {
            let read = try await Self.call(two, "pane.read", ["pane_id": pane, "source": "visible"])["read"]
            return ((read as? [String: Any])?["text"] as? String)?.contains("\nurl-42") == true
        }

        // Again, with the main window in front: the same window comes forward.
        element("workspace.w1").click()
        _ = try await floatByURL(two, pane)
        XCTAssertEqual(app.windows.containing(.any, identifier: "float.\(pane)").count, 1)

        // Not there: a notice in the main window, no window.
        element("workspace.w1").click()
        try await openFloatURL("session=\(two)&pane=w9:p9")
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts["Can't float pane w9:p9 of \(two): no such pane."].exists(within: 5))
        XCTAssertFalse(element("float.w9:p9").exists)
        try await openFloatURL("session=oriel-e2e-none&pane=\(pane)")
        let none = NSPredicate(format: "value BEGINSWITH %@", "Can't float pane \(pane) of oriel-e2e-none: ")
        XCTAssertTrue(notice.staticTexts.matching(none).firstMatch.exists(within: connect))
        XCTAssertFalse(element("sidebar.dot.oriel-e2e-none").exists)

        // Detach: the window goes, and so does two's connection. The URL brings the window forward first: a click on a
        // window behind the main one lands in the main one.
        _ = try await floatByURL(two, pane)
        element("float.\(pane).detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
        try await expect("two's herdr runs end") { try await runs(two).isEmpty }

        // A page's pane, in a workspace not in view.
        let (tab, other) = try await newTab("float-url")
        element("workspace.w1").click()
        XCTAssertTrue(element("tab.\(tab)").vanishes(within: 3))
        _ = try await floatByURL(one, other)
    }

    /// Closing the main window lets a URL float and its session go; a URL with no window opens one and floats there.
    /// Open Session on the float's session makes it a page: the window stays, and after Detach the page keeps the
    /// connection.
    func testOrielURLFloatGoesWithItsWindowAndOpensOne() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let pane = "w1:p1"
        let window = try await floatByURL(two, pane)
        element("workspace.w1").click()
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Close Window"].click()
        XCTAssertTrue(window.vanishes(within: 5))
        try await expect("two's herdr runs end") { try await runs(two).isEmpty }

        _ = try await floatByURL(two, pane)
        XCTAssertTrue(element("workspace.w1").exists(within: connect))

        element("workspace.w1").click()
        openSessionPanel()
        app.typeText(two)
        element("open-session.session.\(two)").click()
        XCTAssertTrue(element("sidebar.dot.\(two)").exists(within: 3))
        XCTAssertTrue(window.exists)
        _ = try await floatByURL(two, pane)
        element("float.\(pane).detach", in: window).click()
        XCTAssertTrue(window.vanishes(within: 3))
        let left = try await runs(two)
        XCTAssertFalse(left.isEmpty)
    }

    /// `open -g` of the pane's `oriel://float` URL with the app under test, through the helper, as pi-herd opens it
    /// (XCUIApplication.open(_:) left the app not foreground for XCUITest, CI 40247366831); its floating window, once
    /// its terminal has the keyboard.
    func floatByURL(_ session: String, _ pane: String) async throws -> XCUIElement {
        try await openFloatURL("session=\(session)&pane=\(pane)")
        let window = app.windows.containing(.any, identifier: "float.\(pane)").firstMatch
        XCTAssertTrue(window.exists(within: connect))
        XCTAssertTrue(hasKeyboard(element("terminal.\(pane)", in: window)))
        return window
    }

    func openFloatURL(_ query: String) async throws {
        let oriel = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Oriel.app").path
        _ = try await Self.post("\(one)/open-url", Data("\(oriel)\noriel://float?\(query)".utf8))
    }

    /// The card's Float button; its window, once it shows.
    func float(_ pane: String) throws -> XCUIElement {
        hoverHeader(pane)
        element("pane.\(pane).float").click()
        let window = app.windows.containing(.any, identifier: "float.\(pane)").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        return window
    }

    /// The whole screen: the main window and the floating ones.
    func keepScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
