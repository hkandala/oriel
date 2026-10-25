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

    /// No card fades (phase 25 dropped the setting), in a key window and one that is not. In Glass the cards look
    /// alike over a dark and a light desktop: the keyboard card at most a little brighter. Read from pixels, the one
    /// place the look shows (as `RevealTests` do).
    func testCardsLookAlikeWithAndWithoutTheKeyboard() throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        element("terminal.w1:p1").click()
        XCTAssertTrue(hasKeyboard(element("terminal.w1:p1")))
        let keyboard = element("pane.w1:p1"), other = element("pane.w1:p2")
        expectValue(keyboard, "content 100%")
        expectValue(other, "content 100%")
        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuBars.menuItems["Toggle Sidebar"].exists(within: 2))
        XCTAssertFalse(app.menuBars.menuItems["Fade Inactive Panes"].exists)
        // Ghostty's words for the text size (phase 25).
        for title in ["Increase Font Size", "Decrease Font Size", "Reset Font Size"] {
            XCTAssertTrue(app.menuBars.menuItems[title].exists, title)
        }
        app.typeKey(.escape, modifierFlags: [])

        // A window of the test runner under every other window stands in for the desktop picture.
        let desktop = NSWindow(contentRect: NSScreen.screens[0].frame, styleMask: .borderless, backing: .buffered,
                               defer: false)
        desktop.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        desktop.isReleasedWhenClosed = false
        desktop.orderFront(nil)
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in
            desktop.close()
            pick("Appearance", "Dark")
        }
        for appearance in ["Dark", "Light"] {
            pick("Appearance", appearance)
            for (name, color) in [("black", NSColor.black), ("white", .white), ("blue", .systemBlue)] {
                desktop.backgroundColor = color
                // The blur follows the window behind it within a frame or two.
                Thread.sleep(forTimeInterval: 0.5)
                let lit = median(keyboard), unlit = median(other)
                keepScreenshot("glass \(appearance.lowercased()) over \(name): \(lit) / \(unlit)")
                XCTAssertTrue((0 ... 6).contains(lit - unlit), "\(appearance) over \(name): \(lit) / \(unlit)")
            }
        }

        // A window that is not key draws its cards at full strength too.
        let (first, _) = try newWindow()
        expectValue(element("pane.w1:p1", in: first), "content 100%")
        expectValue(element("pane.w1:p2", in: first), "content 100%")
        app.typeKey("w", modifierFlags: [.command, .shift])
    }

    /// The median brightness of a card: its fill, as its text is a small share.
    private func median(_ card: XCUIElement) -> Int {
        let brightness = Self.brightness(card.screenshot().image).sorted()
        return brightness.isEmpty ? -1 : brightness[brightness.count / 2]
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
