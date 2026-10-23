import XCTest

/// Drag and drop (phase 18). Each test makes its own workspace in session one (closed after) and checks herdr.
extension OrielUITests {
    func testDropOnACardsCenterSwapsAndOnItsEdgePlacesBeside() async throws {
        let (tab, first) = try await dragWorkspace("swap")
        let second = try await split(first), third = try await split(second)
        restoreHerdrFocusAfter()
        XCTAssertTrue(element("pane.\(third)").exists(within: 3))

        drag(first, to: card(second, 0.5, 0.6))
        try await poll("the two swapped") { () async throws -> Bool? in
            try await order(tab) == [second, first, third] ? true : nil
        }
        // No highlight stays on the card now under the pointer (a hand check saw one).
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        // Its own tab's capsule is not a target: no write, so no refusal shows; the drop below checks nothing moved
        // (writes go one at a time).
        let tabs = try await tabIDs()
        drag(third, to: element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(element("detail.notice").exists(within: 1))

        drag(third, to: card(second, 0.1, 0.6))
        try await poll("the pane left of its neighbor") { () async throws -> Bool? in
            try await order(tab) == [third, second, first] ? true : nil
        }
        let after = try await tabIDs()
        XCTAssertEqual(after, tabs)
        // Its tab stayed selected, its card has the keyboard, and the three share the width, as after a split.
        XCTAssertTrue(element("tab.\(tab)").isSelected)
        XCTAssertTrue(hasKeyboard(element("terminal.\(third)")))
        try await expectWidths(tab, [third: 1 / 3, second: 1 / 3, first: 1 / 3])
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testHoldingOverACapsuleSpringLoadsItsTabAndADropSplitsRight() async throws {
        let (tab, first) = try await dragWorkspace("spring")
        let second = try await split(first)
        let created = try await Self.call(one, "tab.create", ["workspace_id": workspace(of: tab), "label": "other",
                                                              "cwd": "/tmp", "focus": false])
        let other = try XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String)
        let third = try XCTUnwrap((created["root_pane"] as? [String: Any])?["pane_id"] as? String)
        let capsule = element("tab.\(other)")
        XCTAssertTrue(capsule.exists(within: 3))
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))

