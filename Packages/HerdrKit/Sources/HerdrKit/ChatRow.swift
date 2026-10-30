import Foundation

/// The detail level (ui/chat-view#detail-levels).
public enum ChatLevel: String, CaseIterable, Sendable {
    case replies, activity, everything
}

public enum ChatRow: Equatable, Sendable, Identifiable {
    case user(id: String, text: String)
    /// A turn's quiet line on top: "Read 2 files, ran 3 commands". `steps`: the turn's tool calls and thinking, which
    /// it opens to (Activity).
    case summary(id: String, counts: String, steps: [ChatEntry])
    /// "Worked 1m 48s" under a finished turn that has its quiet line.
    case worked(id: String, seconds: Double?)
    case reply(id: String, text: String)
    case thinking(id: String)
    /// A run of tool calls, with the thinking between them, between two replies.
    case stack(id: String, steps: [ChatEntry])
    case todos(id: String, [ChatTodo])
    case note(id: String, text: String, failed: Bool)

    public var id: String {
        switch self {
        case let .user(id, _), let .summary(id, _, _), let .worked(id, _), let .reply(id, _), let .thinking(id),
             let .stack(id, _), let .todos(id, _), let .note(id, _, _): id
        }
    }
}

public extension ChatHistory {
    /// The rows at a level. Replies: the user's messages, each turn's quiet line, its last reply, its notes and how
    /// long it worked; Activity: the same, the line opening to the turn's steps. Everything: no line; every reply,
    /// todo list and note, and each run of tool calls and thinking as one stack, as pi-content-layout groups them.
    /// `working`: the last turn runs on.
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
        guard level == .everything else {
            let tools = body.compactMap(\.tool)
            if !tools.isEmpty {
                rows.append(.summary(id: "\(turn[0].id).summary", counts: ChatTool.summary(tools),
                                     steps: level == .activity ? body.filter(\.isStep) : []))
            }
            let reply = body.last { $0.row?.isReply == true }?.id
            rows += body.compactMap { entry in
                guard let row = entry.row, entry.id == reply || row.isNote else { return nil }
                return row
            }
            // While it runs, the chat's own loader says "Working ‹time›" there.
            if !running, !tools.isEmpty {
                rows.append(.worked(id: "\(turn[0].id).worked", seconds: seconds(body)))
            }
            return rows
        }
        var run: [ChatEntry] = []
        // Thinking alone is its own row; with tool calls it is one of the run's steps.
        func flush() {
            if run.contains(where: { $0.tool != nil }) {
                rows.append(.stack(id: run[0].id, steps: run))
            } else if let first = run.first {
                rows.append(.thinking(id: first.id))
            }
            run = []
        }
        for entry in body {
            if entry.isStep {
                run.append(entry)
            } else if let row = entry.row {
                flush()
                rows.append(row)
            }
        }
        flush()
        return rows
    }

    /// When the last turn started: the chat's "Working ‹time›" counts from there.
    var lastTurnStart: Date? {
        (entries.last { $0.user != nil } ?? entries.first)?.time
    }

    /// The turn's own measure, else from its first entry to its last.
    private static func seconds(_ body: ArraySlice<ChatEntry>) -> Double? {
        body.lazy.compactMap(\.seconds).last
            ?? body.first?.time.flatMap { first in body.last?.time?.timeIntervalSince(first) }
    }
}

public extension ChatRow {
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
