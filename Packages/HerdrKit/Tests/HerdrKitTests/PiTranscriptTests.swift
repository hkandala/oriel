import Foundation
@testable import HerdrKit
import Testing

/// Real pi 1.4.0 sessions, cut down (`Fixtures/pi-*.jsonl`): `pi-session` has a read, a failed command, a write, a
/// `!` command and an interrupt; `pi-tree` has five failed tries, a turn with an edit, then a `/tree` back to the last
/// failed try and a turn on that branch.
private func transcript(_ name: String, upTo last: String? = nil) throws -> (PiTranscript, ChatHistory) {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    var transcript = PiTranscript(), history = ChatHistory()
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        let read = transcript.read(String(line), into: &history)
        #expect(read)
        if let last, line.contains("\"id\":\"\(last)\"") {
            break
        }
    }
    return (transcript, history)
}

private extension ChatHistory {
    var users: [String] {
        entries.compactMap(\.user)
    }

    var tools: [ChatTool] {
        entries.compactMap(\.tool)
    }

    var notes: [String] {
        entries.compactMap {
            if case let .note(text, _) = $0.kind {
                text
            } else {
                nil
            }
        }
    }
}

@Test func `pi session gives user text, replies, tools with their results and notes`() throws {
    let history = try transcript("pi-session").1
    #expect(history.users == ["Read a.txt with your read tool, then run the bash command 'ls /nonexistent', then "
            + "write b.txt containing two lines x and y, then reply with one short sentence.",
        "Run bash 'sleep 20' then say ok"])
    #expect(history.model == "claude-opus-5-5")
    let tools = history.tools
    #expect(tools.map(\.name) == ["read", "bash", "write", "bash", "bash"])
    #expect(tools.allSatisfy { $0.result != nil })
    #expect(tools[0].category == .read && tools[0].target == "a.txt" && tools[0].result == "1 line")
    #expect(tools[1].failed && tools[1].target == "ls /nonexistent" && tools[1].result == "exit 1")
    // The `!` command.
    #expect(tools[3].target == "echo bang" && tools[3].result == "exit 0" && !tools[3].failed)
    #expect(history.notes == ["Interrupted"])
    #expect(history.entries.contains { $0.kind == ChatEntry.Kind.reply(
        "a.txt contains \"bye\", `ls /nonexistent` failed because the directory doesn't exist, and I wrote b.txt "
            + "with the lines x and y.",
    ) })
}

@Test func `pi edit results carry their diff`() throws {
    let edit = try #require(transcript("pi-tree", upTo: "19d90989").1.tools.first { $0.name == "edit" })
    #expect(edit.category == .edit && edit.target == "a.txt" && edit.result == "+1 -1")
    #expect(edit.diff.map { "\($0.mark)\($0.number) \($0.text)" } == ["-1 hi", "+1 bye"])
}

@Test func `the history is the branch from the leaf, also after a tree move`() throws {
    // Before the move: five failed tries, then the turn with the edit.
    var (tree, history) = try transcript("pi-tree", upTo: "19d90989")
    #expect(history.users.count == 2)
    #expect(history.notes.count == 5)
    #expect(history.entries.last?.kind == ChatEntry.Kind.reply("done"))

    // /tree back to the last failed try: the edit turn goes.
    tree.move(to: "6636acff", into: &history)
    #expect(history.users.count == 1)
    #expect(history.notes.count == 5)
    #expect(history.tools.isEmpty)

    // The next turn grows from there.
    let whole = try transcript("pi-tree").1
    #expect(whole.users == ["Run the bash command 'echo hi > a.txt', then edit a.txt replacing hi with bye, then reply "
            + "with just: done", "Reply with just: branched"])
    #expect(whole.entries.last?.kind == ChatEntry.Kind.reply("branched"))
    #expect(!whole.entries.contains { $0.kind == ChatEntry.Kind.reply("done") })
}

@Test func `a read from the middle of the file starts at its first whole entry`() {
    var transcript = PiTranscript(), history = ChatHistory()
    let torn = transcript.read("art of a line\"}}", into: &history)
    #expect(!torn)
    let user = #"{"type":"message","id":"b","parentId":"a","timestamp":"2026-10-28T12:00:00.000Z","#
        + #""message":{"role":"user","content":"hello"}}"#
    let read = transcript.read(user, into: &history)
    #expect(read && history.users == ["hello"])
}
