import XCTest

/// Runs against two throwaway herdr sessions from `make e2e`. The runner is sandboxed and cannot
/// reach herdr, so herdr calls go through the e2e helper on localhost (`scripts/e2e-helper.py`).
/// xcodebuild strips the TEST_RUNNER_ prefix from the names.
@MainActor
final class OrielUITests: XCTestCase {
    var one = ""
    var two = ""
    let app = XCUIApplication()
    /// The app's first snapshot: login shell, herdr checks and a few herdr runs; slow on CI runners.
    let connect: TimeInterval = 30

    /// Session one: w1 "alpha" with t1 = p1 | (p2 / p3) at 0.6 and t2 "second"; w2 "beta".
    /// Session two: w1 "gamma".
    override func setUp() async throws {
        continueAfterFailure = false
        one = try env("ORIEL_SESSION")
        two = try env("ORIEL_SESSION2")
        // Once per session; the runner may restart between tests, so ask herdr, not a static. The check is on
        // the last step, so a setup cut short builds again (and fails loudly) instead of passing half-built.
        let built = try await (Self.snapshot(two)["workspaces"] as? [[String: Any]] ?? [])
            .contains { $0["label"] as? String == "gamma" }
        if !built {
            try await Self.call(one, "workspace.create", ["label": "alpha", "cwd": "/tmp", "focus": false])
            try await Self.call(one, "pane.split", ["target_pane_id": "w1:p1", "direction": "right", "ratio": 0.6,
                                                    "cwd": "/tmp", "focus": false])
            try await Self.call(one, "pane.split", ["target_pane_id": "w1:p2", "direction": "down",
                                                    "cwd": "/tmp", "focus": false])
            try await Self.call(one, "tab.create", ["workspace_id": "w1", "label": "second", "cwd": "/tmp",
                                                    "focus": false])
            try await Self.call(one, "workspace.create", ["label": "beta", "cwd": "/tmp", "focus": false])
            try await Self.call(two, "workspace.create", ["label": "gamma", "cwd": "/tmp", "focus": false])
        }
        relaunch()
    }

    /// The pointer goes off the title row: left on a capsule, it would open a hover card in the next test's launch.
    /// Not async: a failure stops an async test inside the main actor's job, and an async tearDown then waits for
    /// the main actor until the 2-minute allowance runs out.
    /// The main window: the first match can be a floating window that a teardown block's close is closing, with no
    /// frame (an INFINITY point, CI 40294678064).
    override func tearDown() {
        let main = app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'main-'")).firstMatch
        if main.exists {
            main.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.9)).hover()
        }
    }

    func testShowsWorkspacesTabsAndSplits() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        XCTAssertTrue(element("workspace.w2").exists)
        XCTAssertTrue(element("tab.w1:t1").exists)
        XCTAssertTrue(element("tab.w1:t2").exists)
        // At launch no text field has the keyboard; a terminal has it.
        XCTAssertEqual(app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == true")).count, 0)
        XCTAssertNotEqual(element("sidebar.filter").elementType, .textField)

        // p1 | (p2 / p3): p1 on the left with about 60 % of the width, p2 above p3.
        let first = element("pane.w1:p1").frame, second = element("pane.w1:p2").frame
        let third = element("pane.w1:p3").frame
        XCTAssertLessThan(first.maxX, second.minX)
        XCTAssertEqual(first.width / (first.width + second.width), 0.6, accuracy: 0.03)
        XCTAssertLessThan(second.maxY, third.minY)
        XCTAssertLessThan(first.maxX, third.minX)
        keepScreenshot("split")

        element("tab.w1:t2").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        XCTAssertTrue(app.windows.firstMatch.has(\.title, "second - \(one)", within: 2))

        element("workspace.w2").click()
        XCTAssertTrue(element("page.w2:t1").exists(within: 2))
        XCTAssertFalse(element("page.w1:t1").exists)
        XCTAssertTrue(element("pane.w2:p1").exists)
        keepScreenshot("second workspace")
    }

    /// Each workspace keeps its own selected tab; coming back shows it, with the marker on it.
    func testWorkspaceKeepsItsSelectedTab() {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        element("tab.w1:t2").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        element("workspace.w2").click()
        XCTAssertTrue(element("pane.w2:p1").has(\.isHittable, true, within: 2))
        XCTAssertFalse(element("tab.w1:t2").exists)
        element("workspace.w1").click()
        XCTAssertTrue(element("pane.w1:p4").has(\.isHittable, true, within: 2))
        XCTAssertTrue(element("tab.w1:t2").isSelected)
        XCTAssertTrue(until(2) { element("tab.w1:t2").stringValue.hasPrefix("in view") })
    }

    func testSidebarFilterNarrowsTheWorkspaces() {
        XCTAssertTrue(element("workspace.w1").exists(within: connect))
        let filter = element("sidebar.filter")
        filter.click()
        XCTAssertTrue(hasKeyboard(filter))
        filter.typeText("bet")
        XCTAssertTrue(element("workspace.w1").vanishes(within: 2))
        XCTAssertTrue(element("workspace.w2").exists)
        keepScreenshot("sidebar filter")
    }

    func testSplitButtonAddsAPane() async throws {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await newTab("split")
        element("tab.\(tab)").click()
        XCTAssertTrue(element("page.\(tab)").has(\.isHittable, true, within: 3))
        hoverHeader(pane)
        element("pane.\(pane).split-right").click()

        // The app draws a second card to the right of the first, and herdr has two panes in the tab.
        let cards = element("page.\(tab)").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", #"pane\.[^.]+"#))
        XCTAssertTrue(cards.element(boundBy: 1).exists(within: 2))
        XCTAssertLessThan(cards.element(boundBy: 0).frame.maxX, cards.element(boundBy: 1).frame.minX)
        let panes = try await snapshot()["panes"] as? [[String: Any]]
        XCTAssertEqual(panes?.count { $0["tab_id"] as? String == tab }, 2)
        keepScreenshot("split")
    }

    func testSelectsAnotherTabWhenTheSelectedOneCloses() async throws {
        XCTAssertTrue(element("tab.w1:t2").exists(within: connect))
        let (tab, _) = try await newTab("doomed", in: "w1")
        let row = element("tab.\(tab)")
        row.click()
        XCTAssertTrue(row.has(\.isSelected, true, within: 2))

        try await Self.call(one, "tab.close", ["tab_id": tab])
        XCTAssertTrue(row.vanishes(within: 2))
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.w1:' AND selected == true"))
        XCTAssertTrue(selected.firstMatch.exists(within: 2))
        let page = element("page.\(selected.firstMatch.identifier.dropFirst("tab.".count))")
        XCTAssertTrue(page.has(\.isHittable, true, within: 2))
    }
}

