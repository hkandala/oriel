import XCTest

/// A card's terminal keeps its old picture while herdr redraws it at a new grid, a new card fades in once, and both
/// always show herdr's text in the end (phase 24, items 1, 2 and 19).
/// The pixels of a terminal are the only place an empty card shows, so these tests read its screenshot.
extension OrielUITests {
    /// Every way a card comes into view shows its text: launch, another tab and back, another workspace and back, a
    /// new tab, a split, the sidebar.
    func testCardsShowTheirTextOnEveryPath() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        for pane in ["w1:p1", "w1:p2", "w1:p3", "w1:p4", "w2:p1"] {
            try await fill(pane)
        }
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "launch")
        element("tab.w1:t2").click()
        try await expectText(["w1:p4"], "second tab")
        element("tab.w1:t1").click()
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "first tab again")
        element("workspace.w2").click()
        try await expectText(["w2:p1"], "second workspace")
        element("workspace.w1").click()
        try await expectText(["w1:p1", "w1:p2", "w1:p3"], "first workspace again")

        let (tab, pane) = try await newTab("reveal")
        try await fill(pane)
        element("tab.\(tab)").click()
        try await expectText([pane], "new tab")
        let right = try await split(pane)
        try await fill(right)
        try await expectText([pane, right], "split")
        element("titlebar.sidebar").click()
        try await expectText([pane, right], "sidebar hidden")
        element("titlebar.sidebar").click()
        try await expectText([pane, right], "sidebar shown")
    }

    /// While the sidebar slides, the card's terminal keeps its grid (clipped), then takes the new one once: no
    /// passing grid in between, and the program redraws once.
    func testCardKeepsItsGridUntilItsSizeSettles() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        try await expectPTYSize("w1:p1")
        try await send("trap 'echo winch' WINCH\r", to: "w1:p1")
        try await waitFor("w1:p1") { $0.contains("WINCH") }
        let before = terminal.stringValue
        element("titlebar.sidebar").click()
        var grids = [before]
        let end = Date.now + 1.5
        while Date.now < end {
            if terminal.stringValue != grids.last {
                grids.append(terminal.stringValue)
            }
        }
        // The check that tells this from a resize at every frame: herdr's one resize (the winch count) came with the
        // old 100 ms settle too. A stall over 150 ms inside the slide would give a real third grid.
        XCTAssertEqual(grids.count, 2, "grids while the sidebar slid: \(grids)")
        // bash prints it after its prompt, on the prompt's line.
        let winches = { (screen: String) in screen.split(separator: "\n").count { $0.hasSuffix("winch") } }
        try await waitFor("w1:p1") { winches($0) > 0 }
        try await Task.sleep(for: .milliseconds(500))
        let screen = try await read("w1:p1")
        XCTAssertEqual(winches(screen), 1, screen)
        try await expectPTYSize("w1:p1")
        try await fill("w1:p1")
        try await expectText(["w1:p1"], "after the resize")
    }

    /// A resize never blanks the text (item 19): the old picture stays until herdr's frames at the new grid replace it.
    /// The sidebar resizes the card, ⌘+ and ⌘- its grid.
    func testResizeNeverBlanksTheText() async throws {
        let terminal = element("terminal.w1:p1")
        XCTAssertTrue(terminal.exists(within: connect))
        addTeardownBlock { @MainActor [self] in app.typeKey("0", modifierFlags: .command) }
        try await fill("w1:p1")
        try await expectText(["w1:p1"], "filled")
        let steps: [(String, () -> Void)] = [
            ("sidebar hidden", { self.element("titlebar.sidebar").click() }),
            ("sidebar shown", { self.element("titlebar.sidebar").click() }),
            ("bigger text", { self.app.typeKey("+", modifierFlags: .command) }),
            ("smaller text", { self.app.typeKey("-", modifierFlags: .command) }),
        ]
        for (step, act) in steps {
            let grid = terminal.stringValue
            act()
            // Screenshots as fast as they come through the resize and herdr's redraw; read after, not in between.
            var shots: [NSImage] = []
            let end = Date.now + 1.5
            while Date.now < end {
                shots.append(terminal.screenshot().image)
            }
            let inks = shots.map(Self.ink)
            XCTAssertGreaterThan(inks.min() ?? 0, 0.01, "\(step): ink of \(inks.count) screenshots: \(inks)")
            XCTAssertNotEqual(terminal.stringValue, grid, "\(step): the grid changed")
            // Drawing is back on: not stuck on the old picture.
            try await expectText(["w1:p1"], step)
        }
    }

    /// Split, zoom, close and the sidebar animate the card that stays (phase 25, item 3): its host goes through the
    /// sizes in between (`-recordMotion YES` counts them; a card made again or one that jumps takes one or two), and
    /// its text never blanks on the way (phase 24's rule, never seen with motion before: CI has Reduce Motion on).
    /// Under Reduce Motion the card jumps.
    func testLayoutMotionAnimatesWithoutBlanking() async throws {
        relaunch(one, ["-recordMotion", "YES"])
        let (tab, pane) = try await newTab("motion")
        element("tab.\(tab)").click()
        let host = element("host.\(pane)"), terminal = element("terminal.\(pane)")
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try await expectJump(tab, pane)
        }
        try await fill(pane)
        try await expectText([pane], "filled")
        let steps: [(String, () async throws -> Void)] = [
            // The app shows a stand-in card at once (sliding in from the left), then herdr's pane in its place.
            ("split left", { self.paneMenu(pane, "Split Left") }),
            ("zoom", {
                self.hoverHeader(pane)
                self.element("pane.\(pane).zoom").click()
            }),
            ("restore", { self.app.typeKey(.return, modifierFlags: [.command, .shift]) }),
            ("close", {
                let other = try await self.order(tab).first { $0 != pane } ?? ""
                _ = try await Self.call(self.one, "pane.close", ["pane_id": other])
            }),
            ("sidebar hidden", { self.element("titlebar.sidebar").click() }),
            ("sidebar shown", { self.element("titlebar.sidebar").click() }),
        ]
        for (step, act) in steps {
            XCTAssertTrue(host.exists(within: 3), step)
            let sizes = Int(host.label) ?? 0
            // The screen, not the element, which moves: a band across the window through the middle of the terminal.
            // Its text stays in the band while the card moves (no other card has text that low).
            let frame = terminal.frame, window = app.windows.firstMatch.frame
            let band = CGRect(x: window.minX, y: frame.minY + frame.height * 0.45, width: window.width,
                              height: frame.height * 0.2)
            let before = Self.ink(Self.crop(XCUIScreen.main.screenshot().image, band))
            try await act()
            var shots: [NSImage] = []
            let end = Date.now + 1
            while Date.now < end {
                shots.append(XCUIScreen.main.screenshot().image)
            }
            let inks = shots.map { Self.ink(Self.crop($0, band)) }
            XCTAssertGreaterThan(inks.min() ?? 0, before / 3, "\(step): ink \(before) before, then \(inks)")
            XCTAssertGreaterThanOrEqual((Int(host.label) ?? 0) - sizes, 4,
                                        "\(step): sizes from \(sizes) to \(host.label)")
            try await expectText([pane], step)
        }
    }

    /// Under Reduce Motion (CI's Mac) the card jumps to its new size in one step; then the app launches again with
    /// motion forced on.
    private func expectJump(_ tab: String, _ pane: String) async throws {
        let host = element("host.\(pane)")
        XCTAssertTrue(host.exists(within: 3))
        let sizes = Int(host.label) ?? 0
        let other = try await split(pane)
        XCTAssertTrue(until(3) { Int(host.label) == sizes + 1 }, "Reduce Motion")
        _ = try await Self.call(one, "pane.close", ["pane_id": other])
        XCTAssertTrue(element("pane.\(other)").vanishes(within: 3))
        relaunch(one, ["-recordMotion", "YES", "-forceMotion", "YES"])
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").has(\.isHittable, true, within: 3))
        element("tab.\(tab)").click()
    }

    /// The part of a screen shot inside a rectangle in screen points.
    private static func crop(_ image: NSImage, _ rect: CGRect) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let scale = CGFloat(cgImage.width) / image.size.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale,
                            height: rect.height * scale)
        return cgImage.cropping(to: pixels).map { NSImage(cgImage: $0, size: rect.size) } ?? image
    }

    /// Lines of text in the pane, so an empty card is plain to see.
    private func fill(_ pane: String) async throws {
        try await waitForPrompt(pane)
        try await send("clear; for i in $(seq 1 60); do echo oriel-reveal-$i-oriel-reveal; done\r", to: pane)
        try await waitFor(pane) { $0.contains("oriel-reveal-60-oriel-reveal") }
    }

    /// Each card is done loading and its terminal shows text: some of its pixels differ from its background.
    private func expectText(_ panes: [String], _ step: String) async throws {
        keepScreenshot(step)
        for pane in panes {
            let card = element("pane.\(pane)"), terminal = element("terminal.\(pane)")
            var ink = 0.0
            do {
                try await expect("text", times: 30) {
                    guard card.exists, !card.stringValue.hasSuffix(", loading"),
                          terminal.isHittable else { return false }
                    ink = Self.ink(terminal.screenshot().image)
                    return ink > 0.01
                }
            } catch is Waited {
                throw Waited(description: "\(pane) shows no text after \(step): \(card.stringValue), ink \(ink)")
            }
        }
    }

    /// The share of pixels whose brightness is far from the image's median: about 0 for an empty card.
    private static func ink(_ image: NSImage) -> Double {
        let brightness = brightness(image)
        guard !brightness.isEmpty else { return 0 }
        let median = brightness.sorted()[brightness.count / 2]
        return Double(brightness.count { abs($0 - median) > 60 }) / Double(brightness.count)
    }

    /// Each pixel's brightness, 0–255; none when the image does not draw.
    static func brightness(_ image: NSImage) -> [Int] {
        let pixels = pixels(image)
        return stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
        }
    }

    /// The image's pixels, RGBA row by row; none when the image does not draw.
    static func pixels(_ image: NSImage) -> [UInt8] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                .map { $0.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height)) } != nil
        }
        return drawn ? pixels : []
    }
}
