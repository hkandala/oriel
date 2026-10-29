import Foundation

/// pi's session file (`~/.pi/agent/sessions/…/<time>_<id>.jsonl`, pi's docs/session-format.md), one entry per line.
/// Entries form a tree by `id` and `parentId`; the history is the branch from the leaf back to the root
/// (resources/research/agents/pi.md#3-file-watching-and-the-parser). The core reads `message` entries: user text,
/// assistant text, thinking and tool calls, and tool results; errors, interrupts, `!` commands and compaction are
/// extras. Anything else is skipped. It keeps the tree; the history it builds is the caller's (the chat's), changed in
/// place.
public struct PiTranscript: Sendable {
    /// Each entry read, by id: its parent and what it does to the history, so another branch is built again without
    /// reading the file again.
    private var nodes: [String: Node] = [:]
    private var leaf: String?
    /// The session's folder, from the header: tool paths under it show from there.
    private var cwd: String?
    /// Where the file was read up to, and the `/tree` moves it has not been read up to yet.
    /// ponytail: a file pi rewrites in place (it migrates an old one) keeps the old offsets and nodes; the nodes
    /// heal by id, a pending move may be lost.
    private var offset = 0
    private var moves: [(leaf: String?, size: Int)] = []

    public init() {}

    private struct Node {
        let parent: String?
        let steps: [Step]
    }

    private enum Step {
        case add(ChatEntry)
        case finish(id: String, result: String, failed: Bool, diff: [ChatTool.DiffLine], output: String, time: Date?)
        case model(String)
    }

    /// Adds the entry, which ends `end` bytes into the file; it is the leaf now (pi appends to its leaf). False when
    /// the line is not JSON (a torn line).
    @discardableResult
    public mutating func read(_ line: String, end: Int, into history: inout ChatHistory) -> Bool {
        offset = end
        defer {
            while let move = moves.first, move.size <= end {
                moves.removeFirst()
                if move.size == end {
                    self.move(to: move.leaf, into: &history)
                }
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return false
        }
        if object["type"] as? String == "session" {
            cwd = object["cwd"] as? String
            return true
        }
        guard let id = object["id"] as? String else { return true }
        let node = Node(parent: object["parentId"] as? String, steps: steps(object, id: id))
        nodes[id] = node
        if node.parent != nil, node.parent == leaf {
            leaf = id
            Self.apply(node.steps, to: &history)
        } else {
            move(to: id, into: &history)
        }
        return true
    }

    /// `/tree` moved the leaf (nil: before the first entry) when the file was `size` bytes long; pi writes nothing
    /// then. The move shows once the file is read up to there (the state file and this one are two streams), and never
    /// when it was read past it: the entries after it grew from the new leaf already.
    public mutating func tree(_ leaf: String?, at size: Int, into history: inout ChatHistory) {
        if size == offset {
            move(to: leaf, into: &history)
        } else if size > offset {
            moves.append((leaf, size))
        }
    }

    private mutating func move(to leaf: String?, into history: inout ChatHistory) {
        self.leaf = leaf
        var branch: [Node] = [], id = leaf
        while let current = id, let node = nodes[current], branch.count < nodes.count {
            branch.append(node)
            id = node.parent
        }
        history = ChatHistory()
        for node in branch.reversed() {
            Self.apply(node.steps, to: &history)
        }
    }

    private static func apply(_ steps: [Step], to history: inout ChatHistory) {
        for step in steps {
            switch step {
            case let .add(entry): history.append(entry)
            case let .finish(id, result, failed, diff, output, time):
                history.finish(tool: id, result: result, failed: failed, diff: diff, output: output, at: time)
            case let .model(model): history.model = model
            }
        }
    }

    private func steps(_ object: [String: Any], id: String) -> [Step] {
        let time = (object["timestamp"] as? String).flatMap(ChatHistory.date)
        switch object["type"] as? String {
        case "message": break
        case let type? where ["compaction", "branch_summary"].contains(type):
            let text = type == "compaction" ? "Compacted" : "Summarized the branch"
            return [.add(ChatEntry(id: id, .note(text, failed: false), time: time))]
        default: return []
        }
        let message = object["message"] as? [String: Any] ?? [:]
        let blocks = message["content"] as? [[String: Any]] ?? []
        switch message["role"] as? String {
        case "user":
            let text = message["content"] as? String
                ?? blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
            return text.isEmpty ? [] : [.add(ChatEntry(id: id, .user(text), time: time))]
        case "assistant": return assistant(message, blocks, id: id, time: time)
        case "toolResult":
            guard let call = message["toolCallId"] as? String else { return [] }
            return [result(message, blocks, call: call, time: time)]
        case "bashExecution":
            // A `!command` the user ran: a command row with its exit.
            let code = message["exitCode"] as? Int
            let tool = ChatTool(id: id, name: "bash", category: .command,
                                target: ChatHistory.firstLine(message["command"]),
                                input: ChatHistory.detail(message["command"]), started: time)
            let result = message["cancelled"] as? Bool == true ? "cancelled" : code.map { "exit \($0)" } ?? ""
            return [.add(ChatEntry(id: id, .tool(tool), time: time)),
                    .finish(id: id, result: result, failed: code.map { $0 != 0 } ?? false, diff: [],
                            output: ChatHistory.detail(message["output"]), time: time)]
        default: return []
        }
    }

    private func assistant(_ message: [String: Any], _ blocks: [[String: Any]], id: String, time: Date?) -> [Step] {
        var steps: [Step] = (message["model"] as? String).map { [.model($0)] } ?? []
        for (index, block) in blocks.enumerated() {
            let entry = "\(id).\(index)"
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String, !text.isEmpty else { continue }
                steps.append(.add(ChatEntry(id: entry, .reply(text), time: time)))
            case "thinking": steps.append(.add(ChatEntry(id: entry, .thinking, time: time)))
            case "toolCall":
                steps.append(.add(ChatEntry(id: entry, .tool(tool(block, id: entry, time: time)), time: time)))
            default: break
            }
        }
        // Esc while it streams is `aborted`; Esc during a tool is an error that says so.
        let error = message["errorMessage"] as? String ?? ""
        switch message["stopReason"] as? String {
        case "aborted": steps.append(.add(ChatEntry(id: "\(id).end", .note("Interrupted", failed: false), time: time)))
        case "error":
            let note = error.contains("aborted") ? ChatEntry.Kind.note("Interrupted", failed: false)
                : .note(ChatHistory.firstLine(error.isEmpty ? "Error" : error), failed: true)
            steps.append(.add(ChatEntry(id: "\(id).end", note, time: time)))
        default: break
        }
        return steps
    }