        // A herdr TUI zoomed that tab: herdr refuses the move (`zoomed_tab`), so only the spring-load selects it.
        // herdr zooms only a tab with two panes or more, and its zoom moves its focus, as a swap does.
        let fourth = try await split(third)
        restoreHerdrFocusAfter()
        try await Self.call(one, "pane.zoom", ["pane_id": third, "mode": "on"])
        drag(second, to: capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), hold: 1.2)
        XCTAssertTrue(capsule.has(\.isSelected, true, within: 2))
        // The failed write's notice: a red symbol and a ✕ that closes it.
        let notice = element("detail.notice")
        XCTAssertTrue(notice.staticTexts["The tab is zoomed in herdr"].exists(within: 3))
        XCTAssertEqual(notice.images["notice.symbol"].label, "Error")
        keepScreenshot("notice")
        notice.buttons["notice.close"].click()
        XCTAssertTrue(notice.vanishes(within: 2))
        let still = try await order(tab)
        XCTAssertEqual(still, [first, second])

        try await Self.call(one, "pane.zoom", ["pane_id": third, "mode": "off"])
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        drag(second, to: capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await poll("the pane split right in that tab") { () async throws -> Bool? in
            try await order(other) == [third, fourth, second] ? true : nil
        }
        XCTAssertTrue(capsule.has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testDropsOnTheTrackEndARowTheSidebarAndItsPlusMoveThePane() async throws {
        let (tab, first) = try await dragWorkspace("moves")
        let second = try await split(first)
        let terminal = try await terminalID(second)
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))

        // The tab track's empty end: a new tab in this workspace (the pane keeps its id).
        let end = element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 80, dy: 0))
        drag(second, to: end)
        let moved = try await poll("the pane in a new tab") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { $0.tab != tab && workspace(of: $0.tab) == workspace(of: tab) } == true ? place?.tab : nil
        }
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))

        // beta's row: a new tab there, with a new pane id.
        let betaTabs = try await tabIDs().filter { $0.hasPrefix("w2:") }
        addTeardownBlock { [one] in
            for id in try await Self.ids("tab", in: one) where id.hasPrefix("w2:") && !betaTabs.contains(id) {
                _ = try? await Self.call(one, "tab.close", ["tab_id": id])
            }
        }
        drag(second, to: element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
             hold: 0.3)
        let inBeta = try await poll("the pane in a new tab of beta") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { $0.tab.hasPrefix("w2:") && !betaTabs.contains($0.tab) } == true ? place?.pane : nil
        }
        // The row's highlight goes with the drag.
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        // The sidebar's empty space: a new workspace.
        let workspaces = try await workspaceIDs()
        addTeardownBlock { [one] in
            for id in try await Self.ids("workspace", in: one) where !workspaces.contains(id) {
                _ = try? await Self.call(one, "workspace.close", ["workspace_id": id, "close_group": false])
            }
        }
        XCTAssertTrue(element("pane.\(inBeta)").exists(within: 3))
        // 40 pt under the last row.
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workspace.w'"))
        let bottom = rows.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        let sidebar = element("sidebar")
        drag(inBeta, to: sidebar.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: sidebar.frame.width / 2, dy: bottom + 40 - sidebar.frame.minY)))
        let away = try await poll("the pane in a new workspace") { () async throws -> String? in
            let place = try await place(of: terminal)
            return place.map { !workspaces.contains(workspace(of: $0.tab)) } == true ? place?.pane : nil
        }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        // The page header's `+`: a new workspace too (a full page has no empty space under its rows).
        let before = try await workspaceIDs()
        XCTAssertTrue(element("pane.\(away)").exists(within: 3))
        drag(away, to: element("sidebar.new-workspace").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await poll("the pane in another new workspace") { () async throws -> Bool? in
            let place = try await place(of: terminal)
            return place.map { !before.contains(workspace(of: $0.tab)) } == true ? true : nil
        }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
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
        XCTAssertTrue(third.exists(within: 3))
        let from = third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        during(from, to: target)
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
        XCTAssertTrue(secondRow.exists(within: 3))

        during(firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
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
            // Before the workspace (and its pane) closes: teardowns run last first.
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "rm -rf \(root)\r"])
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
        XCTAssertTrue(element("workspace.\(tree)").exists(within: 3))
        during(repoRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        try await poll("the repository and its worktree before second") { () async throws -> Bool? in
            try await workspaceIDs().suffix(4) == [repo, tree, second, first] ? true : nil
        }
    }

    // MARK: - Helpers

    /// A workspace of its own, closed after, selected: its tab's id and its pane's.
    func dragWorkspace(_ label: String) async throws -> (tab: String, pane: String) {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let created = try await Self.call(one, "workspace.create", ["label": label, "cwd": "/tmp", "focus": false])
        let workspace = try XCTUnwrap((created["workspace"] as? [String: Any])?["workspace_id"] as? String)
        addTeardownBlock { [one] in
            _ = try? await Self.call(one, "workspace.close", ["workspace_id": workspace, "close_group": false])
        }
        let tab = try XCTUnwrap((created["tab"] as? [String: Any])?["tab_id"] as? String)
        let pane = try XCTUnwrap((created["root_pane"] as? [String: Any])?["pane_id"] as? String)
        let row = element("workspace.\(workspace)")
        XCTAssertTrue(row.exists(within: 3))
        row.click()
        XCTAssertTrue(element("tab.\(tab)").exists(within: 3))
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
    func drag(_ pane: String, to target: XCUICoordinate, hold: TimeInterval = 0.6) {
        during(card(pane, 0, 0).withOffset(CGVector(dx: 60, dy: 17)), to: target, hold: hold)
    }

    /// A drag that holds at `target` before the drop. XCUITest runs nothing else while it drags (not even the main
    /// queue), so a drag in progress shows only in the run's screen recording.
    func during(_ from: XCUICoordinate, to target: XCUICoordinate, hold: TimeInterval = 0.6) {
        from.click(forDuration: 0.3, thenDragTo: target, withVelocity: .default, thenHoldForDuration: hold)
    }
}
