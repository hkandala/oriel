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
        let base = app.launchArguments
        for (appearance, style) in [("light", "glass"), ("dark", "classic"), ("light", "classic"), ("dark", "glass")] {
            app.terminate()
            app.launchArguments = base + ["-appearance", appearance, "-interfaceStyle", style]
            app.launch()
            expectLook("\(style) \(appearance)")
            try await expectPTYSize("w1:p1")
        }
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
