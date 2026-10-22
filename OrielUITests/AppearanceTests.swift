import XCTest

/// Appearance and interface style (phase 10). The window's root element `window.look` says which look it draws,
/// from the effective appearance and the style setting.
extension OrielUITests {
    /// View ▸ Appearance and View ▸ Interface Style switch the look, with a screenshot of each of the four.
    func testMenuSwitchesTheLook() {
        XCTAssertTrue(element("terminal.w1:p1").waitForExistence(timeout: connect))
        // Settings persist: start from the defaults whatever an earlier run left, and end on them.
        pick("Interface Style", "Glass")
        let steps = [("Appearance", "Dark", "glass dark"), ("Appearance", "Light", "glass light"),
                     ("Interface Style", "Classic", "classic light"), ("Appearance", "Dark", "classic dark"),
                     ("Interface Style", "Glass", "glass dark")]
        for (menu, item, look) in steps {
            pick(menu, item)
            expectLook(look)
            keepScreenshot(look)
        }
    }

    /// Launch arguments land in UserDefaults' argument domain, which the settings read.
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

    private func pick(_ menu: String, _ item: String) {
        app.menuBars.menuBarItems["View"].click()
        let submenu = app.menuBars.menuItems[menu]
        submenu.hover()
        submenu.menuItems[item].click()
    }

    private func expectLook(_ look: String) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", look),
                                              object: element("window.look"))
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: connect), .completed, look)
    }
}
