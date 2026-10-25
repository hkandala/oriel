import XCTest

/// The hover card (phase 19): a tab's panes on a capsule or an Agents view row, and the chrome buttons' tooltips.
extension OrielUITests {
    func testHoverCardShowsABlockedAgentsScreenAndEscClosesIt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("deploy")
        try await split(split(pane))
        try await send("echo hover-$((6*7)); echo waiting\r", to: pane)
        try await waitFor(pane) { $0.contains("\nhover-42") }
        try await report(pane, "blocked", agent: "claude")
        try await waitForValue("tab.\(tab)", containing: "claude, needs you")

        element("tab.\(tab)").hover()
        let card = element("hovercard")
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertEqual(rows(of: card).count, 3)
        try await waitForValue("hovercard.\(pane)", containing: "hover-42")
        XCTAssertTrue((element("hovercard.\(pane)").value as? String)?.hasPrefix("Needs you") == true)
        // Under its capsule, 6 pt below the 46 pt title row (12 pt below the 34 pt capsule).
        XCTAssertEqual(card.frame.midX, element("tab.\(tab)").frame.midX, accuracy: 2)
        XCTAssertEqual(card.frame.minY - element("tab.\(tab)").frame.maxY, 12, accuracy: 1.5)
        keepScreenshot("hover card")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(card.vanishes(within: 2))
    }

    func testHoverCardRowGoesToItsPane() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("peek")
        let second = try await split(pane)
        XCTAssertFalse(element("tab.\(tab)").isSelected)

        element("tab.\(tab)").hover()
        let card = element("hovercard")
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertEqual(rows(of: card).count, 2)
        element("hovercard.\(second)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(hasKeyboard(element("terminal.\(second)")))
        XCTAssertTrue(card.vanishes(within: 2))

        // Shown again, it still goes when the pointer leaves (it closed under the pointer).
        element("tab.\(tab)").hover()
        XCTAssertTrue(card.exists(within: 2))
        element("workspace.w1").hover()
        XCTAssertTrue(card.vanishes(within: 2))
    }

    func testAgentsRowShowsItsTabsCard() async throws {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let (tab, pane) = try await newTab("build")
        try await split(pane)
        element("workspace.w1").click()
        try await report(pane, "working")
        app.typeKey(".", modifierFlags: .command)
        let row = element("agent.\(pane)")
        XCTAssertTrue(row.exists(within: 3))

        row.hover()
        let card = element("hovercard")
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertEqual(rows(of: card).count, 2)
        XCTAssertEqual(card.label, "Panes of build")
        // Beside the row, 6 pt past the sidebar's edge.
        XCTAssertEqual(card.frame.minY, row.frame.minY, accuracy: 1.5)
        XCTAssertEqual(card.frame.minX - element("sidebar").frame.maxX, 6, accuracy: 1.5)
        // A click on the title selects the tab and its workspace.
        element("hovercard.title").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        XCTAssertTrue(card.vanishes(within: 2))
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
    }

    /// In every look the card over a busy terminal shows the text behind only as a soft blur: its empty part is far
    /// less sharp than the same text below the card. On a Mac Liquid Glass alone let it read clearly (user, phase
    /// 25); CI's VM draws glass with no backdrop (the old glass hid text there too, run 40174324533), so on CI this
    /// guards only against a see-through panel.
    func testHoverCardBlursTheTextBehindIt() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("busy")
        element("tab.\(tab)").click()
        let line = String(repeating: "@#W", count: 60)
        try await send("clear; yes '\(line)' | head -300\r", to: pane)
        try await waitFor(pane) { $0.components(separatedBy: "@#W@#W@#W").count > 50 }
        pick("Interface Style", "Glass")
        addTeardownBlock { @MainActor [self] in
            pick("Interface Style", "Glass")
            pick("Appearance", "Dark")
        }
        let card = element("hovercard")
        for (menu, item, look) in [("Appearance", "Dark", "glass dark"), ("Appearance", "Light", "glass light"),
                                   ("Interface Style", "Classic", "classic light"),
                                   ("Appearance", "Dark", "classic dark")]
        {
            pick(menu, item)
            element("workspace.w1").hover()
            XCTAssertTrue(card.vanishes(within: 2), look)
            element("tab.\(tab)").hover()
            XCTAssertTrue(card.exists(within: 2), look)
            // The pane row's empty right part, and the same rect over the bare terminal below the card.
            let row = element("hovercard.\(pane)").frame
            let empty = CGRect(x: row.midX, y: row.minY + 3, width: row.width / 2 - 10, height: 20)
            var sharp = (card: 0.0, bare: 0.0)
            // The card fades in, and the terminal draws its lines.
            let blurred = until(2) {
                sharp = (sharpness(empty), sharpness(empty.offsetBy(dx: 0, dy: 100)))
                return sharp.bare > 4 && sharp.card < sharp.bare * 0.3
            }
            keepScreenshot("\(look): card \(sharp.card), bare \(sharp.bare)")
            XCTAssertTrue(blurred, "\(look): card \(sharp.card), bare \(sharp.bare)")
        }
    }

    /// The card previews the tab's cards in their layout (phase 25): herdr's screen text for panes no terminal showed
    /// yet, then each terminal's own picture, which follows the terminal while the card stays open.
    func testHoverCardPreviewsTheTabsCardsLive() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("preview")
        let second = try await split(pane)
        try await send("echo preview-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("\npreview-42") }

        let card = element("hovercard")
        let left = element("hovercard.preview.\(pane)"), right = element("hovercard.preview.\(second)")
        element("tab.\(tab)").hover()
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertTrue(left.has(\.stringValue, "text", within: 2))
        XCTAssertEqual(right.stringValue, "text")
        // Side by side with a 2 pt gap (the page's 8 pt at a quarter), as herdr's split right.
        XCTAssertEqual(right.frame.minX - left.frame.maxX, 2, accuracy: 1)
        XCTAssertEqual(left.frame.minY, right.frame.minY, accuracy: 1)
        XCTAssertEqual(left.frame.height, right.frame.height, accuracy: 1)
        XCTAssertGreaterThan(left.frame.width, 100)

        // Shown once, each card shows its terminal's picture, and it follows the terminal while the card is open: a
        // white block, then a clear screen.
        element("tab.\(tab)").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 2))
        let block = "for i in 1 2 3 4 5 6 7 8 9 10; do printf '\\033[107m%300s\\033[0m\\n' ''; done"
        try await send("clear; \(block); echo block-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("\nblock-42") }
        element("workspace.w1").hover()
        XCTAssertTrue(card.vanishes(within: 2))
        element("tab.\(tab)").hover()
        XCTAssertTrue(card.exists(within: 2))
        XCTAssertTrue(left.has(\.stringValue, "picture", within: 2))
        XCTAssertEqual(right.stringValue, "picture")
        var shade = (left: 0, right: 0)
        let white = until(3) {
            shade = (mean(left), mean(right))
            return shade.left > shade.right + 60
        }
        keepScreenshot("hover card preview: \(shade)")
        XCTAssertTrue(white, "\(shade)")
        try await send("clear\r", to: pane)
        let cleared = until(3) {
            shade = (mean(left), mean(right))
            return shade.left < shade.right + 20
        }
        XCTAssertTrue(cleared, "\(shade)")
    }

    /// The mean brightness of an element's pixels.
    private func mean(_ element: XCUIElement) -> Int {
        let brightness = Self.brightness(element.screenshot().image)
        return brightness.isEmpty ? 0 : brightness.reduce(0, +) / brightness.count
    }

    /// The mean brightness step between neighbor pixels in a rect of the window (screen points): high for crisp text,
    /// low for a blur.
    private func sharpness(_ rect: CGRect) -> Double {
        let window = app.windows.firstMatch
        let shot = window.screenshot().image
        guard let full = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let scale = Double(full.width) / shot.size.width
        let box = rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        guard let crop = full.cropping(to: CGRect(x: box.minX * scale, y: box.minY * scale,
                                                  width: box.width * scale, height: box.height * scale))
        else { return 0 }
        // Row ends pair with the next row's start: a few steps in thousands, no matter for a ratio.
        let brightness = Self.brightness(NSImage(cgImage: crop, size: .zero))
        let steps = zip(brightness, brightness.dropFirst()).map { abs($0 - $1) }
        return steps.isEmpty ? 0 : Double(steps.reduce(0, +)) / Double(steps.count)
    }

    /// The tooltip and the VoiceOver label are one string (`IconButton`). macOS gives the help tag's text to no
    /// accessibility attribute, and on CI the tag showed in one run of two, so the label stands in for it.
    func testChromeButtonsNameTheirShortcuts() {
        let button = element("titlebar.new-tab")
        XCTAssertTrue(button.exists(within: connect))
        XCTAssertEqual(button.label, "New Tab ⌘T")
        XCTAssertEqual(element("titlebar.palette").label, "Command Palette ⌘K")
        XCTAssertEqual(element("sidebar.open-session").label, "Open Session ⌥⌘T")
    }

    /// The card's pane rows.
    private func rows(of card: XCUIElement) -> [XCUIElement] {
        card.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'hovercard.' AND identifier != 'hovercard.title'"))
            .allElementsBoundByIndex
    }
}
