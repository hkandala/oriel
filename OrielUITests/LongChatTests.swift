import XCTest

/// A long chat (ui/chat-view#what-it-looks-like) with Claude Code's stand-in: it shows its newest message, keeps the
/// message at its top when a split narrows its card, and its button scrolls back to the bottom.
extension OrielUITests {
    func testALongChatKeepsItsPlaceAndScrollsToTheBottom() async throws {
        let (tab, pane) = try await startChat()
        try await say("many", in: pane)
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let bottom = element("chat.\(pane).bottom")
        XCTAssertFalse(bottom.exists)

        // Up into the older messages, by natural scrolling either way.
        let chat = element("chat.\(pane)")
        let point = "\(chat.frame.midX) \(chat.frame.midY)"
        for step in [10, -10] {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step) 20 100 1".utf8))
            if bottom.exists(within: 2) {
                break
            }
        }
        XCTAssertTrue(bottom.exists)
        XCTAssertFalse(last.isHittable)
        // The scroll's momentum ends before the reply at the top of the view is read.
        let replies = app.descendants(matching: .any).matching(identifier: "chat.\(pane).reply")
        var top = ""
        XCTAssertTrue(until(3) {
            let seen = replies.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY > chat.frame.minY }?
                .stringValue ?? ""
            defer { top = seen }
            return !seen.isEmpty && seen == top
        })

        // A split beside it narrows the card: its text wraps again, and the same reply stays in view.
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        _ = try await poll("a pane beside the chat") { try await order(tab).count == 2 ? true : nil }
        let anchor = row(pane, "reply", top)
        XCTAssertTrue(until(3) { anchor.exists && anchor.isHittable && chat.frame.width < 600 }, "\(chat.frame)")
        XCTAssertFalse(last.isHittable)

        bottom.click()
        XCTAssertTrue(until(3) { last.isHittable })
        XCTAssertTrue(bottom.vanishes(within: 2))
    }
}
