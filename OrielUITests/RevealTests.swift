import XCTest

/// A card's terminal hides while herdr redraws it at a new grid and always shows again (phase 24, items 1 and 2).
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
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                .map { $0.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height)) } != nil
        }
        guard drawn, width * height > 0 else { return 0 }
        let brightness = stride(from: 0, to: pixels.count, by: 4).map {
            (Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])) / 3
        }
        let median = brightness.sorted()[brightness.count / 2]
        return Double(brightness.count { abs($0 - median) > 60 }) / Double(brightness.count)
    }
}
