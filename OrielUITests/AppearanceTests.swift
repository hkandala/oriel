import XCTest

/// Appearance and interface style (phase 10). The window's `window.look` element says which look it draws, from
/// the effective appearance and the style setting.
extension OrielUITests {
    /// View ▸ Appearance and View ▸ Interface Style switch the look, with a screenshot of each of the four.
    func testMenuSwitchesTheLook() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        // Settings persist (in the app's own defaults): start from the defaults whatever an earlier run left, and
        // go back to them even when a step fails.
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        let steps = [("Appearance", "Dark", "glass dark"), ("Appearance", "Light", "glass light"),
                     ("Interface Style", "Classic", "classic light"), ("Appearance", "Dark", "classic dark")]
        for (menu, item, look) in steps {
            pick(menu, item)
            expectLook(look)
            keepScreenshot(look)
        }
        // Auto follows macOS, from the other appearance so that an Auto that does nothing fails.
        let (system, other) = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            ? ("dark", "light") : ("light", "dark")
        pick("Appearance", other.capitalized)
        expectLook("classic \(other)")
        pick("Appearance", "Auto")
        expectLook("classic \(system)")
    }

    /// Launch arguments land in UserDefaults' argument domain, which the settings read. They also pin the look: the
    /// menu then writes the persistent domain, which the argument domain hides.
    func testLaunchesInEachLook() async throws {
        for (appearance, style) in [("light", "glass"), ("dark", "classic"), ("light", "classic"), ("dark", "glass")] {
            relaunch(one, ["-appearance", appearance, "-interfaceStyle", style])
            expectLook("\(style) \(appearance)")
            try await expectPTYSize("w1:p1")
        }
    }

    /// No card fades (phase 25 dropped the setting). In Glass the cards look alike: the keyboard card at most a little
    /// brighter. Read from pixels, the one place the look shows (as `RevealTests` do).
    func testCardsLookAlikeWithAndWithoutTheKeyboard() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("terminal.w1:p1").click()
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))
        let keyboard = element("pane.w1:p1"), other = element("pane.w1:p2")
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuBars.menuItems["Toggle Sidebar"].exists(within: 2))
        XCTAssertFalse(app.menuBars.menuItems["Fade Inactive Panes"].exists)
        app.typeKey(.escape, modifierFlags: [])

        // CI's VM draws the glass backdrop opaque whatever the desktop shows (a runner window under Oriel in black,
        // white and blue changed no pixel of it), so a desktop's effect is not checked here.
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        for appearance in ["Dark", "Light"] {
            pick("Appearance", appearance)
            // The fills follow the look within a frame or two.
            Thread.sleep(forTimeInterval: 0.3)
            let lit = median(keyboard), unlit = median(other)
            keepScreenshot("glass \(appearance.lowercased()): \(lit) / \(unlit)")
            // 0: a screenshot that did not draw.
            XCTAssertTrue(unlit > 0 && (0 ... 6).contains(lit - unlit), "\(appearance): \(lit) / \(unlit)")
        }
    }

    /// Glass cards carry Rex's rim (phase 25): brighter along the top edge than down the sides, on every card alike.
    /// Asserted in dark; light's rim and the card both end near white, so its screenshot is for people.
    func testGlassCardsHaveABrighterTopRim() {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in pick("Appearance", "Dark") }
        for appearance in ["Dark", "Light"] {
            pick("Appearance", appearance)
            Thread.sleep(forTimeInterval: 0.3)
            let rims = ["w1:p1", "w1:p2"].map { rim(element("pane.\($0)")) }
            keepScreenshot("glass \(appearance.lowercased()) rims over the fill (top, side): \(rims)")
            for rim in rims where appearance == "Dark" {
                // Rex's dark rim: the top line about 40 steps over the fill at 1x, the sides about 10.
                XCTAssertTrue(rim.top - rim.side >= 12 && rim.top >= 25, "\(rims)")
            }
        }
    }

    /// How much brighter than the card's median (its fill) the brightest of its top 3 pixel rows round its middle is,
    /// and the brightest of its left 3 columns round its middle.
    private func rim(_ card: XCUIElement) -> (top: Int, side: Int) {
        let image = card.screenshot().image
        let brightness = Self.brightness(image)
        guard let width = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, width > 0,
              brightness.count > width * 40 else { return (0, 0) }
        let height = brightness.count / width
        // The mean of 20 pixels, by their offsets in the image.
        func mean(_ offsets: [Int]) -> Int {
            offsets.map { brightness[$0] }.reduce(0, +) / offsets.count
        }
        let middle = Array(-10 ..< 10)
        let top = (0 ..< 3).map { row in mean(middle.map { row * width + width / 2 + $0 }) }.max() ?? 0
        let side = (0 ..< 3).map { column in mean(middle.map { (height / 2 + $0) * width + column }) }.max() ?? 0
        let fill = brightness.sorted()[brightness.count / 2]
        return (top - fill, side - fill)
    }

    /// The median brightness of a card: its fill, as its text is a small share.
    private func median(_ card: XCUIElement) -> Int {
        let brightness = Self.brightness(card.screenshot().image).sorted()
        return brightness.isEmpty ? 0 : brightness[brightness.count / 2]
    }

    func pick(_ menu: String, _ item: String) {
        app.menuBars.menuBarItems["View"].click()
        let submenu = app.menuBars.menuItems[menu]
        submenu.hover()
        submenu.menuItems[item].click()
    }

    private func expectLook(_ look: String) {
        XCTAssertTrue(element("window.look").has(\.stringValue, look, within: connect), look)
    }
}
