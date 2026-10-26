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
        XCTAssertTrue(hasKeyboard("terminal.w1:p1"))
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
                // Rex's dark rim: the top line about 40 steps over the fill at 1x, the sides about 10; every card
                // alike.
                XCTAssertTrue(rim.top - rim.side >= 12 && rim.top >= 25 && abs(rim.top - rims[0].top) <= 6, "\(rims)")
            }
        }
    }

    /// Text selected in a terminal reads well in all four looks (phase 29 lane C): its own color over the selection,
    /// where libghostty's default drew it in the window background, about the selection's own grey. A drag over a
    /// plain shell selects locally (herdr drops mouse events for a program without mouse mode).
    func testSelectedTextIsReadable() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await waitForPrompt("w1:p1")
        // Every row full: full blocks (3 cells in 10) draw the cell's text color edge to edge. printf makes their
        // bytes, so the line editor gets ASCII in any locale.
        try await send(
            "clear; for i in $(seq 600); do printf '\\342\\226\\210\\342\\226\\210\\342\\226\\210 oriel '; done; "
                + "echo; echo oriel-$((6*7))\r",
            to: "w1:p1",
        )
        try await waitFor("w1:p1") { $0.contains("\noriel-42") }
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        for (style, appearance) in [("Glass", "Dark"), ("Glass", "Light"), ("Classic", "Light"), ("Classic", "Dark")] {
            pick("Interface Style", style)
            pick("Appearance", appearance)
            let look = "\(style) \(appearance)".lowercased()
            expectLook(look)
            // The top half of the rows, every one full width.
            terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01))
                .click(
                    forDuration: 0.2,
                    thenDragTo: terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)),
                )
            // WCAG's 4.5 for text; the old default drew 1.2 in dark, 1.4 in light. The selection shows on the card
            // (about 1.0 when no selection was drawn). The terminal takes the look a frame or two after the window.
            var last = (text: 0.0, selection: 0.0)
            do {
                try await expect("\(look): readable selected text", times: 20) {
                    last = Self.contrast(terminal.screenshot().image)
                    return last.text > 4.5 && last.selection > 1.1
                }
            } catch is Waited {
                throw Waited(description: "\(look): text \(last.text), selection over the card \(last.selection)")
            }
            keepScreenshot("\(look) selection: text \(last.text), selection over the card \(last.selection)")
        }
    }

    /// In the image's top third (selected), the contrast of its text color with the selection's: the most common
    /// color there, and a pixel at the 85th percentile of contrast with it (full blocks fill 30 %). And the
    /// selection's contrast with the most common color of the bottom pixel row (the card under the unselected rows).
    private static func contrast(_ image: NSImage) -> (text: Double, selection: Double) {
        let pixels = pixels(image)
        guard let width = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, width > 0,
              pixels.count > width * 4 * 30 else { return (0, 0) }
        let rows = pixels.count / 4 / width
        func luminance(_ offset: Int) -> Double {
            let linear = (0 ..< 3).map { channel in
                let value = Double(pixels[offset + channel]) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        func ratio(_ one: Double, _ other: Double) -> Double {
            (max(one, other) + 0.05) / (min(one, other) + 0.05)
        }
        // The offset of a pixel of the most common color.
        func common(_ offsets: [Int]) -> Int {
            let colors = Dictionary(grouping: offsets) { pixels[$0 ..< $0 + 3].reduce(0) { $0 << 8 | Int($1) } }
            return colors.max { $0.value.count < $1.value.count }?.value.first ?? 0
        }
        let top = (0 ..< rows / 3 * width).map { $0 * 4 }
        let background = luminance(common(top))
        let text = top.map { ratio(luminance($0), background) }.sorted()[top.count * 85 / 100]
        let card = luminance(common(((rows - 1) * width ..< rows * width).map { $0 * 4 }))
        return (text, ratio(background, card))
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

    /// The median brightness of a card or a button: its fill, as its text is a small share.
    func median(_ card: XCUIElement) -> Int {
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
