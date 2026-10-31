@testable import HerdrKit
import Testing

@Test func `a plugin label gives its plugin, iid and argument`() {
    #expect(PaneLabel("oriel:browser#m4p8sa http://localhost:3000/dashboard")
        == PaneLabel(plugin: "browser", iid: "m4p8sa", arg: "http://localhost:3000/dashboard"))
    #expect(PaneLabel("oriel:browser#m4p8sa") == PaneLabel(plugin: "browser", iid: "m4p8sa"))
    #expect(PaneLabel("oriel:kanban/board#7tt1qe")?.plugin == "kanban")
    #expect(PaneLabel("oriel:browser#m4p8sa a b")?.arg == "a b")
    #expect(PaneLabel("oriel:browser#m4p8sa   a ")?.arg == "a ")
    #expect(PaneLabel("oriel:my.plug_in-2/pane-1#m4p8sa ")?.arg == "")
    #expect(PaneLabel("oriel:browser#m4p8sa http://x")?.text == "oriel:browser#m4p8sa http://x")
    #expect(PaneLabel(plugin: "browser", iid: "m4p8sa").text == "oriel:browser#m4p8sa")
}

@Test func `a user's own label or a broken one is no plugin label`() {
    for label in [nil, "todo: fix login", "oriel:browser", "oriel:browser#ABCDEF", "oriel:browser#abc12",
                  "oriel:browser#abc1234", "oriel:Browser#abc123", "oriel:#abc123", "oriel:a/b/c#abc123",
                  "oriel:kanban/Board#abc123", "oriel:kanban/#abc123", "oriel:-a#abc123", "oriel:a#abc123\tx",
                  "oriel:a b#abc123", "oriel:browser#abc123\nx",
                  "oriel:browser#abc123 \u{1b}[2J", "oriel:browser#abc123 " + String(repeating: "x", count: 1025)]
    {
        #expect(PaneLabel(label) == nil, "\(label ?? "nil")")
    }
}

@Test func `a new iid is not one the session has`() {
    let iid = PaneLabel.newIID(taken: ["aaaaaa"])
    #expect(iid.count == 6 && iid != "aaaaaa" && iid.allSatisfy { $0.isLowercase || $0.isNumber })
    #expect(PaneLabel(plugin: "browser", iid: "m4p8sa").statePath(session: "default")
        == ".local/state/oriel/default/browser/m4p8sa.json")
}

@Test func `a Git place ends its root in a slash, so a root's last word is no source`() {
    let diff = { (label: String) in PaneLabel(label).map { "\($0.diff.root) | \($0.diff.source ?? "home")" } }
    #expect(diff("oriel:git#abc123 /x/My Project abcdef0/") == "/x/My Project abcdef0 | home")
    #expect(diff("oriel:git#abc123 /x/My Project/ abcdef0") == "/x/My Project | abcdef0")
    #expect(diff("oriel:git#abc123 /x/notes/ uncommitted") == "/x/notes | uncommitted")
    #expect(diff("oriel:git#abc123 /") == "/ | home")
    // An old Diff label's last word was always its source; an old Files label gets its slash.
    #expect(diff("oriel:diff#abc123 /x/My Project uncommitted") == "/x/My Project | uncommitted")
    #expect(PaneLabel("oriel:diff#abc123 /x/repo 1a2b3c4")?.place == "/x/repo/ 1a2b3c4")
    #expect(PaneLabel("oriel:files#abc123 /x/repo")?.place == "/x/repo/")
}
