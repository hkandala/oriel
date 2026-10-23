import XCTest

/// The scenes phase 22 compares with Rex's pictures, one test per look, kept as attachments so they can be taken
/// again on CI. No pixel checks: each step waits for what the scene shows.
extension OrielUITests {
    func testScenesGlassDark() async throws {
        try await scenes("glass", "dark")
    }

    func testScenesGlassLight() async throws {
        try await scenes("glass", "light")
    }

    func testScenesClassicDark() async throws {
        try await scenes("classic", "dark")
    }

    func testScenesClassicLight() async throws {
        try await scenes("classic", "light")
    }

    /// Three splits, a zoomed card, one tab, and three tabs with a working and a blocked agent; each with the sidebar
    /// open and collapsed where Rex has both.
    private func scenes(_ style: String, _ appearance: String) async throws {
        app.terminate()
        // Rex's window (1180 × 760 pt) in the argument domain, over any frame an earlier run saved.
        app.launchArguments += ["-appearance", appearance, "-interfaceStyle", style,
                                "-NSWindow Frame main-AppWindow-1", "100 100 1180 760 0 0 1728 1084"]
        app.launch()
        let look = "\(style) \(appearance)"
        XCTAssertTrue(element("window.look").has(\.stringValue, look, within: connect))
        XCTAssertTrue(element("terminal.w1:p3").exists(within: connect))
        try await waitForPrompt("w1:p3")
        shoot("\(look) splits sidebar")
        let sidebar = element("titlebar.sidebar")
        sidebar.click()
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        shoot("\(look) splits")
        hoverHeader("w1:p2")
        element("pane.w1:p2.zoom").click()
        XCTAssertTrue(element("pane.w1:p1").vanishes(within: 2))
        shoot("\(look) zoomed")
        element("pane.w1:p2.zoom").click()
        XCTAssertTrue(element("pane.w1:p1").exists(within: 2))
        sidebar.click()

        element("workspace.w2").click()
        XCTAssertTrue(element("terminal.w2:p1").exists(within: 2))
        try await waitForPrompt("w2:p1")
        shoot("\(look) one tab sidebar")
        sidebar.click()
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        shoot("\(look) one tab")
        sidebar.click()
        // The new tabs show as `newTab` selects w2 again (a capsule added to the bar in view was not hittable).
        element("workspace.w1").click()

        let build = try await newTab("build")
        try await report(build.pane, "working")
        let agent = try await newTab("agent")
        try await report(agent.pane, "blocked", agent: "claude")
        try await waitForValue("tab.\(build.tab)", containing: "working")
        try await waitForValue("tab.\(agent.tab)", containing: "needs you")
        shoot("\(look) three tabs sidebar")
        sidebar.click()
        XCTAssertTrue(element("sidebar").vanishes(within: 2))
        shoot("\(look) three tabs")
    }

    /// With the pointer below the window, so no hover fill or header buttons show that Rex's pictures do not.
    private func shoot(_ name: String) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.1)).hover()
        // Hover fills fade out in 0.14 s.
        _ = until(0.3) { false }
        keepScreenshot(name)
    }
}
