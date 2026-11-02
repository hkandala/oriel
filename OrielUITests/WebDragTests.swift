import XCTest

/// A pane dragged over web cards (a browser's and a plugin's): their pages take no part in the app's own drags.
extension OrielUITests {
    /// The highlight shows on the right half of a browser card and then of a plugin card while the drag holds there,
    /// and the drop places the pane right of the plugin card.
    func testADragOverWebCardsShowsTheirEdgesAndDrops() async throws {
        let (tabs, first) = try await newWorkspace("web")
        let tab = tabs[0]
        try await waitForPrompt(first)
        let page = try await writePages(from: first)
        let browser = try await split(first), plugin = try await split(browser)
        for (pane, label) in [(browser, "oriel:browser#e2edrb \(page)"), (plugin, "oriel:explorer#e2edrp /tmp/")] {
            try await Self.call(one, "pane.rename", ["pane_id": pane, "label": label])
            try await Self.call(one, "pane.report_metadata", ["pane_id": pane, "source": "oriel-panes",
                                                              "tokens": ["oriel-label": "1"], "ttl_ms": 1000])
        }
        restoreHerdrFocusAfter()
        XCTAssertTrue(pageText("oriel-page-one").exists(within: 10))
        XCTAssertTrue(element("files.\(plugin).page").exists(within: 10))

        // Through the helper's drag, which leaves XCUITest free to read the highlight while it holds.
        let from = card(first, 0, 0).withOffset(CGVector(dx: 60, dy: 17)).screenPoint
        let over = [browser, plugin].map { card($0, 0.9, 0.6).screenPoint }
        let path = "\(from.x) \(from.y) \(over[0].x) \(over[0].y) 2.5 \(over[1].x) \(over[1].y) 2.5"
        let drag = Task.detached { [one] in try await Self.post("\(one)/drag", Data(path.utf8)) }
        let indicator = element("drop.indicator")
        for pane in [browser, plugin] {
            let frame = element("pane.\(pane)").frame
            let right = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
            var seen = CGRect.null
            XCTAssertTrue(until(4) {
                seen = indicator.exists ? indicator.frame : .null
                return abs(seen.minX - right.minX) < 3 && abs(seen.maxX - right.maxX) < 3
                    && abs(seen.minY - right.minY) < 3 && abs(seen.maxY - right.maxY) < 3
            }, "the highlight over \(pane)'s right half \(right): \(seen)")
        }
        _ = try await drag.value
        try await expect("the pane right of the plugin card") { try await order(tab) == [browser, plugin, first] }
        XCTAssertTrue(indicator.vanishes(within: 2))
    }
}
