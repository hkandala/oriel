import Foundation
@testable import HerdrKit
import Testing

@Test func `a plugin label gives its plugin, iid and argument`() {
    #expect(PaneLabel("ovvi:browser#m4p8sa http://localhost:3000/dashboard")
        == PaneLabel(plugin: "browser", iid: "m4p8sa", arg: "http://localhost:3000/dashboard"))
    #expect(PaneLabel("ovvi:browser#m4p8sa") == PaneLabel(plugin: "browser", iid: "m4p8sa"))
    #expect(PaneLabel("ovvi:kanban/board#7tt1qe")?.plugin == "kanban")
    #expect(PaneLabel("ovvi:browser#m4p8sa a b")?.arg == "a b")
    #expect(PaneLabel("ovvi:browser#m4p8sa   a ")?.arg == "a ")
    #expect(PaneLabel("ovvi:my.plug_in-2/pane-1#m4p8sa ")?.arg == "")
    #expect(PaneLabel("ovvi:browser#m4p8sa http://x")?.text == "ovvi:browser#m4p8sa http://x")
    #expect(PaneLabel(plugin: "browser", iid: "m4p8sa").text == "ovvi:browser#m4p8sa")
}

@Test func `a user's own label or a broken one is no plugin label`() {
    for label in [nil, "todo: fix login", "ovvi:browser", "ovvi:browser#ABCDEF", "ovvi:browser#abc12",
                  "ovvi:browser#abc1234", "ovvi:Browser#abc123", "ovvi:#abc123", "ovvi:a/b/c#abc123",
                  "ovvi:kanban/Board#abc123", "ovvi:kanban/#abc123", "ovvi:-a#abc123", "ovvi:a#abc123\tx",
                  "ovvi:a b#abc123", "ovvi:browser#abc123\nx",
                  "ovvi:browser#abc123 \u{1b}[2J", "ovvi:browser#abc123 " + String(repeating: "x", count: 1025)]
    {
        #expect(PaneLabel(label) == nil, "\(label ?? "nil")")
    }
}

@Test func `a new iid is not one the session has`() {
    let iid = PaneLabel.newIID(taken: ["aaaaaa"])
    #expect(iid.count == 6 && iid != "aaaaaa" && iid.allSatisfy { $0.isLowercase || $0.isNumber })
    #expect(PaneLabel(plugin: "browser", iid: "m4p8sa").statePath(session: "default")
        == ".local/state/ovvi/default/browser/m4p8sa.json")
}

/// This Mac reads a state file itself, as a remote machine's shell reads it: trimmed, nil when missing or empty.
@Test func `a state file reads the same on This Mac and through a shell`() async throws {
    let path = ".ovvi-read-\(UUID().uuidString).json"
    let file = URL(filePath: NSHomeDirectory()).appending(path: path)
    defer { try? FileManager.default.removeItem(at: file) }
    let shell = try await RelayExec.start()
    #expect(await localExec.read(home: path) == nil)
    #expect(await shell.read(home: path) == nil)
    try Data("{\"a\":\"é\"}\n".utf8).write(to: file)
    #expect(await localExec.read(home: path) == #"{"a":"é"}"#)
    #expect(await shell.read(home: path) == #"{"a":"é"}"#)
    try Data().write(to: file)
    #expect(await localExec.read(home: path) == nil)
    #expect(await shell.read(home: path) == nil)
}

@Test func `a Git place ends its root in a slash, so a root's last word is no source`() {
    let diff = { (label: String) in PaneLabel(label)?.diffSource ?? "home" }
    #expect(diff("ovvi:git#abc123 /x/My Project abcdef0/") == "home")
    #expect(diff("ovvi:git#abc123 /x/My Project/ abcdef0") == "abcdef0")
    #expect(diff("ovvi:git#abc123 /x/notes/ uncommitted") == "uncommitted")
    #expect(diff("ovvi:git#abc123 /") == "home")
    // An old Diff label's last word was always its source; an old Files label gets its slash.
    #expect(diff("ovvi:diff#abc123 /x/My Project uncommitted") == "uncommitted")
    #expect(PaneLabel("ovvi:diff#abc123 /x/repo 1a2b3c4")?.place == "/x/repo/ 1a2b3c4")
    #expect(PaneLabel("ovvi:files#abc123 /x/repo")?.place == "/x/repo/")
}
