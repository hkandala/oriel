import Foundation

/// Claude Code's transcript (`~/.claude/projects/…/<session>.jsonl`), one JSON object per line
/// (resources/research/agents/claude-code.md#3-file-watching-and-the-parser). The core reads the API's own shapes:
/// `user` and `assistant` lines with `text`, `tool_use`, `tool_result` and `thinking` blocks. Queued prompts, turn
/// ends, errors and compaction are extras of 2.1.x that may change; anything else is skipped.
public enum ClaudeTranscript {
    /// Adds what the line holds; false when it is not JSON (a torn line).
    @discardableResult
    public static func read(_ line: String, into history: inout ChatHistory) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return false
        }
        let line = Line(object: object, id: object["uuid"] as? String ?? UUID().uuidString,
                        time: (object["timestamp"] as? String).flatMap(ChatHistory.date))
        guard object["isSidechain"] as? Bool != true, object["isMeta"] as? Bool != true else { return true }
        switch object["type"] as? String {
        case "user" where object["isCompactSummary"] as? Bool != true: user(line, into: &history)
        case "assistant": assistant(line, into: &history)
        case "attachment":
            let attachment = object["attachment"] as? [String: Any]
            if attachment?["type"] as? String == "queued_command", let text = attachment?["prompt"] as? String {
                history.append(ChatEntry(id: line.id, .user(text), time: line.time))
            }
        case "system" where object["subtype"] as? String == "turn_duration":
            let milliseconds = object["durationMs"] as? Double ?? 0
            history.append(ChatEntry(id: line.id, .turnEnd(seconds: milliseconds / 1000), time: line.time))
        case "system" where object["subtype"] as? String == "compact_boundary":
            history.append(ChatEntry(id: line.id, .note("Compacted", failed: false), time: line.time))
        default: break
        }
        return true
    }

    private struct Line {
        let object: [String: Any]
        let id: String
        let time: Date?

        var blocks: [[String: Any]] {
            (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        }
    }

    private static func user(_ line: Line, into history: inout ChatHistory) {
        if let text = (line.object["message"] as? [String: Any])?["content"] as? String {
            user(text, id: line.id, time: line.time, into: &history)
        }
        for (index, block) in line.blocks.enumerated() {
            if block["type"] as? String == "text", let text = block["text"] as? String {
                user(text, id: "\(line.id).\(index)", time: line.time, into: &history)
            } else if block["type"] as? String == "tool_result", let toolID = block["tool_use_id"] as? String {
                result(block, line.object["toolUseResult"], id: toolID, time: line.time, into: &history)
            }
        }
    }

    private static func assistant(_ line: Line, into history: inout ChatHistory) {
        if let model = (line.object["message"] as? [String: Any])?["model"] as? String, !model.hasPrefix("<") {
            history.model = model
            // A model without effort levels (Haiku) has none.
            history.effort = line.object["effort"] as? String
        }
        let failed = line.object["isApiErrorMessage"] as? Bool == true
        for (index, block) in line.blocks.enumerated() {
            let id = "\(line.id).\(index)"
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String, !text.isEmpty else { continue }
                history.append(ChatEntry(id: id, failed ? .note(text, failed: true) : .reply(text), time: line.time))
            case "thinking", "redacted_thinking": history.append(ChatEntry(id: id, .thinking, time: line.time))
            case "tool_use":
                toolUse(block, id: id, cwd: line.object["cwd"] as? String, time: line.time, into: &history)
            default: break
            }
        }
    }

    /// A user's text; Claude's own tags as what they mean: a slash command as its name, an interrupt as a note, and
    /// its command output and task notices not at all.
    private static func user(_ text: String, id: String, time: Date?, into history: inout ChatHistory) {
        if text.hasPrefix("[Request interrupted by user") {
            history.append(ChatEntry(id: id, .note("Interrupted", failed: false), time: time))
        } else if let range = text.range(of: "<command-name>"), let end = text.range(of: "</command-name>") {
            history.append(ChatEntry(id: id, .user(String(text[range.upperBound ..< end.lowerBound])), time: time))
        } else if !["<task-notification>", "<local-command-", "<command-", "<bash-", "<system-reminder>"]
            .contains(where: text.hasPrefix)
        {
            history.append(ChatEntry(id: id, .user(text), time: time))
        }
    }

    private static func toolUse(_ block: [String: Any], id: String, cwd: String?, time: Date?,
                                into history: inout ChatHistory)
    {
        let name = block["name"] as? String ?? "tool", input = block["input"] as? [String: Any] ?? [:]
        let toolID = block["id"] as? String ?? id
        let path = (input["file_path"] as? String ?? input["notebook_path"] as? String)
            .map { ChatHistory.short($0, cwd) }
        let category: ChatTool.Category, target: String
        var shown = name.lowercased()
        switch name {
        case "TodoWrite":
            history.append(ChatEntry(id: id, .todos(ChatTodo.list(input["todos"])), time: time))
            return
        case "Read", "NotebookRead": (category, target) = (.read, path ?? "")
        case "Edit", "MultiEdit", "Write", "NotebookEdit": (category, target) = (.edit, path ?? "")
        case "Bash": (category, target) = (.command, ChatHistory.firstLine(input["command"]))
        case "Grep", "Glob": (category, target) = (.search, ChatHistory.firstLine(input["pattern"]))
        case "WebSearch": (category, target) = (.search, ChatHistory.firstLine(input["query"]))
        case "Task", "Agent":
            shown = input["subagent_type"] as? String ?? "agent"
            (category, target) = (.other, ChatHistory.firstLine(input["description"]))
        case "AskUserQuestion":
            let question = (input["questions"] as? [[String: Any]])?.first?["question"]
            (category, target) = (.other, ChatHistory.firstLine(question))
        default:
            // An MCP tool's own name (`mcp__server__tool`), and its first text argument.
            shown = String(name.split(separator: "_").last ?? Substring(name)).lowercased()
            (category, target) = (.other, ChatHistory.firstLine(input.values.first { $0 is String }))
        }
        history.append(ChatEntry(id: id, .tool(ChatTool(id: toolID, name: shown, category: category, target: target,
                                                        input: ChatHistory.detail(input), started: time)), time: time))
    }

    /// A result as its row says it: lines read, lines changed with the diff, or a failure's first line.
    private static func result(_ block: [String: Any], _ extra: Any?, id: String, time: Date?,
                               into history: inout ChatHistory)
    {
        let failed = block["is_error"] as? Bool == true
        let content = block["content"] as? String
            ?? (block["content"] as? [
                [String: Any]
            ])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
        let extra = extra as? [String: Any] ?? [:]
        var diff: [ChatTool.DiffLine] = []
        for hunk in extra["structuredPatch"] as? [[String: Any]] ?? [] {
            var old = hunk["oldStart"] as? Int ?? 1, new = hunk["newStart"] as? Int ?? 1
            for line in hunk["lines"] as? [String] ?? [] {
                guard let mark = line.first else { continue }
                diff.append(ChatTool.DiffLine(
                    mark: mark,
                    number: mark == "-" ? old : new,
                    text: String(line.dropFirst()),
                ))
                old += mark == "+" ? 0 : 1
                new += mark == "-" ? 0 : 1
            }
        }
        if diff.isEmpty, extra["type"] as? String == "create", let text = extra["content"] as? String {
            diff = ChatTool.DiffLine.added(text)
        }
        let text: String
        if failed {
            let first = ChatHistory.firstLine(content)
            text = first.hasPrefix("Exit code ") ? "exit " + first.dropFirst(10) : first
        } else if !diff.isEmpty {
            text = ChatTool.change(diff)
        } else if let lines = (extra["file"] as? [String: Any])?["numLines"] as? Int {
            text = ChatHistory.count(lines, "line")
        } else {
            text = ChatHistory.firstLine(content)
        }
        history.finish(
            tool: id,
            result: text,
            failed: failed,
            diff: diff,
            output: ChatHistory.detail(content),
            at: time,
        )
    }
}
