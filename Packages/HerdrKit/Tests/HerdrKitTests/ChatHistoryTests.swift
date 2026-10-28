import Foundation
@testable import HerdrKit
import Testing

/// A real Claude Code 2.1.312 session, cut to the lines the parser reads (`Fixtures/claude-transcript.jsonl`): six
/// turns with a question, a write, an edit, a queued prompt, a failed command, an MCP tool and background tasks.
private func history() throws -> ChatHistory {
    let url = try #require(Bundle.module.url(forResource: "claude-transcript", withExtension: "jsonl",
                                             subdirectory: "Fixtures"))
    var history = ChatHistory()
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        ClaudeTranscript.read(String(line), into: &history)
    }
    return history
}

@Test func `claude transcript gives user text, replies and tools with their results`() throws {
    let history = try history()
    let users = history.entries.compactMap {
        if case let .user(text) = $0.kind {
            text
        } else {
            nil
        }
    }
    // Task notices are not the user's; the queued prompt is.
    #expect(users.count == 6)
    #expect(users[0] == "Reply with just the word hello.")
    #expect(users.contains("Queued: say queued-ok."))
    #expect(history.model == "claude-opus-5-5")
    let tools = history.entries.compactMap {
        if case let .tool(tool) = $0.kind {
            tool
        } else {
            nil
        }
    }
    #expect(tools.allSatisfy { $0.result != nil })
    let edit = try #require(tools.first { $0.name == "edit" })
    #expect(edit.target == "notes.txt" && edit.result == "+1 -1")
    #expect(edit.diff.map { "\($0.mark)\($0.number) \($0.text)" } == [" 1 alpha", "-2 beta", "+2 gamma"])
    #expect(tools.first { $0.name == "write" }?.diff.count == 2)
    #expect(tools.first { $0.name == "read" }?.result == "3 lines")
    let failed = try #require(tools.first { $0.failed })
    #expect(failed.target == "ls /nonexistent" && failed.result == "exit 1")
    #expect(tools.contains { $0.name == "files" && $0.category == .other })
    #expect(history.entries.contains { $0.kind == .turnEnd(seconds: 8.355) })
}

@Test func `replies show each turn's last reply; steps add every step, with tool runs stacked`() throws {
    let history = try history()
    let replies = history.rows(.replies, working: false)
    #expect(replies.count {
        if case .user = $0 {
            true
        } else {
            false
        }
    } == 6)
    #expect(!replies.contains {
        if case .stack = $0 {
            true
        } else {
            false
        }
    })
    // The edit turn: its user message, its quiet line, its last reply.
    let turn = try #require(replies
        .firstIndex {
            if case let .user(_, text) = $0 {
                text.hasPrefix("Think")
            } else {
                false
            }
        })
    guard case let .summary(_, text, nil) = replies[turn + 1], case .reply = replies[turn + 2] else {
        Issue.record("no summary and reply after \(replies[turn])"); return
    }
    #expect(text.hasPrefix("Worked ") && text.hasSuffix(" · 1 file edited · 1 command"))

    let steps = history.rows(.steps, working: false)
    let stacks = steps.compactMap {
        if case let .stack(_, tools) = $0 {
            tools
        } else {
            nil
        }
    }
    #expect(stacks.contains { ChatTool.summary($0) == "Edited 1 file, read 1 file, ran 1 command" })
    #expect(steps.count > replies.count)
    #expect(Set(steps.map(\.id)).count == steps.count)
}

@Test func `the last turn says working while it runs`() {
    var history = ChatHistory()
    ClaudeTranscript.read(#"{"type":"user","uuid":"u","message":{"content":"go"}}"#, into: &history)
    let tool = #"{"type":"tool_use","id":"t","name":"Bash","input":{"command":"npm test\nmore"}}"#
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"a","message":{"content":[\#(tool)]}}"#, into: &history)
    #expect(history.rows(.replies, working: true).map(\.id) == ["u", "u.summary"])
    guard case let .stack(_, tools) = history.rows(.steps, working: true).last else { Issue.record("no stack"); return }
    #expect(tools.first?.target == "npm test" && tools.first?.result == nil)
    #expect(ChatTool.summary(tools) == "Running 1 command")
    // A torn line is no entry.
    #expect(!ClaudeTranscript.read(#"{"type":"assist"#, into: &history))
    #expect(ChatHistory.duration(108) == "1m 48s")
}
