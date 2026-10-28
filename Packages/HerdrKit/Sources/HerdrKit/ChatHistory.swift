import Foundation

/// An agent's history as the chat view draws it (ui/chat-view): what each adapter's parser makes of the
/// agent's own transcript. The core is user text, replies, tool calls with their results and turn ends; the rest are
/// extras an adapter may leave out.
public struct ChatHistory: Equatable, Sendable {
    public private(set) var entries: [ChatEntry] = []
    /// The model of the last reply, shown read only.
    public var model: String?
    /// Where each open tool call is, to pair it with its result.
    private var tools: [String: Int] = [:]

    public init() {}

    public mutating func append(_ entry: ChatEntry) {
        if case let .tool(tool) = entry.kind {
            tools[tool.id] = entries.count
        }
        entries.append(entry)
    }

    /// A tool call's result; nil when the call is not known (a result in a later read than its call is still paired).
    public mutating func finish(tool id: String, result: String, failed: Bool, diff: [ChatTool.DiffLine] = [],
                                at time: Date?)
    {
        guard let index = tools.removeValue(forKey: id), case var .tool(tool) = entries[index].kind else { return }
        tool.result = result
        tool.failed = failed
        tool.diff = diff.isEmpty ? tool.diff : diff
        tool.ended = time
        entries[index].kind = .tool(tool)
    }
}

public struct ChatEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case user(String)
        case reply(String)
        case thinking
        case tool(ChatTool)
        case todos([ChatTodo])
        /// "Interrupted", an API error, a compaction.
        case note(String, failed: Bool)
        /// The agent finished its turn after this long.
        case turnEnd(seconds: Double)
    }

    public let id: String
    public var kind: Kind
    public let time: Date?

    public init(id: String, _ kind: Kind, time: Date?) {
        self.id = id
        self.kind = kind
        self.time = time
    }
}

extension ChatEntry {
    var user: String? {
        if case let .user(text) = kind {
            text
        } else {
            nil
        }
    }

    var seconds: Double? {
        if case let .turnEnd(seconds) = kind {
            seconds
        } else {
            nil
        }
    }

    var tool: ChatTool? {
        if case let .tool(tool) = kind {
            tool
        } else {
            nil
        }
    }

    /// Its own row: a reply, a thinking row, a todo list or a note.
    var row: ChatRow? {
        switch kind {
        case let .reply(text): .reply(id: id, text: text)
        case .thinking: .thinking(id: id)
        case let .todos(todos): .todos(id: id, todos)
        case let .note(text, failed): .note(id: id, text: text, failed: failed)
        case .user, .tool, .turnEnd: nil
        }
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

public struct ChatTool: Equatable, Sendable {
    public enum Category: Sendable {
        case read, edit, command, search, other
    }

    public struct DiffLine: Equatable, Sendable {
        /// " ", "+" or "-".
        public let mark: Character
        public let number: Int
        public let text: String
    }

    public let id: String
    /// As the row shows it: `bash`, `edit`, a subagent's type.
    public let name: String
    public let category: Category
    /// The command, the file, the pattern.
    public let target: String
    /// "62 lines", "exit 1", "+3 -1"; nil while it runs.
    public var result: String?
    public var failed = false
    public var diff: [DiffLine] = []
    public let started: Date?
    public var ended: Date?

    public init(id: String, name: String, category: Category, target: String, started: Date?) {
        self.id = id
        self.name = name
        self.category = category
        self.target = target
        self.started = started
    }
}

public struct ChatTodo: Equatable, Sendable {
    public let text: String
    public let done: Bool
    public let active: Bool
}

/// The detail level (ui/chat-view#detail-levels).
public enum ChatLevel: String, CaseIterable, Sendable {
    case replies, steps, all
}

/// One row of the chat at a detail level.
public enum ChatRow: Equatable, Sendable, Identifiable {
    case user(id: String, text: String)
    /// The quiet line under a user message: "Worked 1m 48s · 2 files edited · 3 commands". `since` while it works.
    case summary(id: String, text: String, since: Date?)
    case reply(id: String, text: String)
    case thinking(id: String)
    /// A run of tool calls between two replies.
    case stack(id: String, tools: [ChatTool])
    case todos(id: String, [ChatTodo])
    case note(id: String, text: String, failed: Bool)

    public var id: String {
        switch self {
        case let .user(id, _), let .summary(id, _, _), let .reply(id, _), let .thinking(id), let .stack(id, _),
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
        return stack.isEmpty ? rows : rows + [.stack(id: stackID, tools: stack)]
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

    /// "4s", "1m 48s", "2h 5m".
    static func duration(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return whole < 60 ? "\(whole)s" : whole < 3600 ? "\(whole / 60)m \(whole % 60)s"
            : "\(whole / 3600)h \(whole % 3600 / 60)m"
    }

    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    /// A target or a result as its row shows it: the first line, at most 120 characters.
    static func firstLine(_ value: Any?) -> String {
        let text = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.prefix { $0 != "\n" }
        return line.count > 120 ? line.prefix(119) + "…" : String(line)
    }

    /// A path under the session's folder from there, else whole.
    static func short(_ path: String, _ cwd: String?) -> String {
        guard let cwd, path.hasPrefix(cwd + "/") else { return path }
        return String(path.dropFirst(cwd.count + 1))
    }

    static func date(_ text: String) -> Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
    }
}

public extension ChatTool {
    /// A stack's front: "Edited 2 files, ran 1 command, 1 failed"; "Editing 1 file, running 2 commands" while one runs.
    static func summary(_ tools: [ChatTool]) -> String {
        let running = tools.contains { $0.result == nil }
        let files = { (category: Category) in Set(tools.filter { $0.category == category }.map(\.target)).count }
        let calls = { (category: Category) in tools.count { $0.category == category } }
        let searches = calls(.search), failed = tools.count(where: \.failed)
        let parts = [
            (files(.edit), running ? "editing" : "edited", ChatHistory.count(files(.edit), "file")),
            (files(.read), running ? "reading" : "read", ChatHistory.count(files(.read), "file")),
            (searches, running ? "searching" : "searched",
             searches == 1 ? "once" : searches == 2 ? "twice" : "\(searches) times"),
            (calls(.command), running ? "running" : "ran", ChatHistory.count(calls(.command), "command")),
            (calls(.other), running ? "using" : "used", ChatHistory.count(calls(.other), "tool")),
            (failed, "", "\(failed) failed"),
        ]
        let text = parts.filter { $0.0 > 0 }.map { [$0.1, $0.2].filter { !$0.isEmpty }.joined(separator: " ") }
            .joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