    /// pi's own tools by name; any other tool shows its name and first text argument.
    private func tool(_ block: [String: Any], id: String, time: Date?) -> ChatTool {
        let name = block["name"] as? String ?? "tool", input = block["arguments"] as? [String: Any] ?? [:]
        let path = ChatHistory.short(input["path"] as? String ?? "", cwd)
        let (category, target): (ChatTool.Category, String) = switch name {
        case "read": (.read, path)
        case "edit", "write": (.edit, path)
        case "bash": (.command, ChatHistory.firstLine(input["command"]))
        case "grep", "find": (.search, ChatHistory.firstLine(input["pattern"]))
        case "ls": (.search, path)
        default: (.other, ChatHistory.firstLine(input.values.first { $0 is String }))
        }
        return ChatTool(id: block["id"] as? String ?? id, name: name, category: category, target: target,
                        input: ChatHistory.detail(input), started: time)
    }

    /// A result as its row says it: lines read, lines changed with the diff, a failed command's exit, else its first
    /// line.
    private func result(_ message: [String: Any], _ blocks: [[String: Any]], call: String, time: Date?) -> Step {
        let failed = message["isError"] as? Bool == true
        let content = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `-12 old`, `+12 new`, ` 13 same`; `   ...` between hunks has no number.
        let diff: [ChatTool.DiffLine] = ((message["details"] as? [String: Any])?["diff"] as? String ?? "")
            .split(separator: "\n").compactMap { line in
                guard let mark = line.first, "+- ".contains(mark) else { return nil }
                let rest = line.dropFirst().drop { $0 == " " }, digits = rest.prefix { $0.isNumber }
                guard let number = Int(digits) else { return nil }
                return ChatTool.DiffLine(mark: mark, number: number, text: String(rest.dropFirst(digits.count + 1)))
            }
        let text: String
        if failed {
            let last = content.split(separator: "\n").last.map(String.init) ?? ""
            text = last.hasPrefix("Command exited with code ") ? "exit " + last.dropFirst(25)
                : ChatHistory.firstLine(content)
        } else if !diff.isEmpty {
            text = ChatTool.change(diff)
        } else if message["toolName"] as? String == "read" {
            text = ChatHistory.count(content.split(separator: "\n", omittingEmptySubsequences: false).count, "line")
        } else {
            text = ChatHistory.firstLine(content)
        }
        return .finish(id: call, result: text, failed: failed, diff: diff, output: ChatHistory.detail(content),
                       time: time)
    }
}
