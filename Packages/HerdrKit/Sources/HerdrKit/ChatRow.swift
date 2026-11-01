import Foundation

public enum ChatRow: Equatable, Sendable, Identifiable {
    case user(id: String, text: String)
    /// A run of tool calls, with the thinking between them, between two messages: one line of its counts ("Ran 3
    /// commands, read 2 files"). `steps`: where the run is in the history's entries; the chat reads them for the
    /// counts of the rows it shows, and its rows only while it is open.
    case stack(id: String, steps: Range<Int>)
    /// "Worked 1m 48s" under a finished turn with tool calls.
    case worked(id: String, seconds: Double?)
    case reply(id: String, text: String)
    case todos(id: String, [ChatTodo])
    case note(id: String, text: String, failed: Bool)

    public var id: String {
        switch self {
        case let .user(id, _), let .stack(id, _), let .worked(id, _), let .reply(id, _), let .todos(id, _),
             let .note(id, _, _): id
        }
    }
}

public extension ChatHistory {
    /// The chat's rows (ui/chat-view#messages): the user's messages; every reply, todo list and note in order; each run
    /// of tool calls between them as one line, its thinking among its steps; and "Worked" under a finished turn with
    /// tool calls. Thinking with no tool call in its run has no row. `working`: the last turn runs on.
    func rows(working: Bool) -> [ChatRow] {
        var rows: [ChatRow] = [], turn = 0, run = 0 ..< 0
        func endRun() {
            if entries[run].contains(where: { $0.tool != nil }) {
                rows.append(.stack(id: entries[run.lowerBound].id, steps: run))
            }
        }
        func endTurn(at end: Int, running: Bool) {
            endRun()
            let body = entries[turn ..< end].drop { $0.user != nil }
            // While it runs, the chat's own loader says "Working ‹time›" there.
            if !running, body.contains(where: { $0.tool != nil }) {
                rows.append(.worked(id: "\(entries[turn].id).worked", seconds: Self.seconds(body)))
            }
        }
        for (index, entry) in entries.enumerated() {
            if let text = entry.user {
                endTurn(at: index, running: false)
                turn = index
                rows.append(.user(id: entry.id, text: text))
            } else if entry.isStep {
                run = (run.isEmpty ? index : run.lowerBound) ..< index + 1
                continue
            } else {
                // A message, or a turn's end (a run never spans two turns).
                endRun()
                if let row = entry.row {
                    rows.append(row)
                }
            }
            run = index + 1 ..< index + 1
        }
        endTurn(at: entries.endIndex, running: working)
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
