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
        // Where the newest row sits at the bottom once the turn ended: Scroll to Bottom lands there too.
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))
        let composer = element("chat.\(pane).composer"), gap = composer.frame.minY - last.frame.maxY

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
        XCTAssertTrue(until(3) { abs(composer.frame.minY - last.frame.maxY - gap) < 2 },
                      "\(gap) \(composer.frame.minY - last.frame.maxY)")
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

    /// A long chat shows its newest rows under Show Earlier, in its own row, which adds the rows before them without
    /// moving what is in view, until the first message; they stay back at the bottom.
    func testALongChatShowsEarlierRowsInPlace() async throws {
        let pane = try await startChat().pane
        // 25 turns: about 100 rows, the newest 34 and the blocks above.
        app.typeText("many 25\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        let chat = element("chat.\(pane)"), earlier = element("chat.\(pane).earlier")
        let first = row(pane, "user", "many 25")
        XCTAssertFalse(first.exists)
        // Up to the oldest row shown, where the button is (always in the stack, so in the tree).
        func up() {
            for _ in 0 ..< 5 where !earlier.isHittable && !first.isHittable {
                chat.scroll(byDeltaX: 0, deltaY: 5000)
            }
        }
        var clicks = 0
        while !first.exists, clicks < 5 {
            up()
            clicks += 1
            guard clicks <= 2 else {
                earlier.click()
                continue
            }
            let tree = try chat.snapshot()
            var queue = [tree], nodes: [XCUIElementSnapshot] = []
            while let node = queue.popLast() {
                queue += node.children
                nodes.append(node)
            }
            let button = try XCTUnwrap(nodes.first { $0.identifier == "chat.\(pane).earlier" }).frame
            // Its own row, the rows' gap under it, not over the first row.
            let kinds = ["user", "reply", "stack", "worked"].map { "chat.\(pane).\($0)" }
            let under = try XCTUnwrap(nodes.filter { kinds.contains($0.identifier) && $0.frame.maxY > button.minY }
                .min { $0.frame.minY < $1.frame.minY })
            XCTAssertGreaterThanOrEqual(under.frame.minY - button.maxY, 10, "\(button) \(under.frame)")
            // The message at the top stays where it is.
            let top = try XCTUnwrap(nodes.filter {
                $0.identifier == "chat.\(pane).user" && $0.frame.minY >= tree.frame.minY - 1
            }.min { $0.frame.minY < $1.frame.minY })
            let (text, place) = (top.value as? String ?? "", top.frame.minY)
            earlier.click()
            let same = row(pane, "user", text)
            XCTAssertTrue(until(3) { abs(same.frame.minY - place) < 2 }, "\(text) \(place) \(same.frame)")
        }
        XCTAssertGreaterThanOrEqual(clicks, 2)
        up()
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(earlier.exists)
        // Back at the bottom by the button, then by the wheel (the user's way), the earlier rows stay.
        staysAtTheBottom(pane, first) { element("chat.\(pane).bottom").click() }
        up()
        staysAtTheBottom(pane, first) {
            for _ in 0 ..< 5 where !last.isHittable {
                chat.scroll(byDeltaX: 0, deltaY: -5000)
            }
        }
    }

    /// Slow trackpad scrolls at the end of a chat move it exactly as far as the fingers: no snap to the bottom as it
    /// comes near, no jump as it leaves, and new rows move nothing in view. A run of tool calls is as wide as a reply's
    /// bubble.
    func testTheChatsEndMovesWithTheFingers() async throws {
        let pane = try await startChat().pane
        app.typeText("many 25\r")
        let last = row(pane, "reply", "Last.")
        XCTAssertTrue(until(10) { last.exists && last.isHittable })
        XCTAssertTrue(element("chat.\(pane).send").exists(within: 5))
        let chat = element("chat.\(pane)")
        let point = "\(chat.frame.midX) \(chat.frame.midY)"
        // The fingers move `steps` × 2 pt, 16 ms apart, and rest before they lift: no momentum. How far the newest
        // reply moved, down positive.
        func swipe(_ step: Int, _ steps: Int) async throws -> CGFloat {
            let before = last.frame.minY
            _ = try await Self.post("\(one)/swipe", Data("\(point) \(step * 2) \(steps) 150 1".utf8))
            // Once it rests: the bottom's rubber band springs back.
            var now = last.frame.minY
            _ = until(2) {
                let place = last.frame.minY
                defer { now = place }
                return place == now
            }
            return now - before
        }
        // Up 30 pt from the bottom, by natural scrolling either way (the other way is the bottom's rubber band).
        var upward = 1
        var left = try await swipe(upward, 15)
        if abs(left) < 2 {
            upward = -1
            left = try await swipe(upward, 15)
        }
        // 6 pt: AppKit can draw a frame or two of its own momentum before the lift's empty one stops it (3.5 pt here).
        XCTAssertEqual(left, 30, accuracy: 6, "leaving the bottom")
        // Up past the Scroll to Bottom button's 40 pt, down past it again, down a little more, and up.
        for (direction, steps) in [(upward, 25), (-upward, 25), (-upward, 5), (upward, 10)] {
            let moved = try await swipe(direction, steps)
            XCTAssertEqual(moved, CGFloat(direction * upward * steps * 2), accuracy: 6, "\(direction) × \(steps)")
        }
        // A run and its open rows take a reply bubble's left edge and widest width: 18 pt left of the replies' text,
        // and 48 pt short of the messages' right edge, 18 pt in from the user's bubble's.
        let stacks = app.descendants(matching: .any).matching(identifier: "chat.\(pane).stack")
        let stack = stacks.element(boundBy: stacks.count - 1), user = row(pane, "user", "Question 25")
        stack.click()
        let tool = app.descendants(matching: .any).matching(identifier: "chat.\(pane).tool").firstMatch
        XCTAssertTrue(tool.exists(within: 3))
        XCTAssertEqual(stack.frame.minX, last.frame.minX - 18, accuracy: 1, "\(stack.frame) \(last.frame)")
        XCTAssertEqual(stack.frame.maxX, user.frame.maxX - 18 - 48, accuracy: 1, "\(stack.frame) \(user.frame)")
        XCTAssertEqual(tool.frame.maxX, stack.frame.maxX, accuracy: 1, "\(tool.frame) \(stack.frame)")

        // Scrolled up a little, a new turn comes below without moving what is in view: no row leaves the top.
        let place = user.frame.minY
        app.typeText("many 3\r")
        let lasts = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "chat.\(pane).reply", "Last."))
        XCTAssertTrue(until(10) { lasts.count == 2 })
        XCTAssertEqual(user.frame.minY, place, accuracy: 1)
    }

    /// After `scroll` the chat is at the bottom and stays there, with the first message still in the stack. The button
    /// goes in the same update that dropped the earlier rows, or put back the row a scroll began at (a jump back up).
    private func staysAtTheBottom(_ pane: String, _ first: XCUIElement, _ scroll: () -> Void) {
        let bottom = element("chat.\(pane).bottom"), last = row(pane, "reply", "Last.")
        scroll()
        XCTAssertTrue(bottom.vanishes(within: 3))
        XCTAssertTrue(until(3) { last.isHittable })
        XCTAssertFalse(bottom.exists)
        XCTAssertTrue(first.exists)
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
