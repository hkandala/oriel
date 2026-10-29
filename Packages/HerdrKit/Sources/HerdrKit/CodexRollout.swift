import CryptoKit
import Foundation

/// Codex's rollout (`~/.codex/sessions/…/rollout-….jsonl`), one JSON object per line
/// (resources/research/agents/codex.md#3-file-watching-and-the-parser). The parser reads the typed items of
/// `item_completed` events, which are whole when written, and the turn's end; anything else is skipped.
public enum CodexRollout {
    /// Adds what the line holds; false when it is not JSON (a torn line).
    @discardableResult
    public static func read(_ line: String, into history: inout ChatHistory) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return false
        }
        let payload = object["payload"] as? [String: Any] ?? [:]
        let time = (object["timestamp"] as? String).flatMap(ChatHistory.date)
        let turn = payload["turn_id"] as? String ?? UUID().uuidString
        switch (object["type"] as? String, payload["type"] as? String) {
        case ("turn_context", _):
            history.model = payload["model"] as? String ?? history.model
            history.effort = payload["effort"] as? String ?? history.effort
        case ("event_msg", "item_completed"):
            if let item = payload["item"] as? [String: Any] {
                self.item(item, time: time, into: &history)
            }
        case ("event_msg", "task_complete"):
            let milliseconds = payload["duration_ms"] as? Double ?? 0
            history.append(ChatEntry(id: turn + ".end", .turnEnd(seconds: milliseconds / 1000), time: time))
        case ("event_msg", "turn_aborted"):
            history.append(ChatEntry(id: turn + ".end", .note("Interrupted", failed: false), time: time))
        case ("event_msg", "error"):
            history.append(ChatEntry(
                id: UUID().uuidString,
                .note(payload["message"] as? String ?? "Error", failed: true),
                time: time,
            ))
        default: break
        }
        return true
    }

    private static func item(_ item: [String: Any], time: Date?, into history: inout ChatHistory) {
        let id = item["id"] as? String ?? UUID().uuidString
        let text = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        switch item["type"] as? String {
        case "UserMessage" where !text.isEmpty: history.append(ChatEntry(id: id, .user(text), time: time))
        // A plan (plan mode's proposal) reads as a reply.
        case "AgentMessage" where !text.isEmpty, "Plan" where item["text"] is String:
            history.append(ChatEntry(id: id, .reply(item["text"] as? String ?? text), time: time))
        case "Reasoning": history.append(ChatEntry(id: id, .thinking, time: time))
        case "ContextCompaction": history.append(ChatEntry(id: id, .note("Compacted", failed: false), time: time))
        case "CommandExecution": command(item, id: id, time: time, into: &history)
        case "FileChange":
            for (path, change) in (item["changes"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                // The item's status, declined or failed, is each file's.
                let change = (change as? [String: Any] ?? [:]).merging(["status": item["status"] ?? ""]) { $1 }
                edit(path, change, id: "\(id).\(path)", time: time, into: &history)
            }
        case "McpToolCall": mcp(item, id: id, time: time, into: &history)
        default: break
        }
    }

    /// An MCP tool's own name, and its first text argument by name.
    private static func mcp(_ item: [String: Any], id: String, time: Date?, into history: inout ChatHistory) {
        let arguments = (item["arguments"] as? [String: Any] ?? [:]).sorted { $0.key < $1.key }
        var tool = ChatTool(id: id, name: item["tool"] as? String ?? "tool", category: .other,
                            target: ChatHistory.firstLine(arguments.first { $0.value is String }?.value),
                            input: ChatHistory.detail(item["arguments"]), started: time)
        tool.failed = item["status"] as? String == "failed"
        tool.result = tool.failed ? "failed" : ""
        tool.output = ChatHistory.detail(item["result"] ?? item["error"])
        tool.ended = time
        history.append(ChatEntry(id: id, .tool(tool), time: time))
    }

    /// The script of `[shell, -lc, script]`; a read as the file it read.
    private static func command(_ item: [String: Any], id: String, time: Date?, into history: inout ChatHistory) {
        let parsed = item["parsed_cmd"] as? [[String: Any]] ?? [], argv = item["command"] as? [String] ?? []
        let script = argv.count == 3 && argv[1] == "-lc" ? argv[2] : argv.joined(separator: " ")
        let path = parsed.count == 1 && parsed[0]["type"] as? String == "read" ? parsed[0]["path"] as? String : nil
        let duration = item["duration"] as? [String: Any]
        let seconds = (duration?["secs"] as? Double ?? 0) + (duration?["nanos"] as? Double ?? 0) / 1e9
        var tool = ChatTool(id: id, name: path == nil ? "bash" : "read", category: path == nil ? .command : .read,
                            target: path ?? ChatHistory.firstLine(script), input: ChatHistory.detail(script),
                            started: time?.addingTimeInterval(-seconds))
        let exit = item["exit_code"] as? Int, status = item["status"] as? String
        tool.failed = exit.map { $0 != 0 } ?? false || ["failed", "declined"].contains(status)
        tool.result = !tool.failed ? ChatHistory.firstLine(item["aggregated_output"])
            : exit.map { "exit \($0)" } ?? status ?? "failed"
        tool.output = ChatHistory.detail(item["aggregated_output"])
        tool.ended = time
        history.append(ChatEntry(id: id, .tool(tool), time: time))
    }

    /// One file's change: an added file's lines, or an update's unified diff.
    private static func edit(_ path: String, _ change: [String: Any], id: String, time: Date?,
                             into history: inout ChatHistory)
    {
        let content = change["type"] as? String == "add" ? change["content"] as? String : nil
        let diff = content.map(ChatTool.DiffLine.added)
            ?? ChatTool.DiffLine.unified(change["unified_diff"] as? String ?? "")
        var tool = ChatTool(id: id, name: "edit", category: .edit, target: path, started: time)
        let status = change["status"] as? String ?? ""
        tool.failed = ["failed", "declined"].contains(status)
        tool.result = tool.failed ? status : change["type"] as? String == "delete" ? "deleted"
            : ChatTool.change(diff)
        tool.diff = diff
        tool.ended = time
        history.append(ChatEntry(id: id, .tool(tool), time: time))
    }

    /// Codex's input box (`› …`) directly above its status row (`<model> <effort> · <folder>`), among the screen's
    /// last rows: no picker, dialog or question is open. A picker's selected row is `› 1. …`.
    public static func ready(_ screen: String) -> Bool {
        let rows = screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .suffix(4)
        return zip(rows, rows.dropFirst()).contains { box, status in
            box.hasPrefix("› ") && box.dropFirst(2).firstMatch(of: /^\d+\./) == nil && status.contains(" · ")
        }
    }

    /// The trust hash Codex keeps for a SessionStart command hook in `hooks.state` (`codex-rs/hooks`): sha256 of the
    /// hook's sorted compact JSON, with Codex's defaults filled in. The command holds no quote and no backslash.
    public static func trust(_ command: String) -> String {
        let identity = #"{"event_name":"session_start","hooks":[{"async":false,"command":"\#(command)","#
            + #""timeout":600,"type":"command"}]}"#
        return "sha256:" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