extension OrielUITests {
    /// `stty size` in the pane prints the grid its card shows (the terminal's accessibility value), in this window
    /// when there are several.
    func expectPTYSize(_ pane: String, in window: XCUIElement? = nil) async throws {
        let terminal = element("terminal.\(pane)", in: window)
        try await waitForPrompt(pane)
        try await poll("stty size in \(pane) to match its card", times: 30) { () async throws -> String? in
            guard terminal.exists, let grid = terminal.value as? String, !grid.isEmpty else { return nil }
            try await send("clear; stty size\r", to: pane)
            try await Task.sleep(for: .milliseconds(200))
            return try await read(pane).split(separator: "\n").contains { $0 == grid } ? grid : nil
        }
    }

    func waitForPrompt(_ pane: String) async throws {
        try await waitFor(pane) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Polls the pane's text until `done` passes. Escaping: the compiler rejects it otherwise across files.
    /// The failure says what the pane showed last.
    func waitFor(_ pane: String, times: Int = 50, _ done: @escaping (String) -> Bool) async throws {
        var last = ""
        do {
            try await poll("pane \(pane) to show it", times: times) { () async throws -> String? in
                last = try await read(pane)
                return done(last) ? last : nil
            }
        } catch is Waited {
            throw Waited(description: "waited for pane \(pane) to show it; it showed:\n\(last)")
        }
    }

    /// `probe` every 100 ms until it gives a value (a predicate expectation checks only about once a second); the
    /// test fails after `times` tries.
    @discardableResult
    func poll<Value>(_ what: String, times: Int = 50,
                     _ probe: () async throws -> Value?) async throws -> Value
    {
        for _ in 0 ..< times {
            if let value = try await probe() {
                return value
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // A throw, not XCTFail: XCTFail in async code stops the test inside the main actor's job, where its async
        // teardown blocks wait for the main actor until the 2-minute allowance runs out.
        throw Waited(description: "waited for \(what)")
    }

    /// Polls until `check` passes.
    func expect(_ what: String, times: Int = 50, _ check: () async throws -> Bool) async throws {
        try await poll(what, times: times) { try await check() ? true : nil }
    }

    struct Waited: Error, CustomStringConvertible {
        let description: String
    }

    func env(_ name: String) throws -> String {
        try XCTUnwrap(ProcessInfo.processInfo.environment[name], "run through make e2e")
    }

    /// Launches the app on the session (one by default) with no window state from earlier runs; `launch` ends a
    /// running one first.
    func relaunch(_ session: String? = nil, _ args: [String] = []) {
        app.launchArguments = ["-session", session ?? one, "-ApplePersistenceIgnoreState", "YES"] + args
        app.launch()
    }

    /// Swipes sideways over the element until the target has the value, one way and then the other: which sign goes
    /// forward follows the natural scrolling setting (one way here, the other on CI), and past the last page nothing
    /// moves.
    func swipe<Value: Equatable>(_ element: XCUIElement, by distance: Double? = nil, until target: XCUIElement,
                                 _ property: KeyPath<XCUIElement, Value>, _ value: Value) async throws
    {
        var delta = -(distance ?? Double(element.frame.width))
        for _ in 0 ..< 6 {
            element.hover()
            element.scroll(byDeltaX: delta, deltaY: 0)
            delta = -delta
            if target.has(property, value, within: 0.7) {
                return
            }
        }
        throw Waited(description: "waited for the swipe over \(element.identifier)")
    }

    /// Shows a card's header buttons. Over the header, not the card's center: SwiftUI does not see the
    /// pointer jump straight into a terminal view, which takes the mouse moves.
    func hoverHeader(_ pane: String) {
        element("pane.\(pane)").coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 17)).hover()
    }

    /// A new tab (closed after the test), its workspace selected so its capsule shows: its id and
    /// its pane's. By default in w2, another workspace than the one selected at launch.
    func newTab(_ label: String, in workspace: String = "w2") async throws -> (tab: String, pane: String) {
        let created = try await Self.call(one, "tab.create", ["workspace_id": workspace, "label": label,
                                                              "cwd": "/tmp", "focus": false])
        let tab = try id(created, "tab"), pane = try id(created, "root_pane")
        closeAfter("tab", tab)
        let row = element("workspace.\(workspace)")
        if !row.isSelected {
            row.click()
        }
        // Hittable and at rest, not only there: the capsule slides in, and the bar lays out again after a workspace
        // change; a click on an earlier frame went beside it (CI 40319705774).
        let capsule = element("tab.\(tab)")
        XCTAssertTrue(capsule.has(\.isHittable, true, within: 2))
        var frame = CGRect.null
        XCTAssertTrue(until(2) {
            defer { frame = capsule.frame }
            return capsule.frame == frame
        })
        return (tab, pane)
    }

    /// createWorkspace with this many tabs, selected so its capsules show: its tabs' ids and its first pane's.
    func newWorkspace(_ label: String, tabs count: Int = 1) async throws -> (tabs: [String], pane: String) {
        XCTAssertTrue(element("workspace.w2").exists(within: connect))
        let (tab, pane) = try await createWorkspace(label)
        let workspace = workspace(of: tab)
        var tabs = [tab]
        for _ in 1 ..< count {
            try await tabs.append(id(Self.call(one, "tab.create", ["workspace_id": workspace, "cwd": "/tmp",
                                                                   "focus": false]), "tab"))
        }
        let row = element("workspace.\(workspace)")
        XCTAssertTrue(row.exists(within: 3))
        row.click()
        XCTAssertTrue(element("tab.\(tabs[count - 1])").exists(within: 3))
        return (tabs, pane)
    }

    /// Types a command into the pane once its terminal has the keyboard, and waits for the output.
    func typeAndRead(_ pane: String) async throws {
        XCTAssertTrue(hasKeyboard("terminal.\(pane)"))
        app.typeText("echo oriel-keys-$((6*7))")
        app.typeKey(.return, modifierFlags: [])
        try await waitFor(pane) { $0.contains("\noriel-keys-42") }
    }

    /// ⌘K; the palette's filter has the keyboard.
    @discardableResult
    func openPalette() -> XCUIElement {
        app.typeKey("k", modifierFlags: .command)
        let filter = element("palette.filter")
        XCTAssertTrue(hasKeyboard(filter))
        return filter
    }

    /// For people reviewing a run: the window (brought to the front when given), in the result bundle.
    func keepScreenshot(_ name: String, of window: XCUIElement? = nil) {
        if let window {
            raise(window)
        }
        let attachment = XCTAttachment(screenshot: (window ?? app.windows.firstMatch).screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits for the element to take the keyboard; focus lands a moment after it appears.
    /// By one query a try: `exists` and then a focus read found a terminal gone between the two as its floating window
    /// came forward, which XCUITest fails the test for (CI 40335691646, 40342555702).
    func hasKeyboard(_ identifier: String, in window: XCUIElement? = nil) -> Bool {
        let focused = NSPredicate(format: "identifier == %@ AND hasKeyboardFocus == true", identifier)
        return until(2) { (window ?? app).descendants(matching: .any).matching(focused).firstMatch.exists }
    }

    func hasKeyboard(_ element: XCUIElement) -> Bool {
        let focus = NSPredicate(format: "hasKeyboardFocus == true")
        return until(2) { element.exists && focus.evaluate(with: element) }
    }

    /// In this window when there are several.
    func element(_ identifier: String, in window: XCUIElement? = nil) -> XCUIElement {
        (window ?? app).descendants(matching: .any)[identifier]
    }
}

/// XCTest's own waits (waitForExistence, wait(for:toEqual:), predicate expectations) check about once a second
/// and take over a second even when the condition already holds; these check every 100 ms (plan/ci.md, Speed).
extension XCUIElement {
    func exists(within timeout: TimeInterval) -> Bool {
        until(timeout) { exists }
    }

    func vanishes(within timeout: TimeInterval) -> Bool {
        until(timeout) { !exists }
    }

    /// Reading a property of a missing element fails the test, so it waits for the element first.
    func has<Value: Equatable>(_ property: KeyPath<XCUIElement, Value>, _ value: Value,
                               within timeout: TimeInterval) -> Bool
    {
        until(timeout) { exists && self[keyPath: property] == value }
    }

    var stringValue: String {
        value as? String ?? ""
    }
}

/// Checks every 100 ms until `check` passes; false when `timeout` runs out first.
func until(_ timeout: TimeInterval, _ check: () -> Bool) -> Bool {
    let end = Date.now + timeout
    while !check() {
        guard Date.now < end else { return false }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return true
}
