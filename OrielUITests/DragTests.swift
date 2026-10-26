import XCTest

/// Drag and drop (phase 18). Each test makes its own workspace in session one (closed after) and checks herdr.
extension OrielUITests {
    func testDropOnACardsCenterSwapsAndOnItsEdgePlacesBeside() async throws {
        let (tabs, first) = try await newWorkspace("swap")
        let tab = tabs[0]
        let second = try await split(first), third = try await split(second)
        restoreHerdrFocusAfter()
        XCTAssertTrue(element("pane.\(third)").exists(within: 3))

        drag(first, to: card(second, 0.5, 0.6))
        try await expect("the two swapped") { try await order(tab) == [second, first, third] }
        // No highlight stays on the card now under the pointer (a hand check saw one).
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        // Its own tab's capsule is not a target: no write, so no refusal shows; the drop below checks nothing moved
        // (writes go one at a time).
        let before = try await tabIDs()
        drag(third, to: element("tab.\(tab)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(element("detail.notice").exists(within: 1))

        drag(third, to: card(second, 0.1, 0.6))
        try await expect("the pane left of its neighbor") { try await order(tab) == [third, second, first] }
        let after = try await tabIDs()
        XCTAssertEqual(after, before)
        // Its tab stayed selected, its card has the keyboard, and the three share the width, as after a split.
        XCTAssertTrue(element("tab.\(tab)").isSelected)
        XCTAssertTrue(hasKeyboard(element("terminal.\(third)")))
        try await expectWidths(tab, [third: 1 / 3, second: 1 / 3, first: 1 / 3])
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testHoldingOverACapsuleSpringLoadsItsTabAndADropSplitsRight() async throws {
        let (tabs, first) = try await newWorkspace("spring")
        let tab = tabs[0]
        let second = try await split(first)
        let created = try await Self.call(one, "tab.create", ["workspace_id": workspace(of: tab), "label": "other",
                                                              "cwd": "/tmp", "focus": false])
        let other = try id(created, "tab"), third = try id(created, "root_pane")
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

        // The same refused move onto a workspace row: only the row's spring-load selects beta.
        XCTAssertTrue(element("pane.\(third)").exists(within: 3))
        drag(third, to: element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), hold: 1.2)
        XCTAssertTrue(element("workspace.w2").has(\.isSelected, true, within: 2))
        XCTAssertTrue(notice.staticTexts["The tab is zoomed in herdr"].exists(within: 3))
        notice.buttons["notice.close"].click()
        XCTAssertTrue(notice.vanishes(within: 2))
        let unmoved = try await order(other)
        XCTAssertEqual(unmoved, [third, fourth])

        try await Self.call(one, "pane.zoom", ["pane_id": third, "mode": "off"])
        element("workspace.\(workspace(of: tab))").click()
        element("tab.\(tab)").click()
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        drag(second, to: capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await expect("the pane split right in that tab") { try await order(other) == [third, fourth, second] }
        XCTAssertTrue(capsule.has(\.isSelected, true, within: 2))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testDropsOnTheTrackEndARowTheSidebarAndItsPlusMoveThePane() async throws {
        let (tabs, first) = try await newWorkspace("moves")
        let tab = tabs[0]
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
        try await closeNew("tab", besides: tabIDs())
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
        closeNew("workspace", besides: workspaces)
        XCTAssertTrue(element("pane.\(inBeta)").exists(within: 3))
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
        try await expect("the pane in another new workspace") {
            let place = try await place(of: terminal)
            return place.map { !before.contains(workspace(of: $0.tab)) } == true
        }
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
    }

    func testDropsOnTopAndBottomEdgesStackThePanesAndOnThePlusMakeATab() async throws {
        let (tabs, first) = try await newWorkspace("edges")
        let tab = tabs[0], second = try await split(first)
        restoreHerdrFocusAfter()
        XCTAssertTrue(element("pane.\(second)").exists(within: 3))
        // Bottom: out of the row and back in under its neighbor; top: over it.
        drag(first, to: card(second, 0.5, 0.9))
        try await expectStack(tab, [second, first])
        drag(first, to: card(second, 0.5, 0.15))
        try await expectStack(tab, [first, second])

        // The `+`, as the track's end: a new tab in this workspace.
        let terminal = try await terminalID(second)
        drag(second, to: element("titlebar.new-tab").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        try await expect("the pane in a new tab of its workspace") {
            try await place(of: terminal).map { $0.tab != tab && workspace(of: $0.tab) == workspace(of: tab) } == true
        }
    }

    func testDraggingTheThirdCapsuleFirstReordersHerdrsTabs() async throws {
        let tabs = try await newWorkspace("tabs", tabs: 3).tabs
        let third = element("tab.\(tabs[2])")
        let from = third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = element("tab.\(tabs[0])").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        during(from, to: target)
        try await expect("herdr's tab order") {
            try await tabIDs().filter { $0.hasPrefix("\(workspace(of: tabs[0])):") } == [tabs[2], tabs[0], tabs[1]]
        }
    }

    /// A tab dragged onto another workspace's row moves there whole (phase 29): its terminals, split tree, ratios and
    /// label, and the page follows it. Its own workspace's row is not a target. Then back from a collapsed sidebar:
    /// held over the workspace button, the menu opens and its row takes the drop.
    func testDraggingATabOntoAWorkspaceRowOrMenuRowMovesItWithItsLayout() async throws {
        let (tabs, first) = try await newWorkspace("tabs", tabs: 2)
        let tab = tabs[0], home = workspace(of: tab)
        let second = try await split(first)
        _ = try await Self.call(one, "pane.split", ["target_pane_id": second, "direction": "down", "cwd": "/tmp",
                                                    "focus": false])
        try await Self.call(one, "layout.set_split_ratio", ["tab_id": tab, "path": [Bool](), "ratio": 0.3])
        try await Self.call(one, "layout.set_split_ratio", ["tab_id": tab, "path": [true], "ratio": 0.7])
        try await Self.call(one, "tab.rename", ["tab_id": tab, "label": "moving"])
        let layout = try await terminalLayout(tab), terminal = try await terminalID(first)
        let before = try await tabIDs()
        closeNew("tab", besides: before)
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.has(\.isHittable, true, within: 3))

        // Its own row: no move (the drag below would find no capsule).
        during(capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: element("workspace.\(home)").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertFalse(element("detail.notice").exists(within: 1))
        let stayed = try await place(of: terminal)?.tab
        XCTAssertEqual(stayed, tab)
        during(capsule.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: element("workspace.w2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let moved = try await movedTab(of: terminal, in: "w2", layout, "moving")
        let after = try await tabIDs()
        XCTAssertFalse(after.contains(tab))
        XCTAssertTrue(element("tab.\(moved)").has(\.isSelected, true, within: 3))
        XCTAssertTrue(element("workspace.w2").isSelected)
        let inBeta = try await place(of: terminal)
        let keyboard = try XCTUnwrap(inBeta).pane
        XCTAssertTrue(hasKeyboard(element("terminal.\(keyboard)")))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))

        // The collapsed sidebar's workspace menu: where its row is, then a drag held over the button and onto it.
        element("titlebar.sidebar").click()
        let button = element("titlebar.workspace")
        XCTAssertTrue(button.has(\.isHittable, true, within: 3))
        button.click()
        let row = element("workspaces.\(one).\(home)")
        XCTAssertTrue(row.exists(within: 2))
        let target = row.frame
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(row.vanishes(within: 2))
        let from = element("tab.\(moved)").frame, over = button.frame
        try await Self.post("\(one)/drag", Data("\(from.midX) \(from.midY) \(over.midX) \(over.midY) 1.2 "
                .appending("\(target.midX) \(target.midY) 0.5").utf8))
        let back = try await movedTab(of: terminal, in: home, layout, "moving")
        XCTAssertTrue(row.vanishes(within: 2))
        XCTAssertTrue(element("tab.\(back)").has(\.isSelected, true, within: 3))
        let arrived = try await place(of: terminal)
        XCTAssertTrue(try hasKeyboard(element("terminal.\(XCTUnwrap(arrived).pane)")))
        XCTAssertTrue(element("drop.indicator").vanishes(within: 2))
        element("titlebar.sidebar").click()
    }

    func testDraggingWorkspaceRowsReordersThemAndAWorktreeMovesWithItsRepository() async throws {
        let (tabs, pane) = try await newWorkspace("first")
        let first = workspace(of: tabs[0]), second = try await workspace(of: createWorkspace("second").tab)
        let firstRow = element("workspace.\(first)"), secondRow = element("workspace.\(second)")
        XCTAssertTrue(secondRow.exists(within: 3))

        during(firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        try await expect("first below second") { try await workspaceIDs().suffix(2) == [second, first] }

        // A repository with a linked worktree, last: dragged above second, its worktree comes right after it.
        let root = "/tmp/oriel-e2e-drag-\(Int.random(in: 10000 ... 99999))"
        try await send("(mkdir -p \(root) && cd \(root) && git init -q -b main repo && cd repo && "
            + "git -c user.name=e2e -c user.email=e2e@oriel commit -q --allow-empty -m one && "
            + "git worktree add -q ../tree -b feature) && echo built-$((6*7))\r", to: pane)
        addTeardownBlock { [one] in
            // Before the workspace (and its pane) closes: teardowns run last first.
            _ = try? await Self.call(one, "pane.send_text", ["pane_id": pane, "text": "rm -rf \(root)\r"])
        }
        try await waitFor(pane) { $0.contains("\nbuilt-42") }
        let repo = try await workspace(of: createWorkspace("repo", cwd: "\(root)/repo").tab)
        let tree = try await id(Self.call(one, "worktree.open", ["workspace_id": repo, "path": "\(root)/tree",
                                                                 "focus": false]), "workspace")
        closeAfter("workspace", tree)
        let repoRow = element("workspace.\(repo)")
        XCTAssertTrue(element("workspace.\(tree)").exists(within: 3))
        during(repoRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
               to: secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        try await expect("the repository and its worktree before second") {
            try await workspaceIDs().suffix(4) == [repo, tree, second, first]
        }
    }

    // MARK: - Helpers

    /// Where herdr has the terminal now.
    func place(of terminal: String) async throws -> (pane: String, tab: String)? {
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        return panes.first { $0["terminal_id"] as? String == terminal }.flatMap { pane in
            guard let id = pane["pane_id"] as? String, let tab = pane["tab_id"] as? String else { return nil }
            return (id, tab)
        }
    }

    /// The tab's split tree with each pane's terminal and the ratios to 0.01: the same after a move to another
    /// workspace, which gives the panes new ids.
    private func terminalLayout(_ tab: String) async throws -> String {
        let panes = try await snapshot()["panes"] as? [[String: Any]] ?? []
        func text(_ node: [String: Any]) -> String {
            if let id = node["pane_id"] as? String {
                return panes.first { $0["pane_id"] as? String == id }?["terminal_id"] as? String ?? id
            }
            let ratio = (node["ratio"] as? Double).map { String(format: "%.2f", $0) } ?? "?"
            return "\(node["direction"] ?? "?") \(ratio) (\(text(node["first"] as? [String: Any] ?? [:])), "
                + "\(text(node["second"] as? [String: Any] ?? [:])))"
        }
        return try await text(root(tab))
    }

    /// The terminal's tab once herdr has it in the workspace with this layout and label.
    private func movedTab(of terminal: String, in workspace: String, _ layout: String,
                          _ label: String) async throws -> String
    {
        try await poll("the tab in \(workspace) as it was") { () async throws -> String? in
            guard let tab = try await place(of: terminal)?.tab, self.workspace(of: tab) == workspace else { return nil }
            let tabs = try await snapshot()["tabs"] as? [[String: Any]] ?? []
            let same = try await terminalLayout(tab) == layout
            return same && tabs.first { $0["tab_id"] as? String == tab }?["label"] as? String == label ? tab : nil
        }
    }

    /// The tab is one split down, with these panes top to bottom.
    private func expectStack(_ tab: String, _ panes: [String]) async throws {
        try await expect("\(panes) stacked") {
            let root = try await root(tab), order = try await order(tab)
            return root["direction"] as? String == "down" && order == panes
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
