import Foundation

/// The detail level (ui/chat-view#detail-levels).
public enum ChatLevel: String, CaseIterable, Sendable {
    case replies, steps, all
}

public enum ChatRow: Equatable, Sendable, Identifiable {
    case user(id: String, text: String)
    /// The quiet line under a user message: "Worked 1m 48s · 2 files edited · 3 commands". `since` while it works.
    /// `tools`: the run of tool calls right under it, which it opens to (Steps and All).
    case summary(id: String, text: String, since: Date?, tools: [ChatTool] = [])
    case reply(id: String, text: String)
    case thinking(id: String)
    /// A run of tool calls between two replies.
    case stack(id: String, tools: [ChatTool])
    case todos(id: String, [ChatTodo])
    case note(id: String, text: String, failed: Bool)

    public var id: String {
        switch self {
        case let .user(id, _), let .summary(id, _, _, _), let .reply(id, _), let .thinking(id), let .stack(id, _),
             let .todos(id, _), let .note(id, _, _): id
        }
    }
}

public extension ChatHistory {
    /// The rows at a level. Replies: the user's messages, each turn's quiet line and its last reply. Steps: every
    /// reply and todo list, and each run of tool calls as one stack; All adds the thinking rows. `working`: the last
    /// turn runs on.
    func rows(_ level: ChatLevel, working: Bool) -> [ChatRow] {
        var turns: [[ChatEntry]] = []
        for entry in entries {
            if turns.isEmpty || entry.user != nil {
                turns.append([entry])
            } else {
                turns[turns.count - 1].append(entry)
            }
        }
        return turns.indices.flatMap { Self.rows(turns[$0], level, running: working && $0 == turns.count - 1) }
    }

    private static func rows(_ turn: [ChatEntry], _ level: ChatLevel, running: Bool) -> [ChatRow] {
        var rows: [ChatRow] = [], body = turn[...]
        if let text = turn[0].user {
            rows.append(.user(id: turn[0].id, text: text))
            body = body.dropFirst()
        }
        let tools = body.compactMap(\.tool)
        if running || !tools.isEmpty {
            rows.append(.summary(id: "\(turn[0].id).summary", text: summary(body, tools, running),
                                 since: running ? turn[0].time : nil))
        }
        guard level != .replies else {
            let reply = body.last { $0.row?.isReply == true }?.id
            return rows + body.compactMap { entry in
                guard let row = entry.row, entry.id == reply || row.isNote else { return nil }
                return row
            }
        }
        var stack: [ChatTool] = [], stackID = ""
        for entry in body {
            if let tool = entry.tool {
                stackID = stack.isEmpty ? entry.id : stackID
                stack.append(tool)
                continue
            }
            // Thinking only at All: at Steps it is noise between the steps.
            guard let row = entry.row, level == .all || entry.kind != .thinking else { continue }
            if !stack.isEmpty {
                rows.append(.stack(id: stackID, tools: stack))
                stack = []
            }
            rows.append(row)
        }
        if !stack.isEmpty {
            rows.append(.stack(id: stackID, tools: stack))
        }
        // The quiet line takes the run right under it, so the two do not say the same twice.
        if let index = rows.firstIndex(where: \.isSummary), index + 1 < rows.count,
           case let .summary(id, text, since, _) = rows[index], case let .stack(_, tools) = rows[index + 1]
        {
            rows[index] = .summary(id: id, text: text, since: since, tools: tools)
            rows.remove(at: index + 1)
        }
        return rows
    }

    /// "Worked 14s · 2 files edited · 3 commands · 1 failed"; "Working" while it runs (the view adds the time).
    private static func summary(_ body: ArraySlice<ChatEntry>, _ tools: [ChatTool], _ running: Bool) -> String {
        var parts = [running ? "Working" : "Worked"]
        let first = body.first?.time, last = body.last?.time
        let seconds = body.lazy.compactMap(\.seconds).last ?? first.flatMap { first in last?.timeIntervalSince(first) }
        if !running, let seconds {
            parts[0] += " " + duration(seconds)
        }
        let edited = Set(tools.filter { $0.category == .edit }.map(\.target)).count
        let commands = tools.count { $0.category == .command }, failed = tools.count(where: \.failed)
        let read = Set(tools.filter { $0.category == .read }.map(\.target)).count
        parts += [edited > 0 ? count(edited, "file") + " edited" : "", commands > 0 ? count(commands, "command") : ""]
        if edited == 0, commands == 0, !tools.isEmpty {
            parts.append(read > 0 ? "read " + count(read, "file") : count(tools.count, "step"))
        }
        parts.append(failed > 0 ? "\(failed) failed" : "")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public extension ChatRow {
    var isSummary: Bool {
        if case .summary = self {
            true
        } else {
            false
        }
    }

    var isReply: Bool {
        if case .reply = self {
            true
        } else {
            false
        }
    }

    var isNote: Bool {
        if case .note = self {
            true
        } else {
            false
        }
    }
}
