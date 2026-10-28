import Foundation
@testable import HerdrKit
import Testing

/// Recorded from opencode 1.19.4 (`Fixtures/opencode-*`): a session with a command allowed in a permission prompt, a
/// question, a read and an edit, plus an interrupted command from a second session; and that first session's events.
private func fixture(_ name: String, _ type: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: type, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

private let first = "ses_e7d8c818bffeiWemFHC4CGIFNZ"

private func tools(_ history: ChatHistory) -> [ChatTool] {
    history.entries.compactMap {
        if case let .tool(tool) = $0.kind {
            tool
        } else {
            nil
        }
    }
}

@Test func `opencode history gives user text, replies, tools with results, turn ends and interrupts`() throws {
    var session = OpenCodeSession(id: first)
    let loaded = try session.load(fixture("opencode-messages", "json"))
    #expect(loaded)
    let history = session.history
    #expect(history.entries.first?.kind == .user("Run the shell command: echo hi-oriel. Then reply with one word."))
    #expect(history.model == "claude-haiku-4-5")
    let tools = tools(history)
    #expect(tools.map(\.name) == ["bash", "question", "read", "edit", "bash"])
    #expect(tools[0].target == "echo hi-oriel" && tools[0].result == "hi-oriel" && tools[0].category == .command)
    #expect(tools[1].target == "Which color do you like?")
    #expect(tools[2].target == "a.txt" && tools[2].result == "1 line")
    #expect(tools[3].target == "a.txt" && tools[3].result == "+1 -1")
    #expect(tools[3].diff.map { "\($0.mark)\($0.number) \($0.text)" } == ["-1 hello", "+1 oriel was here"])
    #expect(history.entries.contains { $0.kind == .note("Interrupted", failed: false) })
    // A turn of two steps ends once, after its last reply.
    #expect(history.entries.count {
        if case .turnEnd = $0.kind {
            true
        } else {
            false
        }
    } == 4)
    let empty = session.load("{}")
    #expect(!empty)
}

@Test func `opencode events build the same history, upserting parts by id and skipping other sessions`() throws {
    var live = OpenCodeSession(id: first), other = OpenCodeSession(id: "ses_other")
    for line in try fixture("opencode-events", "jsonl").split(separator: "\n") {
        let event = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        live.apply(event)
        other.apply(event)
    }
    #expect(other.history.entries.isEmpty)
    var loaded = OpenCodeSession(id: first)
    _ = try loaded.load(fixture("opencode-messages", "json"))
    // The events are the first three turns: the same entries as the history's.
    let entries = live.history.entries
    #expect(!entries.isEmpty)
    #expect(Array(loaded.history.entries.prefix(entries.count)).map(\.kind) == entries.map(\.kind))
    #expect(tools(live.history).allSatisfy { $0.result != nil })
}

@Test func `a unified diff gives numbered lines, its headers skipped`() {
    let diff = ChatTool.DiffLine
        .unified("--- a\n+++ a\n@@ -3,2 +3,3 @@\n keep\n-old\n+new\n+more\n\\ No newline at end of file\n")
    #expect(diff.map { "\($0.mark)\($0.number) \($0.text)" } == [" 3 keep", "-4 old", "+4 new", "+5 more"])
    #expect(ChatTool.change(diff) == "+2 -1")
}
