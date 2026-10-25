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

    /// The whole screen: the main window and the floating ones.
    func keepScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
