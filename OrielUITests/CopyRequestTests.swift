import XCTest

/// Copy requests (talking-to-herdr#copy-requests): a program asks Oriel to copy through herdr's pane metadata.
extension OrielUITests {
    /// A copy request on a pane, as pi-hkandala's extensions send it, puts its file's text on the clipboard and
    /// deletes the file. This Mac's panes are marked `1`, which tells them to copy with pbcopy.
    func testACopyRequestReachesTheClipboard() async throws {
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await requestCopy(on: "w1:p1", marked: "1")
    }

    /// The pane carries the mark, then writes the text to the request's file on its machine, and the request names it.
    func requestCopy(on pane: String, marked mark: String) async throws {
        try await expect("\(pane) marked \(mark)") {
            let info = try await Self.call(one, "pane.get", ["pane_id": pane])["pane"] as? [String: Any]
            return (info?["tokens"] as? [String: String])?["oriel-shown"] == mark
        }
        try await waitForPrompt(pane)
        // The user's clipboard, every type of it, back after the test.
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
        NSPasteboard.general.clearContents()
        let id = UUID().uuidString.lowercased()
        try await send("printf 'copy-%s\\n✓ two' $((6*7)) >/tmp/oriel-copy-\(id) && echo saved-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("\nsaved-42") }
        try await Self.call(one, "pane.report_metadata", [
            "pane_id": pane, "source": "e2e", "ttl_ms": 1000, "tokens": ["oriel-copy": id],
        ])
        try await expect("the copy on the clipboard") {
            NSPasteboard.general.string(forType: .string) == "copy-42\n✓ two"
        }
        try await send("test -e /tmp/oriel-copy-\(id) || echo gone-$((6*7))\r", to: pane)
        try await waitFor(pane) { $0.contains("\ngone-42") }
    }

    /// A copy request from Key Host's pane: marked `remote`, and Oriel reads the file over the relay.
    func testARemoteMachinesCopyRequestReachesTheClipboard() async throws {
        try await skipWithoutSSH()
        relaunch(one, ["-machines", Self.keyHost, "-machine", "e2e-key"])
        XCTAssertTrue(element("terminal.w1:p1").exists(within: connect))
        try await requestCopy(on: "w1:p1", marked: "remote")
    }
}
