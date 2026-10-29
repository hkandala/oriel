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
    // Opened, a call shows its whole input and output.
    #expect(failed.input == "command: ls /nonexistent\ndescription: List a directory that does not exist")
    #expect(failed.output.hasPrefix("Exit code 1\n"), "\(failed.output)")
    #expect(tools.contains { $0.name == "search_files" && $0.category == .other })
    #expect(history.entries.contains { $0.kind == .turnEnd(seconds: 8.355) })
}

/// A row's kind, and the steps of a quiet line or a stack.
private extension ChatRow {
    var kind: String {
        String(describing: self).prefix { $0 != "(" }.description
    }

    var steps: [ChatEntry]? {
        switch self {
        case let .summary(_, _, _, _, steps), let .stack(_, steps): steps
        default: nil
        }
    }
}

@Test func `replies show each turn's quiet line and last reply; activity opens the line to every step`() throws {
    let history = try history()
    let replies = history.rows(.replies, working: false)
    #expect(replies.count { $0.kind == "user" } == 6 && !replies.contains { $0.kind == "stack" })
    // The edit turn: its user message, its quiet line, its last reply.
    let turn = try #require(replies
        .firstIndex {
            if case let .user(_, text) = $0 {
                text.hasPrefix("Think")
            } else {
                false
            }
        })
    guard case let .summary(_, counts, nil, seconds?, []) = replies[turn + 1], case .reply = replies[turn + 2] else {
        Issue.record("no summary and reply after \(replies[turn])"); return
    }
    #expect(counts == "Wrote 1 file, ran 1 command, edited 1 file, read 1 file" && seconds > 30)

    // The same rows, each line holding every step of its turn: the MCP turn's calls and thinking.
    let activity = history.rows(.activity, working: false)
    #expect(activity.map(\.id) == replies.map(\.id))
    let mcp = try #require(activity.compactMap(\.steps).first { $0.count == 9 })
    #expect(ChatTool.summary(mcp.compactMap(\.tool))
        == "Ran 3 commands, ran toolsearch 1 time, ran search_files 1 time, 2 failed")
}

@Test func `everything has no quiet line, and the thinking between calls is in their run`() throws {
    let everything = try history().rows(.everything, working: false)
    #expect(!everything.contains { $0.kind == "summary" })
    #expect(everything.compactMap(\.steps).map { ChatTool.summary($0.compactMap(\.tool)) } == [
        "Asked 1 question", "Wrote 1 file, ran 1 command, edited 1 file, read 1 file", "Ran 1 command",
        "Ran 3 commands, ran toolsearch 1 time, ran search_files 1 time, 2 failed",
    ])
    #expect(everything.compactMap(\.steps)
        .contains { $0.contains { $0.kind == .thinking } && $0.contains { $0.tool != nil } })
    // Thinking alone is a row of its own.
    #expect(everything.count { $0.kind == "thinking" } == 2)
    #expect(Set(everything.map(\.id)).count == everything.count)
}

@Test func `a run is worded as pi-content-layout words it`() {
    func tool(_ name: String, failed: Bool = false, calls: [String] = []) -> ChatTool {
        var tool = ChatTool(id: name, name: name, category: .other, target: "", started: nil)
        tool.failed = failed
        tool.calls = calls
        return tool
    }
    #expect(ChatTool.summary([tool("read"), tool("bash", failed: true), tool("read"), tool("ls"), tool("ls")])
        == "Read 2 files, ran 1 command, listed 2 directories, 1 failed")
    // codemode is a command, and its script's calls count as their own.
    #expect(ChatTool.summary([tool("codemode", calls: ["read", "web_fetch", "bash"]), tool("agent_list")])
        == "Ran 2 commands, read 1 file, fetched 1 web page, checked agents")
    #expect(ChatTool.summary([tool("explore"), tool("explore")]) == "Ran explore 2 times")
}

@Test func `the last turn says working while it runs`() {
    var history = ChatHistory()
    ClaudeTranscript.read(#"{"type":"user","uuid":"u","message":{"content":"go"}}"#, into: &history)
    let tool = #"{"type":"tool_use","id":"t","name":"Bash","input":{"command":"npm test\nmore"}}"#
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"a","message":{"content":[\#(tool)]}}"#, into: &history)
    #expect(history.rows(.replies, working: true).map(\.id) == ["u", "u.summary"])
    guard case let .summary(_, counts, _, nil, steps) = history.rows(.activity, working: true).last else {
        Issue.record("no steps in the quiet line"); return
    }
    #expect(steps.first?.tool?.target == "npm test" && steps.first?.tool?.result == nil)
    #expect(counts == "Ran 1 command")
    // A torn line is no entry.
    #expect(!ClaudeTranscript.read(#"{"type":"assist"#, into: &history))
    #expect(ChatHistory.duration(108) == "1m 48s")
}

@Test func `models read as the agent's picker names them`() {
    #expect(ChatHistory.modelName("claude-opus-5-5") == "Opus 5.5")
    #expect(ChatHistory.modelName("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
    #expect(ChatHistory.modelName("claude-3-5-haiku-20241022") == "Haiku 3.5")
    #expect(ChatHistory.modelName("anthropic/claude-opus-4") == "Opus 4")
    #expect(ChatHistory.modelName("gpt-5-codex") == "gpt-5-codex")
}

@Test func `claude's effort comes with each reply's model, none for a model without levels`() {
    var history = ChatHistory()
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"a","effort":"medium","message":{"model":"claude-opus-5-5"}}"#,
                          into: &history)
    #expect(history.model == "claude-opus-5-5" && history.effort == "medium")
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"b","message":{"model":"claude-haiku-5-5"}}"#, into: &history)
    #expect(history.model == "claude-haiku-5-5" && history.effort == nil)
}
