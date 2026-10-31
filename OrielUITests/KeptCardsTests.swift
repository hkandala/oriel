import XCTest

/// What kept cards cost (on demand): a workspace whose first tab shows a terminal beside a browser, then `kept`
/// terminal tabs and `kept` web tabs (browsers on local pages and Markdown cards, half each), each shown once, so the
/// kept sets are full; then the app at rest on the first tab, in use (tab switches), and with the overview open (its
/// open's latency, then CPU and memory). The numbers are in the result bundle (`usage, …` and `latency`).
extension OrielUITests {
    func testKeptCardsCost() async throws {
        try await keptCardsCost(20)
    }

    func testManyKeptCardsCost() async throws {
        try await keptCardsCost(40)
    }

    private func keptCardsCost(_ kept: Int) async throws {
        executionTimeAllowance = 1200
        relaunch(nil, ["-spareTerminals", "\(kept)", "-spareWebCards", "\(kept)", "-recordLatency", "YES"])
        addTeardownBlock { @MainActor in self.keep(self.element("app.latency").stringValue, as: "latency") }
        let opened = try await keptTabs(kept)
        // Each tab once, by Show Next Tab, until its card shows; then back to the first.
        XCTAssertTrue(element("tab.\(opened.last?.0 ?? "")").exists(within: 10))
        app.typeKey("1", modifierFlags: .command)
        for (tab, pane) in opened.dropFirst() {
            app.typeKey("]", modifierFlags: [.command, .shift])
            XCTAssertTrue(element("tab.\(tab)").has(\.isSelected, true, within: 5), tab)
            XCTAssertTrue(element("pane.\(pane)").exists(within: 10), pane)
        }
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element("tab.\(opened[0].0)").has(\.isSelected, true, within: 5))
        try await Task.sleep(for: .seconds(10))
        _ = try await measure("at rest, \(kept) + \(kept) kept")
        // In use: a tab switch every half second.
        async let use = measure("in use, \(kept) + \(kept) kept", seconds: 10)
        for step in 0 ..< 20 {
            app.typeKey(step % 4 < 2 ? "]" : "[", modifierFlags: [.command, .shift])
            try await Task.sleep(for: .milliseconds(500))
        }
        _ = try await use
        app.typeKey("1", modifierFlags: .command)
        try await Task.sleep(for: .seconds(3))
        app.typeKey("o", modifierFlags: [.command, .control])
        XCTAssertTrue(element("overview").exists(within: 5))
        _ = try await measure("overview, \(kept) + \(kept) kept", seconds: 5)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("overview").vanishes(within: 5))
    }

    /// A workspace of a terminal beside a browser, then terminal and web tabs in turn: each tab and its pane.
    private func keptTabs(_ kept: Int) async throws -> [(String, String)] {
        let (tabs, shell) = try await newWorkspace("kept")
        let workspace = workspace(of: tabs[0]), folder = "/tmp/oriel-e2e-kept"
        try await waitForPrompt(shell)
        // Pages with some text to lay out, a different one per card.
        try await send("mkdir -p \(folder) && cd \(folder) && for i in $(seq 0 \(kept)); do { echo \"<title>Page $i"
            + "</title><h1>Page $i</h1>\"; for j in $(seq 300); do echo \"<p>Paragraph $j of page $i, words to lay "
            + "out and paint.</p>\"; done; } >$i.html; { echo \"# Notes $i\"; for j in $(seq 300); do echo \"- Line $j "
            + "of notes $i, *some* \\`code\\` and text.\"; done; } >$i.md; done; clear; echo made-$((1+1))\r",
            to: shell)
        try await waitFor(shell, times: 200) { $0.contains("made-2") }
        func leaf(_ kind: String, _ arg: String) -> [String: Any] {
            let iid = String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(6))
            return ["type": "pane", "cwd": folder, "label": "oriel:\(kind)#\(iid) \(arg)",
                    "command": ["sh", "-c", "cat", "sh"]]
        }
        let browser = try await split(shell)
        try await Self.call(one, "pane.rename", ["pane_id": browser,
                                                 "label": leaf("browser", "file://\(folder)/0.html")["label"] ?? ""])
        // Terminals and web cards in turn.
        var opened = [(tabs[0], browser)]
        for index in 1 ... 2 * kept {
            let web = index.isMultiple(of: 2), page = (index + 1) / 2
            let root = web ? leaf(page.isMultiple(of: 2) ? "browser" : "markdown",
                                  page.isMultiple(of: 2) ? "file://\(folder)/\(page).html" : "\(folder)/\(page).md")
                : ["type": "pane", "cwd": "/tmp"]
            let layout = try await Self.call(one, "layout.apply", ["workspace_id": workspace, "focus": false,
                                                                   "root": root])["layout"] as? [String: Any]
            let pane = (layout?["root"] as? [String: Any])?["pane_id"] as? String ?? ""
            try opened.append((field(layout?["tab_id"], "tab"), pane))
        }
        return opened
    }
}
