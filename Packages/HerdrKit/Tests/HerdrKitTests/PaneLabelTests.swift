@testable import HerdrKit
import Testing

@Test func `a plugin label gives its plugin, iid and argument`() {
    #expect(PaneLabel("oriel:browser#m4p8sa http://localhost:3000/dashboard")
        == PaneLabel(plugin: "browser", iid: "m4p8sa", arg: "http://localhost:3000/dashboard"))
    #expect(PaneLabel("oriel:browser#m4p8sa") == PaneLabel(plugin: "browser", iid: "m4p8sa"))
    #expect(PaneLabel("oriel:kanban/board#7tt1qe")?.plugin == "kanban")
    #expect(PaneLabel("oriel:browser#m4p8sa a b")?.arg == "a b")
    #expect(PaneLabel("oriel:browser#m4p8sa http://x")?.text == "oriel:browser#m4p8sa http://x")
    #expect(PaneLabel(plugin: "browser", iid: "m4p8sa").text == "oriel:browser#m4p8sa")
}

@Test func `a user's own label or a broken one is no plugin label`() {
    for label in [nil, "todo: fix login", "oriel:browser", "oriel:browser#ABCDEF", "oriel:browser#abc12",
                  "oriel:browser#abc1234", "oriel:Browser#abc123", "oriel:#abc123", "oriel:a/b/c#abc123",
                  "oriel:kanban/Board#abc123",
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
