import Foundation
@testable import HerdrKit
import Testing

/// Real pi 1.4.0 sessions, cut down (`Fixtures/pi-*.jsonl`): `pi-session` has a read, a failed command, a write, a
/// `!` command and an interrupt; `pi-tree` has five failed tries, a turn with an edit, then a `/tree` back to the last
/// failed try and a turn on that branch.
private struct Read {
    var transcript: PiTranscript
    var history: ChatHistory
    /// Where the read stopped, in bytes.
    let end: Int
}

private func transcript(_ name: String, upTo last: String? = nil, into transcript: PiTranscript = PiTranscript())
    throws -> Read
{
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    var transcript = transcript, history = ChatHistory(), end = 0
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        end += line.utf8.count + 1
        let read = transcript.read(String(line), end: end, into: &history)
        #expect(read)
        if let last, line.contains("\"id\":\"\(last)\"") {
            break
        }
    }
    return Read(transcript: transcript, history: history, end: end)
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
    let history = try transcript("pi-session").history
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
    let edit = try #require(transcript("pi-tree", upTo: "19d90989").history.tools.first { $0.name == "edit" })
    #expect(edit.category == .edit && edit.target == "a.txt" && edit.result == "+1 -1")
    #expect(edit.diff.map { "\($0.mark)\($0.number) \($0.text)" } == ["-1 hi", "+1 bye"])
}

private extension ChatHistory {
    /// Back at the last failed try, before the edit turn.
    var movedBack: Bool {
        users.count == 1 && notes.count == 5 && tools.isEmpty
    }

    /// The turn after the move, on that branch.
    var branched: Bool {
        users == ["Run the bash command 'echo hi > a.txt', then edit a.txt replacing hi with bye, then reply with "
            + "just: done", "Reply with just: branched"]
            && entries.last?.kind == ChatEntry.Kind.reply("branched") && !entries.contains { $0.kind == .reply("done") }
    }
}

@Test func `the history is the branch from the leaf, also after a tree move`() throws {
    // Before the move: five failed tries, then the turn with the edit.
    var read = try transcript("pi-tree", upTo: "19d90989")
    #expect(read.history.users.count == 2 && read.history.notes.count == 5)
    #expect(read.history.entries.last?.kind == ChatEntry.Kind.reply("done"))

    // /tree back to the last failed try, read up to its size: the edit turn goes.
    read.transcript.tree("6636acff", at: read.end, into: &read.history)
    #expect(read.history.movedBack)

    // The next turn grows from there.
    #expect(try transcript("pi-tree").history.branched)
}

@Test func `a tree move waits for the transcript, and one it has passed is dropped`() throws {
    let end = try transcript("pi-tree", upTo: "19d90989").end
    // A new chat reads the state file first: the move waits until the transcript is read up to its size.
    var early = PiTranscript(), history = ChatHistory()
    early.tree("6636acff", at: end, into: &history)
    #expect(try transcript("pi-tree", upTo: "19d90989", into: early).history.movedBack)
    #expect(try transcript("pi-tree", into: early).history.branched)

    // A card shown again reads the transcript first: the entries after the move grew from it already.
    var late = try transcript("pi-tree")
    late.transcript.tree("6636acff", at: end, into: &late.history)
    #expect(late.history.branched)
}

@Test func `a read from the middle of the file starts at its first whole entry`() {
    var transcript = PiTranscript(), history = ChatHistory()
    let torn = transcript.read("art of a line\"}}", end: 300_000, into: &history)
    #expect(!torn)
    let user = #"{"type":"message","id":"b","parentId":"a","timestamp":"2026-10-28T12:00:00.000Z","#
        + #""message":{"role":"user","content":"hello"}}"#
    let read = transcript.read(user, end: 300_100, into: &history)
    #expect(read && history.users == ["hello"])
}
