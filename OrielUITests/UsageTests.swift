import XCTest

/// Memory and CPU (phase 25, item 30): a workspace of 6 tabs and 12 panes, some printing as a working agent does, plus
/// session one's other 5, each shown once; then the app's footprint, CPU and herdr runs while a quiet tab shows and
/// while a busy one does (the e2e helper's `usage`, kept in the result bundle and printed).
extension OrielUITests {
    func testMemoryAndCPUOverManyTabs() async throws {
        // The working dots move, as on a Mac without Reduce Motion.
        relaunch(nil, ["-forceMotion", "YES"])
        let (tabs, _) = try await newWorkspace("usage", tabs: 6)
        var panes: [[String]] = []
        for (index, tab) in tabs.enumerated() {
            var tabPanes = try await [pane(of: tab)]
            for _ in 0 ..< index % 3 {
                try await tabPanes.append(split(tabPanes[tabPanes.count - 1]))
            }
            panes.append(tabPanes)
        }
        // The first tab stays quiet; the others' first pane prints 10 lines a second as a working agent, and the last
        // tab's three all print.
        let printing = panes.dropFirst().map { $0[0] } + panes[5].dropFirst()
        for pane in printing {
            try await waitForPrompt(pane)
            try await send("while :; do echo $RANDOM $RANDOM $RANDOM $RANDOM; sleep 0.1; done\r", to: pane)
        }
        for pane in panes.dropFirst().prefix(4).map({ $0[0] }) {
            try await report(pane, "working")
        }
        for index in tabs.indices {
            app.typeKey("\(index + 1)", modifierFlags: .command)
            try drawn(panes[index])
        }
        for workspace in ["w1", "w2", workspace(of: tabs[0])] {
            element("workspace.\(workspace)").click()
            XCTAssertTrue(element("workspace.\(workspace)").has(\.isSelected, true, within: 3))
        }
        app.typeKey("1", modifierFlags: .command)
        try drawn(panes[0])
        // The shown cards and the 4 most recently shown others keep a herdr run (D46).
        let quiet = try await measure("quiet tab")
        XCTAssertLessThanOrEqual(helpers(quiet), 1 + 4, quiet)
        app.typeKey("6", modifierFlags: .command)
        try drawn(panes[5])
        let busy = try await measure("busy tab")
        XCTAssertLessThanOrEqual(helpers(busy), 3 + 4, busy)
    }

    /// Every card of the tab drew herdr's frames.
    private func drawn(_ panes: [String]) throws {
        for pane in panes {
            let card = element("pane.\(pane)")
            XCTAssertTrue(until(5) { card.exists && !card.stringValue.contains("loading") }, "\(pane) drew")
        }
    }

    /// The `terminal session` runs in a `usage` report.
    private func helpers(_ usage: String) -> Int {
        usage.split(separator: "\n").first { $0.hasPrefix("helpers ") }.flatMap { Int($0.split(separator: " ")[1]) }
            ?? .max
    }

    /// 10 s of the app's use, in the result bundle and the log.
    private func measure(_ name: String) async throws -> String {
        let usage = try await String(decoding: Self.post("\(one)/usage", Data("10".utf8)), as: UTF8.self)
        print("usage, \(name):\n\(usage)")
        let attachment = XCTAttachment(string: usage)
        attachment.name = "usage, \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return usage
    }
}
