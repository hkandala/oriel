import XCTest

/// Drag and drop (phase 18). Each test makes its own workspace in session one (closed after) and checks herdr. A drag
/// holds at its end before the drop; screenshots and checks during the hold run on the main queue, which XCUITest
/// drains while it drags.
extension OrielUITests {
    func testDropOnACardsCenterSwapsAndOnItsEdgePlacesBeside() async throws {
        let (tab, first) = try await dragWorkspace("swap")
        let second = try await split(first), third = try await split(second)
        restoreHerdrFocusAfter()
        XCTAssertTrue(element("pane.\(third)").waitForExistence(timeout: 3))

        await drag(first, to: card(second, 0.5, 0.6), shot: "drag over a center target")
        try await poll("the two swapped") { () async throws -> Bool? in
            try await order(tab) == [second, first, third] ? true : nil
        }

        let tabs = try await tabIDs()
        await drag(third, to: card(second, 0.1, 0.6), shot: "drag over an edge target")
        try await poll("the pane left of its neighbor") { () async throws -> Bool? in
            try await order(tab) == [third, second, first] ? true : nil
        }
        let after = try await tabIDs()
        XCTAssertEqual(after, tabs)
        XCTAssertTrue(hasKeyboard(element("terminal.\(third)")))

        // Its own tab's capsule is not a target: nothing moves.
        await drag(third, to: element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   shot: "drag over a not-allowed target")
        try await Task.sleep(for: .milliseconds(500))
        let still = try await order(tab)
        XCTAssertEqual(still, [third, second, first])
    }

    func testHoldingOverACapsuleSpringLoadsItsTabAndADropSplitsRight() async throws {
        let (tab, first) = try await dragWorkspace("spring")
        let second = try await split(first)
        let created = try await Self.call(one, "tab.create", ["workspace_id": workspace(of: tab), "label": "other",
                                                              "cwd": "/tmp", "focus": false])
        let other = try XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String)
        let third = try XCTUnwrap((created["root_pane"] as? [String: Any])?["pane_id"] as? String)
        let capsule = element("tab.\(other)")
        XCTAssertTrue(capsule.waitForExistence(timeout: 3))
        XCTAssertTrue(element("pane.\(second)").waitForExistence(timeout: 3))

