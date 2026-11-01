import XCTest

/// The `oriel` command (agent-control/cli): typed in a pane, it asks the Oriel that follows the session through herdr
/// and the machine's mailbox.
extension OrielUITests {
    /// The script that Oriel writes on each machine it opens a session on.
    static let orielCommand = "~/.cache/oriel/bin/oriel"

    /// status from herdr's tokens, float and unfloat with their windows (also of a session with no page, whose
    /// workspaces are marked while it floats), errors as text and JSON, copy onto the clipboard; once Oriel quits, its
    /// marks go and the command exits 3.
    func testTheOrielCommandFloatsCopiesAndSaysWhereItIs() async throws {
        let (tab, first) = try await newTab("oriel")
        let second = try await split(first)
        element("tab.\(tab)").click()
        XCTAssertTrue(element("terminal.\(second)").exists(within: 3))
        try await waitForPrompt(first)
        try await expectOpen("w2")
        let oriel = Self.orielCommand
        try await run("\(oriel) status", in: first, "status", 0, "Shown in Oriel")

        try await run("\(oriel) float \(second) --on-top", in: first, "float", 0, "existing: false", "onTop: true")
        let window = app.windows.containing(.any, identifier: "float.\(second)").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        XCTAssertTrue(element("float.\(second).pin").has(\.stringValue, "on", within: 3))
        try await run("\(oriel) float \(second)", in: first, "again", 0, "existing: true")
        try await run("\(oriel) unfloat \(second)", in: first, "unfloat", 0, "floating: false")
        XCTAssertTrue(window.vanishes(within: 3))
        try await run("\(oriel) unfloat \(second)", in: first, "not", 1, "oriel: pane \(second) does not float")
        // `tr`: the JSON is wider than the pane. `exit`: the command's code, not tr's.
        try await run("j=$(\(oriel) --json unfloat \(second)); s=$?; echo \"$j\" | tr , '\\n'; (exit $s)", in: first,
                      "json", 1, #"{"error":{"code":"not_floating""#)
        try await run("\(oriel) float \(two)/w1:p1", in: first, "other", 0, "floating: true")
        try await expectOpen("w1", in: two)
        try await run("\(oriel) unfloat \(two)/w1:p1", in: first, "back", 0, "floating: false")
        try await expectOpen("w1", false, in: two)
        try await run("\(oriel) float", in: first, "usage", 2, "oriel: missing <pane>")

        keepClipboard()
        NSPasteboard.general.clearContents()
        try await run("printf 'copy-%s\\n✓ two' $((6*7)) | \(oriel) copy", in: first, "copy", 0)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copy-42\n✓ two")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        try await expectOpen("w2", false)
        try await run("\(oriel) status", in: first, "gone", 3, "Not in Oriel")
        try await run("\(oriel) info", in: first, "none", 3, "oriel: no Oriel shows")
    }

    /// The `oriel` command on Key Host (RemoteTests' sshd, CI only): Oriel writes the script there, hears the ring over
    /// the relay, takes the request
    /// from that machine's mailbox and floats the pane in this Mac's window.
    func testTheOrielCommandWorksOnARemoteMachine() async throws {
        try await skipWithoutSSH()
        // CI's sshd has this Mac's home: an older script that only the Key Host store can replace, written once this
        // Mac's Oriel, which may still be writing its own, is gone.
        try await waitForPrompt("w1:p1")
        app.terminate()
        try await run("printf '#!/bin/sh\\n# oriel-cli 0\\n' >\(Self.orielCommand)", in: "w1:p1", "old", 0)
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await waitForPrompt("w1:p1")
        try await expectOpen("w1")
        let oriel = Self.orielCommand
        // The Key Host store writes it once its session opens, beside its first marks.
        try await run("until ! grep -qx '# oriel-cli 0' \(oriel); do sleep 0.1; done", in: "w1:p1", "new", 0)
        try await run("\(oriel) status --json | tr , '\\n'", in: "w1:p1", "status", 0, "\"remote\":true")
        try await run("\(oriel) info", in: "w1:p1", "info", 0, "machine: Key Host")
        try await run("\(oriel) float w1:p2", in: "w1:p1", "float", 0, "floating: true")
        let window = app.windows.containing(.any, identifier: "float.w1:p2").firstMatch
        XCTAssertTrue(window.exists(within: 5))
        try await run("\(oriel) unfloat w1:p2", in: "w1:p1", "unfloat", 0, "floating: false")
        XCTAssertTrue(window.vanishes(within: 3))
    }

    /// Types the command in the pane, then `echo ‹marker›-$?`: waits for the marker with the exit code, and checks the
    /// lines the command printed, each by its start: a line wider than the pane wraps (CI's are about 50 columns).
    func run(_ command: String, in pane: String, _ marker: String, _ code: Int, _ lines: String...) async throws {
        try await send("\(command); echo \(marker)-$((6*7))-$?\r", to: pane)
        // Exit 3 comes after the 3 s the command waits for a take.
        try await waitFor(pane, times: 100) { $0.contains("\n\(marker)-42-") }
        let text = try await read(pane)
        XCTAssertTrue(text.contains("\n\(marker)-42-\(code)"), text)
        for line in lines {
            XCTAssertTrue(text.contains("\n\(line)"), "\(line) in:\n\(text)")
        }
    }

    /// The workspace carries Oriel's `oriel-open` mark, or not.
    func expectOpen(_ workspace: String, _ open: Bool = true, in session: String? = nil) async throws {
        try await expect("\(workspace) marked \(open ? "" : "not ")open") {
            let info = try await Self.call(session ?? one, "workspace.get", ["workspace_id": workspace])["workspace"]
            return ((info as? [String: Any])?["tokens"] as? [String: String])?["oriel-open"] == (open ? "1" : nil)
        }
    }

    /// The user's clipboard, every type of it, back after the test.
    func keepClipboard() {
        let saved = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        addTeardownBlock {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types {
                    item.setData(data, forType: type)
                }
                return item
            })
        }
    }
}
