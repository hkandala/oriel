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

    /// The traffic lights sit where Rex's do, centered on the 46 pt title row, also after a zoom (AppKit lays them out
    /// again then); in full screen the row starts 8 pt in.
    func testTrafficLightsSitInTheTitleRow() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        let window = app.windows.firstMatch
        let lights = [XCUIIdentifierCloseWindow, XCUIIdentifierMinimizeWindow, XCUIIdentifierFullScreenWindow]
            .map { window.buttons[$0] }
        func placed() -> Bool {
            lights.enumerated().allSatisfy { index, light in
                // Rex's accessibility frames: 16 pt at x 15, 38, 61 and y 15.
                abs(light.frame.minX - window.frame.minX - (15 + CGFloat(index) * 23)) < 1
                    && abs(light.frame.minY - window.frame.minY - 15) < 1
            }
        }
        XCTAssertTrue(until(2, placed), "\(lights.map(\.frame)) in \(window.frame)")
        // ⌥-click zooms (a click goes full screen), and again back.
        // Each zoom settles before the next click: one during the animation zoomed to a frame wider than the screen.
        // CI's window nearly fills the screen, so a zoom may change little or nothing.
        for _ in 0 ..< 2 {
            var frame = window.frame
            XCUIElement.perform(withKeyModifiers: .option) { lights[2].click() }
            _ = until(1) { window.frame != frame }
            XCTAssertTrue(until(3) {
                defer { frame = window.frame }
                return window.frame == frame
            })
            XCTAssertTrue(placed(), "\(lights.map(\.frame)) in \(window.frame)")
        }
        keepScreenshot("traffic lights")
        // Leaving full screen is not checked: a second ⌃⌘F during the animation is lost on CI.
        app.typeKey("f", modifierFlags: [.control, .command])
        let toggle = element("titlebar.sidebar")
        XCTAssertTrue(until(5) { abs(toggle.frame.minX - window.frame.minX - 8) < 1 })
    }

    /// Workspace and tab switches draw no frame with a traffic light off its place (the user saw them flicker; CI's
    /// recording showed the zoom button 4 pt off for 1 to 4 frames).
    func testTrafficLightsStayStillWhenWorkspacesSwitch() {
        relaunch(one, ["-recordLights", "YES"])
        let lights = element("window.lights")
        XCTAssertTrue(element("pane.w1:p1").exists(within: connect))
        let launched = lights.stringValue
        for (row, pane) in [("w2", "w2:p1"), ("w1", "w1:p1"), ("w2", "w2:p1"), ("w1", "w1:p1")] {
            element("workspace.\(row)").click()
            XCTAssertTrue(element("pane.\(pane)").has(\.isHittable, true, within: 2))
        }
        element("tab.w1:t2").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        element("tab.w1:t1").click()
        XCTAssertTrue(element("pane.w1:p1").has(\.isHittable, true, within: 2))
        // ponytail: launch itself may draw one such turn (1 of 4 CI runs); the user saw it on switches.
        XCTAssertEqual(lights.stringValue, launched, "turns drawn with a light off its place")
    }

    /// Three splits, a zoomed card, one tab, and three tabs with a working and a blocked agent; each with the sidebar
    /// open and collapsed where Rex has both.
    private func scenes(_ style: String, _ appearance: String) async throws {
        // Rex's window (1180 × 760 pt) in the argument domain, over any frame an earlier run saved.
        relaunch(one, ["-appearance", appearance, "-interfaceStyle", style,
                       "-NSWindow Frame main-AppWindow-1", "100 100 1180 760 0 0 1728 1084"])
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
        Thread.sleep(forTimeInterval: 0.3)
        keepScreenshot(name)
    }
}