        var springLoaded = false
        await drag(second, to: capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), hold: 1.2,
                   shot: "a spring-loaded tab") { springLoaded = capsule.isSelected }
        XCTAssertTrue(springLoaded, "the tab was not selected during the hold")
        try await poll("the pane split right in that tab") { () async throws -> Bool? in
            try await order(other) == [third, second] ? true : nil
        }
        XCTAssertTrue(capsule.isSelected)
    }

    func testDropsOnTheTrackEndAWorkspaceRowAndEmptySidebarMoveThePane() async throws {
        let (tab, first) = try await dragWorkspace("moves")
        let second = try await split(first)
        let terminal = try await terminalID(second)
        XCTAssertTrue(element("pane.\(second)").waitForExistence(timeout: 3))

        // The tab track's empty end: a new tab in this workspace (the pane keeps its id).
        let end = element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 80, dy: 0))
        await drag(second, to: end)
        let moved = try await poll("the pane in a new tab") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { $0.tab != tab && workspace(of: $0.tab) == workspace(of: tab) } == true ? place?.tab : nil
        }
        XCTAssertTrue(element("tab.\(moved)").wait(for: \.isSelected, toEqual: true, timeout: 3))

        // beta's row: a new tab there, with a new pane id.
        let betaTabs = try await tabIDs().filter { $0.hasPrefix("w2:") }
        addTeardownBlock { @MainActor in
            for id in try await self.tabIDs() where id.hasPrefix("w2:") && !betaTabs.contains(id) {
                _ = try? await Self.call(self.one, "tab.close", ["tab_id": id])
            }
        }
        await drag(second, to: element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   hold: 0.3)
        let inBeta = try await poll("the pane in a new tab of beta") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { $0.tab.hasPrefix("w2:") && !betaTabs.contains($0.tab) } == true ? place?.pane : nil
        }

        // The sidebar's empty space: a new workspace.
        let workspaces = try await workspaceIDs()
        addTeardownBlock { @MainActor in
            for id in try await self.workspaceIDs() where !workspaces.contains(id) {
                _ = try? await Self.call(self.one, "workspace.close", ["workspace_id": id, "close_group": false])
            }
        }
        XCTAssertTrue(element("pane.\(inBeta)").waitForExistence(timeout: 3))
        await drag(inBeta, to: element("sidebar").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        try await poll("the pane in a new workspace") { () async throws -> Bool? in
            let place = try await place(of: terminal)
            return place.map { !workspaces.contains(workspace(of: $0.tab)) } == true ? true : nil
        }
    }

    func testDraggingTheThirdCapsuleFirstReordersHerdrsTabs() async throws {
        let (tab, _) = try await dragWorkspace("tabs")
        let workspace = workspace(of: tab)
        var tabs = [tab]
        for label in ["two", "three"] {
            let created = try await Self.call(one, "tab.create", ["workspace_id": workspace, "label": label,
                                                                  "cwd": "/tmp", "focus": false])
            try tabs.append(XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String))
        }
        let third = element("tab.\(tabs[2])")
        XCTAssertTrue(third.waitForExistence(timeout: 3))
        let from = third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        await during(from, to: target, shot: "a tab reorder in progress")
        try await poll("herdr's tab order") { () async throws -> Bool? in
            try await tabIDs().filter { $0.hasPrefix("\(workspace):") } == [tabs[2], tabs[0], tabs[1]] ? true : nil
        }
    }

    func testDraggingWorkspaceRowsReordersThemAndAWorktreeMovesWithItsRepository() async throws {
        let (tab, pane) = try await dragWorkspace("first")
        let first = workspace(of: tab)
        let made = try await Self.call(one, "workspace.create", ["label": "second", "cwd": "/tmp", "focus": false])
        let second = try XCTUnwrap((made["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "workspace.close", ["workspace_id": second, "close_group": false])
        }
        let firstRow = element("workspace.\(first)"), secondRow = element("workspace.\(second)")
        XCTAssertTrue(secondRow.waitForExistence(timeout: 3))

        await during(firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                     to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        try await poll("first below second") { () async throws -> Bool? in
            try await workspaceIDs().suffix(2) == [second, first] ? true : nil
        }

        // A repository with a linked worktree, last: dragged above second, its worktree comes right after it.
        let root = "/tmp/oriel-e2e-drag-\(Int.random(in: 10000 ... 99999))"
        try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "(mkdir -p \(root) && cd \(root) && "
                + "git init -q -b main repo && cd repo && git -c user.name=e2e -c user.email=e2e@oriel commit -q "
                + "--allow-empty -m one && git worktree add -q ../tree -b feature) && echo built-$((6*7))\r"])
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": "w2:p1", "text": "rm -rf \(root)\r"])
        }
        try await waitFor(pane) { $0.contains("\nbuilt-42") }
        let created = try await Self.call(one, "workspace.create", ["cwd": "\(root)/repo", "label": "repo",
                                                                    "focus": false])
        let repo = try XCTUnwrap((created["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "workspace.close", ["workspace_id": repo, "close_group": true])
        }
        let opened = try await Self.call(one, "worktree.open", ["workspace_id": repo, "path": "\(root)/tree",
                                                                "focus": false])
        let tree = try XCTUnwrap((opened["workspace"] as? [String: Any])?["workspace_id"] as? String)
        let repoRow = element("workspace.\(repo)")
        XCTAssertTrue(element("workspace.\(tree)").waitForExistence(timeout: 3))
        await during(repoRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                     to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        try await poll("the repository and its worktree before second") { () async throws -> Bool? in
            try await workspaceIDs().suffix(4) == [repo, tree, second, first] ? true : nil
        }
    }

    // MARK: - Helpers

    /// A workspace of its own, closed after, selected: its tab's id and its pane's.
    func dragWorkspace(_ label: String) async throws -> (tab: String, pane: String) {
        XCTAssertTrue(element("workspace.w1").waitForExistence(timeout: connect))
        let created = try await Self.call(one, "workspace.create", ["label": label, "cwd": "/tmp", "focus": false])
        let workspace = try XCTUnwrap((created["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "workspace.close", ["workspace_id": workspace, "close_group": false])
        }
        let tab = try XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String)
        let pane = try XCTUnwrap((created["root_pane"] as? [String: Any])?["pane_id"] as? String)
        let row = element("workspace.\(workspace)")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        XCTAssertTrue(element("tab.\(tab)").waitForExistence(timeout: 3))
        return (tab, pane)
    }

    /// herdr's ids are `w<n>:t<m>`.
    func workspace(of tab: String) -> String {
        String(tab.prefix { $0 != ":" })
    }

    /// Where herdr has the terminal now.
    func place(of terminal: String) async throws -> (pane: String, tab: String)? {
        let panes = try await snapshot()?["panes"] as? [[String: Any]] ?? []
        return panes.first { $0["terminal_id"] as? String == terminal }.flatMap { pane in
            guard let id = pane["pane_id"] as? String, let tab = pane["tab_id"] as? String else { return nil }
            return (id, tab)
        }
    }

    /// A point on a card, as fractions of its size.
    func card(_ pane: String, _ across: CGFloat, _ down: CGFloat) -> XCUICoordinate {
        element("pane.\(pane)").coordinate(withNormalizedOffset: CGVector(dx: across, dy: down))
    }

    /// Drags a card by its header's title area.
    func drag(_ pane: String, to target: XCUICoordinate, hold: TimeInterval = 0.6, shot: String? = nil,
              check: (() -> Void)? = nil) async
    {
        await during(card(pane, 0, 0).withOffset(CGVector(dx: 60, dy: 17)), to: target, hold: hold, shot: shot,
                     check: check)
    }

    /// A drag that holds at `target` before the drop; halfway through the hold, a screenshot and `check`.
    func during(_ from: XCUICoordinate, to target: XCUICoordinate, hold: TimeInterval = 0.6, shot: String? = nil,
                check: (() -> Void)? = nil) async
    {
        var ran = false
        let taken = Task { @MainActor in
            // The press, the move (about 0.5 s at the default speed), then half the hold.
            try? await Task.sleep(for: .seconds(0.3 + 0.5 + hold / 2))
            ran = true
            check?()
            return shot.map { _ in XCUIScreen.main.screenshot() }
        }
        from.click(forDuration: 0.3, thenDragTo: target, withVelocity: .default, thenHoldForDuration: hold)
        if shot != nil || check != nil {
            XCTAssertTrue(ran, "the hold's check ran after the drop")
        }
        if let shot, let image = await taken.value {
            let attachment = XCTAttachment(screenshot: image)
            attachment.name = shot
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
