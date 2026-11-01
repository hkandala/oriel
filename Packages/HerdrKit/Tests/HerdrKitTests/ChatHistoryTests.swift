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

/// A row's kind.
private extension ChatRow {
    var kind: String {
        String(describing: self).prefix { $0 != "(" }.description
    }
}

@Test func `every message shows in order, each run between them as one line of counts, then the time`() throws {
    let history = try history()
    let rows = history.rows(working: false)
    #expect(rows.count { $0.kind == "user" } == 6 && Set(rows.map(\.id)).count == rows.count)
    // Every reply, not only a turn's last one.
    #expect(rows.count { $0.kind == "reply" } == history.entries.count { $0.row?.kind == "reply" })
    // The edit turn: its runs and the replies between them, then how long it worked.
    let turn = try #require(rows
        .firstIndex {
            if case let .user(_, text) = $0 {
                text.hasPrefix("Think")
            } else {
                false
            }
        })
    let next = rows[(turn + 1)...].firstIndex { $0.kind == "user" } ?? rows.endIndex
    #expect(rows[(turn + 1) ..< next].map(\.kind).last == "worked")
    guard case let .worked(_, seconds?) = rows[next - 1] else { Issue.record("no time"); return }
    #expect(seconds > 30)
    // A turn with no tool calls has no line and no time.
    #expect(rows.prefix(3).map(\.kind) == ["user", "reply", "user"])

    let runs = rows.compactMap { row -> ArraySlice<ChatEntry>? in
        guard case let .stack(_, steps) = row else { return nil }
        return history.entries[steps]
    }
    #expect(runs.map { ChatTool.summary($0.compactMap(\.tool)) } == [
        "Asked 1 question", "Wrote 1 file, ran 1 command, edited 1 file, +1 more", "Ran 1 command",
        "Ran 3 commands, ran toolsearch 1 time, ran search_files 1 time, 2 failed",
    ])
    // A run's range holds its steps only: its calls and the thinking between them, which has no row of its own.
    #expect(runs.allSatisfy { $0.allSatisfy { $0.tool != nil || $0.kind == .thinking } })
    #expect(runs.contains { $0.contains { $0.kind == .thinking } && $0.contains { $0.tool != nil } })
    #expect(!rows.contains { $0.kind == "thinking" })
}

@Test func `a run is worded as pi-content-layout words it`() {
    func tool(_ name: String, failed: Bool = false, calls: [String] = []) -> ChatTool {
        var tool = ChatTool(id: name, name: name, category: .other, target: "", started: nil)
        tool.failed = failed
        tool.calls = calls
        return tool
    }
    // The largest counts first, ties in the order they first ran.
    #expect(ChatTool.summary([tool("read"), tool("bash", failed: true), tool("read"), tool("ls"), tool("ls")])
        == "Read 2 files, listed 2 directories, ran 1 command, 1 failed")
    // One line: three counts, the rest as "+N more", and the failures.
    let many = ["agent_send", "bash", "bash", "read", "agent_stop", "agent_list", "edit"].map { tool($0) }
        + [tool("bash", failed: true)]
    #expect(ChatTool.summary(many) == "Ran 3 commands, talked to 1 agent, read 1 file, +3 more, 1 failed")
    // codemode is a command, and its script's calls count as their own.
    #expect(ChatTool.summary([tool("codemode", calls: ["read", "web_fetch", "bash"]), tool("agent_list")])
        == "Ran 2 commands, read 1 file, fetched 1 web page, +1 more")
    #expect(ChatTool.summary([tool("explore"), tool("explore")]) == "Ran explore 2 times")
}

@Test func `the last turn says working while it runs`() {
    var history = ChatHistory()
    ClaudeTranscript.read(#"{"type":"user","uuid":"u","message":{"content":"go"}}"#, into: &history)
    let tool = #"{"type":"tool_use","id":"t","name":"Bash","input":{"command":"npm test\nmore"}}"#
    ClaudeTranscript.read(#"{"type":"assistant","uuid":"a","message":{"content":[\#(tool)]}}"#, into: &history)
    // No "Worked" while it runs: the chat's loader counts from the turn's start.
    #expect(history.rows(working: true).map(\.id) == ["u", "a.0"])
    #expect(history.rows(working: false).map(\.id) == ["u", "a.0", "u.worked"])
    guard case let .stack(_, steps) = history.rows(working: true).last else {
        Issue.record("no run"); return
    }
    #expect(history.entries[steps].first?.tool?.target == "npm test" && history.entries[steps].first?.tool?
        .result == nil)
    #expect(ChatTool.summary(history.entries[steps].compactMap(\.tool)) == "Ran 1 command")
    // A turn's end ends its run: a turn with no user entry after it (a task notice) starts its own.
    history.append(ChatEntry(id: "e", .turnEnd(seconds: 1), time: nil))
    history.append(ChatEntry(id: "t2", .tool(ChatTool(id: "t2", name: "bash", category: .command, target: "ls",
                                                      started: nil)), time: nil))
    #expect(history.rows(working: false).map(\.id) == ["u", "a.0", "t2", "u.worked"])
    // A torn line is no entry.
    #expect(!ClaudeTranscript.read(#"{"type":"assist"#, into: &history))
    #expect(ChatHistory.duration(108) == "1m 48s")
    ClaudeTranscript.read(
        #"{"type":"user","uuid":"v","timestamp":"2026-10-29T10:00:00.000Z","message":{"content":"on"}}"#,
        into: &history,
    )
    #expect(history.lastTurnStart == ChatHistory.date("2026-10-29T10:00:00.000Z"))
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
