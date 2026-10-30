import XCTest

/// A long chat (ui/chat-view#what-it-looks-like) with Claude Code's stand-in: it shows its newest message, keeps the
/// messages at its top when a split narrows its card, its button scrolls back to the bottom, which stays there when the
/// card widens, and the session opened again shows at once.
extension OrielUITests {
    func testALongChatKeepsItsPlaceAndScrollsToTheBottom() async throws {
        let (tab, pane) = try await startChat()
        // Not `say`: its bubble is 150 turns up by the time it would look.
        app.typeText("many\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let bottom = element("chat.\(pane).bottom")
        XCTAssertFalse(bottom.exists)

        // Up into the older messages, by natural scrolling either way.
        let chat = element("chat.\(pane)")
        let point = "\(chat.frame.midX) \(chat.frame.midY)"
        var upward = 0
        for step in [10, -10] where upward == 0 {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step) 20 100 1".utf8))
            if bottom.exists(within: 2) {
                upward = step
            }
        }
        XCTAssertTrue(bottom.exists)
        // Far enough up that the newest reply is out of view, so a jump back to it would show.
        for _ in 0 ..< 5 where last.exists && last.isHittable {
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(upward) 20 100 1".utf8))
        }
        XCTAssertFalse(last.exists && last.isHittable)
        // The messages along the top of the view, once the scroll's momentum ends.
        var top: Set<String> = []
        XCTAssertTrue(until(3) {
            let seen = atTop(of: chat, pane)
            defer { top = seen }
            return !seen.isEmpty && seen == top
        })

        // A split beside it narrows the card: its text wraps again, and the same messages stay at the top.
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()
        let other = try await poll("a pane beside the chat") { try await order(tab).first { $0 != pane } }
        XCTAssertTrue(until(3) { chat.frame.width < 600 && !atTop(of: chat, pane).isDisjoint(with: top) },
                      "\(top) \(atTop(of: chat, pane))")
        XCTAssertFalse(last.exists && last.isHittable)

        bottom.click()
        XCTAssertTrue(until(3) { last.exists && last.isHittable })
        XCTAssertTrue(bottom.vanishes(within: 2))
        // At the bottom, it stays there as the card widens again.
        _ = try await Self.call(one, "pane.close", ["pane_id": other])
        XCTAssertTrue(until(3) { chat.frame.width > 600 && last.exists && last.isHittable }, "\(chat.frame)")
        XCTAssertFalse(bottom.exists)

        // Opened again, the long session is read whole as a backlog and shows without a switch.
        relaunch()
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        element("workspace.w2").click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(pane).view.tui").has(\.isSelected, true, within: 10))
        element("pane.\(pane).view.chat").click()
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
    }

    /// The values of the replies' blocks and the user's messages along the top 100 pt of the chat, from one snapshot.
    private func atTop(of chat: XCUIElement, _ pane: String) -> Set<String> {
        guard let tree = try? chat.snapshot() else { return [] }
        let kinds = ["chat.\(pane).reply", "chat.\(pane).user"], top = tree.frame.minY
        var found: Set<String> = [], queue = [tree]
        while let node = queue.popLast() {
            queue += node.children
            if kinds.contains(node.identifier), node.frame.maxY > top, node.frame.minY < top + 100,
               let value = node.value as? String
            {
                found.insert(value)
            }
        }
        return found
    }
}
