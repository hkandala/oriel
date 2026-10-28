import Foundation
import HerdrKit

/// One agent's side of the chat view (future-work/chat-view). The core (`Chat`, the views, `agent.prompt` for
/// sending) is shared; an adapter says how Oriel starts the agent, how it knows the pane again, how it follows the
/// agent's history and phase on the pane's machine, how to stop a turn, and, optionally, how to answer a question.
protocol ChatAdapter: Sendable {
    /// The chooser's command, which is herdr's agent name too (`claude`).
    static var command: String { get }
    /// What the chooser adds to the command for a new launch, with `token` (a fresh lowercase UUID) as its marker.
    static func flags(_ token: String) -> String
    /// The whole launch line, after writing what it needs on the pane's machine; nil: the agent starts without
    /// Oriel's flags (no chat). The command and its flags by default.
    static func prepare(_ token: String, on exec: any Exec) async -> String?
    /// The adapter of the launch whose marker is in the pane's foreground processes (`pane.process_info`), else nil.
    init?(_ foreground: [Program.Foreground])
    /// The launch's marker: a new launch in the same pane is a new chat.
    var token: String { get }
    /// Keys that interrupt a turn, sent only while the agent works.
    var stopKeys: [String] { get }
    /// Follows the agent on its machine until cancelled: the history, the phase it records, its questions and
    /// problems go into the chat. Goes on from the chat's marks.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async
    /// Answers the chat's question; adapters with no channel for questions never set one.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async
}

extension ChatAdapter {
    /// As the chat names it ("Reply to Claude Code"): the chooser's name.
    var name: String {
        Chooser.agents.first { $0.command == Self.command }?.name ?? Self.command
    }

    static func prepare(_ token: String, on _: any Exec) async -> String? {
        command + " " + flags(token)
    }

    func answer(_: ChatQuestion, _: [String: String], on _: any Exec) async {}
}

extension Chat {
    /// Follows the history file while it is the chat's, each line read by the adapter's parser (false: a torn line);
    /// five torn lines in a row are a problem.
    func follow(history source: String, on exec: any Exec, read: (String, inout ChatHistory) -> Bool) async {
        guard let lines = try? await exec.follow(source, from: marks[source] ?? FileMark()) else { return }
        var torn = 0
        for await line in lines where !Task.isCancelled && self.source == source {
            switch line {
            case let .opened(_, restarted) where restarted && !history.entries.isEmpty:
                history = ChatHistory()
            case let .line(text, mark):
                marks[source] = mark
                torn = read(text, &history) ? 0 : torn + 1
                if torn == 5 {
                    problem = "The transcript is not in a format the chat knows"
                }
            case .opened: break
            }
        }
    }
}

enum ChatAdapters {
    static let all: [any ChatAdapter.Type] = [ClaudeCode.self, Codex.self]

    /// The line the chooser types for an agent: its adapter's launch line when it has a chat, else its command.
    static func launch(_ command: String, on exec: any Exec) async -> String {
        guard let adapter = all.first(where: { $0.command == command }) else { return command }
        return await adapter.prepare(UUID().uuidString.lowercased(), on: exec) ?? command
    }

    static func recognize(_ program: Program?) -> (any ChatAdapter)? {
        guard let foreground = program?.foreground, !foreground.isEmpty else { return nil }
        return all.lazy.compactMap { $0.init(foreground) }.first
    }
}
