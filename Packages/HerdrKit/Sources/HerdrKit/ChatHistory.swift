import Foundation

/// An agent's history as the chat view draws it (ui/chat-view): what each adapter's parser makes of the
/// agent's own transcript. The core is user text, replies, tool calls with their results and turn ends; the rest are
/// extras an adapter may leave out.
public struct ChatHistory: Equatable, Sendable {
    public private(set) var entries: [ChatEntry] = []
    /// The model of the last reply and its thinking effort, in the agent's words ("high"), shown read only.
    public var model: String?
    public var effort: String?
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
                                output: String = "", at time: Date?)
    {
        guard let index = tools.removeValue(forKey: id), case var .tool(tool) = entries[index].kind else { return }
        tool.result = result
        tool.output = output
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
    /// What it was given and what it gave back, whole (`ChatHistory.detail`), for its open row.
    public let input: String
    public var output = ""
    public let started: Date?
    public var ended: Date?

    public init(id: String, name: String, category: Category, target: String, input: String = "", started: Date?) {
        self.id = id
        self.name = name
        self.category = category
        self.target = target
        self.input = input
        self.started = started
    }
}

public struct ChatTodo: Equatable, Sendable {
    public let text: String
    public let done: Bool
    public let active: Bool
}

public extension ChatHistory {
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

    /// A tool's input or output as its open row shows it: text as it is, an object's text values as `key: value`
    /// lines, anything else as indented JSON; at most 20 000 characters.
    static func detail(_ value: Any?) -> String {
        func json(_ value: Any) -> String {
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .fragmentsAllowed,
                                                             .withoutEscapingSlashes]
            return (try? JSONSerialization.data(withJSONObject: value, options: options))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        let text = switch value {
        case nil, is NSNull: ""
        case let text as String: text
        case let object as [String: Any]:
            object.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value as? String ?? json($0.value))" }
                .joined(separator: "\n")
        case let value?: json(value)
        }
        return text.count > 20000 ? text.prefix(19999) + "…" : text.trimmingCharacters(in: .whitespacesAndNewlines)
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

extension ChatTool.DiffLine {
    /// A unified diff's lines with their numbers (`@@ -a,b +c,d @@` hunks); headers and "\ No newline" skipped.
    static func unified(_ text: String) -> [Self] {
        var lines: [Self] = [], old = 0, new = 0, inHunk = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                let numbers = line.split(separator: " ").dropFirst().prefix(2)
                    .map { Int($0.dropFirst().split(separator: ",").first ?? "") ?? 1 }
                (old, new, inHunk) = (numbers.first ?? 1, numbers.last ?? 1, true)
                continue
            }
            guard inHunk, let mark = line.first, "+- ".contains(mark) else { continue }
            lines.append(Self(mark: mark, number: mark == "-" ? old : new, text: String(line.dropFirst())))
            old += mark == "+" ? 0 : 1
            new += mark == "-" ? 0 : 1
        }
        return lines
    }

    /// A new file's lines, all added.
    static func added(_ text: String) -> [Self] {
        text.split(separator: "\n", omittingEmptySubsequences: false).dropLast(text.hasSuffix("\n") ? 1 : 0)
            .enumerated().map { Self(mark: "+", number: $0 + 1, text: String($1)) }
    }
}

extension ChatTool {
    /// A change as its row says it: "+3 -1", "+2", "-4".
    static func change(_ diff: [DiffLine]) -> String {
        let added = diff.count { $0.mark == "+" }, removed = diff.count { $0.mark == "-" }
        return [added > 0 ? "+\(added)" : nil, removed > 0 ? "-\(removed)" : nil].compactMap(\.self)
            .joined(separator: " ")
    }
}

extension ChatTodo {
    /// A todo list as Claude Code's TodoWrite and opencode's todowrite give it (`content`, `status`).
    static func list(_ todos: Any?) -> [ChatTodo] {
        (todos as? [[String: Any]] ?? []).map { todo in
            let status = todo["status"] as? String
            return ChatTodo(text: todo["content"] as? String ?? "", done: status == "completed",
                            active: status == "in_progress")
        }
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

public extension ChatHistory {
    /// A model as the agent's picker names it: Claude's ids (`claude-opus-5-5`, `claude-3-5-haiku-20241022`) as
    /// "Opus 5.5" and "Haiku 3.5"; any other as it is.
    static func modelName(_ model: String) -> String {
        let parts = model.split(separator: "/").last?.split(separator: "-") ?? []
        guard parts.first == "claude", let family = parts.first(where: { ["opus", "sonnet", "haiku"].contains($0) })
        else { return model }
        let version = parts.filter { $0.count < 3 && $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        return ([family.capitalized] + (version.isEmpty ? [] : [version])).joined(separator: " ")
    }
}
