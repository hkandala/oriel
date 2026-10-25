import XCTest

/// Floating panes (phase 25, D50): a pane floats in its own window, its card in the tab is a placeholder.
extension OrielUITests {
    func testFloatingAPaneOpensItsWindowAndDetachPutsItBack() async throws {
        let (tab, first) = try await newTab("float")
        let second = try await split(first)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        hoverHeader(second)
        element("pane.\(second).float").click()

        let window = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        XCTAssertTrue(element("terminal.\(second)", in: window).exists(within: 3))
        XCTAssertTrue(element("pane.\(second).show").exists(within: 3))
        // herdr keeps the pane in its tab.
        try await expect("both panes in herdr's tab") { try await order(tab) == [first, second] }
        XCTAssertTrue(element("float.\(second).place").has(\.stringValue, "\(one) › beta › float", within: 3))
        keepScreen("floating window and placeholder")

        // Keys go to the floated terminal.
        window.click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)", in: window)))
        app.typeText("echo float-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(second) { $0.contains("\nfloat-42") }

        element("float.\(second).detach").click()
        XCTAssertTrue(window.vanishes(within: 3))
        XCTAssertTrue(element("pane.\(second).show").vanishes(within: 3))
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
    }

    func testFloatingWindowHasItsOwnCommandsAndComesBackAfterRelaunch() async throws {
        // As testRelaunchRestoresThePagesThatStillRun: ⌘Q saves the window.
        app.launchArguments = ["-session", one, "-NSQuitAlwaysKeepsWindows", "YES"]
        app.launch()
        let (tab, first) = try await newTab("float-keep")
        let second = try await split(first)
        element("tab.\(tab)").click()
        element("terminal.\(second)").click()
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        openPalette().typeText("float pane")
        app.typeKey(.return, modifierFlags: [])
        let window = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(window.exists(within: 5))

        // ⌘K in the floating window: its commands only, no places.
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)", in: window)))
        openPalette()
        XCTAssertTrue(element("palette.command.Detach Pane", in: window).exists(within: 2))
        XCTAssertFalse(element("palette.command.New Tab", in: window).exists)
        XCTAssertFalse(element("palette.tab.\(tab)", in: window).exists)
        app.typeText("stay on top")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 2))
        keepScreen("floating window on top")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launchArguments = ["-defaultSession", one]
        app.launch()
        let back = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(back.exists(within: connect))
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 3))
        XCTAssertTrue(element("pane.\(second).show").exists(within: 3))

        // herdr closed the pane: its window closes.
        try await Self.call(one, "pane.close", ["pane_id": second])
        XCTAssertTrue(back.vanishes(within: 5))
    }

    func testClosingAFloatedPaneAsksInItsWindow() async throws {
        let (tab, first) = try await newTab("float-close")
        let second = try await split(first)
        try await runSleep(second)
        element("tab.\(tab)").click()
        hoverHeader(second)
        element("pane.\(second).float").click()
        let window = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        element("float.\(second).close").click()
        let confirm = window.sheets.buttons["Close Pane"]
        XCTAssertTrue(confirm.exists(within: 5))
        confirm.click()
        XCTAssertTrue(window.vanishes(within: 5))
        try await expect("the pane closed in herdr") { try await order(tab) == [first] }
    }

    /// The whole screen: the main window and the floating ones.
    func keepScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
