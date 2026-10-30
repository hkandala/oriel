import Foundation
import HerdrKit

/// One agent's side of the chat view (ui/chat-view); the core (`Chat`, the views, sending with `agent.prompt`) is
/// shared.
protocol ChatAdapter: Sendable {
    /// The chooser's command, which is herdr's agent name too (`claude`).
    static var command: String { get }
    /// What the chooser adds to the command for a new launch, with `token` (a fresh lowercase UUID) as its marker, and
    /// `resume`'s arguments for Relaunch with Chat.
    static func flags(_ token: String, resume: String?) -> String
    /// The whole launch line, after writing what it needs on the pane's machine; nil: the agent starts without
    /// Oriel's flags (no chat). The command and its flags by default.
    static func prepare(_ token: String, resume: String?, on exec: any Exec) async -> String?
    /// The arguments that resume a session (herdr's `agent_session` value); nil when the value is not one this agent
    /// takes (no Relaunch with Chat then). They go into a typed line: only plain ids and quotable paths.
    static func resume(_ session: String) -> String?
    /// The command that quits it, typed into its prompt.
    static var quit: String { get }
    /// Keys that interrupt a turn, sent only while the agent works.
    static var stopKeys: [String] { get }
    /// The adapter of the launch whose marker is in the pane's foreground processes (`pane.process_info`), else nil.
    init?(_ foreground: [Program.Foreground])
    /// The launch's marker: a new launch in the same pane is a new chat.
    var token: String { get }
    /// Follows the agent on its machine until cancelled: the history, the phase it records, its questions and
    /// problems go into the chat. Goes on from the chat's marks.
    @MainActor func follow(_ chat: Chat, on exec: any Exec) async
    /// Answers the chat's question; false when it did not reach the agent. Adapters with no channel for questions
    /// never set one.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async -> Bool
}

extension ChatAdapter {
    /// The launch's side files, under the home folder of the pane's machine: the user's own, on a shared machine too.
    var folder: String {
        ".cache/oriel/chat/\(token)"
    }

    /// As the chat names it ("Claude Code is asking in the terminal"): the chooser's name.
    var name: String {
        Chooser.agents.first { $0.command == Self.command }?.name ?? Self.command
    }

    static func prepare(_ token: String, resume: String?, on _: any Exec) async -> String? {
        command + " " + flags(token, resume: resume)
    }

    func answer(_: ChatQuestion, _: [String: String], on _: any Exec) async -> Bool {
        false
    }
}

extension Chat {
    private static let unknownFormat = "The transcript is not in a format the chat knows"

    /// Follows an agent's side file from the chat's mark: `line` gives a line's history file when it starts a session
    /// (and handles any other line itself). A new file is the history from its start. `late`: no session after 10 s is
    /// a problem. `skip`: the lines of the history file its parser skips (`Exec.follow`).
    func followSessions(_ sideFile: String, on exec: any Exec, late: Bool, skip: String = "0",
                        read: @escaping (String, inout ChatHistory) -> Bool, restarted: @escaping () -> Void = {},
                        line: ([String: Any]) async -> String?) async
    {
        var transcript: Task<Void, Never>?
        // One history follow at a time: they share the chat's backlog.
        let follow = { (source: String) in
            let old = transcript
            old?.cancel()
            transcript = Task {
                await old?.value
                guard !Task.isCancelled else { return }
                await self.follow(history: source, on: exec, skip: skip, read: read, restarted: restarted)
            }
        }
        let timer = Task {
            try? await Task.sleep(for: .seconds(10))
            if late, !Task.isCancelled, source == nil {
                problem = "\(adapter.name) has not started a session"
            }
        }
        defer { timer.cancel() }
        guard let lines = try? await exec.follow(sideFile, from: marks[sideFile] ?? FileMark()) else { return }
        if let source {
            follow(source)
        }
        // Lines buffered before a cancel still come: not into the next follow's chat.
        for await batch in lines {
            for entry in batch where !Task.isCancelled {
                guard case let .line(text, mark) = entry else { continue }
                marks[sideFile] = mark
                guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      let next = await line(object), !Task.isCancelled else { continue }
                problem = nil
                guard next != source else { continue }
                source = next
                history = ChatHistory()
                // A resumed session's file again: from its start, not from where the chat left it.
                marks[next] = nil
                follow(next)
            }
        }
        transcript?.cancel()
        await transcript?.value
    }

    /// Changes the history a follow builds: the backlog while it loads, else the one the card shows.
    func change<T>(_ body: (inout ChatHistory) -> T) -> T {
        loading ? body(&backlog) : body(&history)
    }

    /// Follows the history file while it is the chat's, each line read by the adapter's parser (false: a torn line);
    /// five torn lines in a row are a problem, until a good one. `restarted`: the file was rewritten. What the file
    /// held when opened goes into the backlog, which shows whole once read (a long session would show row by row, and
    /// rebuild every row each time).
    private func follow(history source: String, on exec: any Exec, skip: String,
                        read: (String, inout ChatHistory) -> Bool, restarted: () -> Void) async
    {
        guard let lines = try? await exec.follow(source, from: marks[source] ?? FileMark(), skip: skip) else { return }
        var torn = 0, count = 0
        (loading, backlog) = (true, history)
        // A batch's lines in one main-actor turn: the card draws once for them, not once per line.
        for await batch in lines {
            for line in batch where !Task.isCancelled && self.source == source {
                switch line {
                case let .opened(_, again) where again && !backlog.entries.isEmpty:
                    backlog = ChatHistory()
                    restarted()
                case let .line(text, mark):
                    marks[source] = mark
                    torn = change { read(text, &$0) } ? 0 : torn + 1
                    check(torn: torn)
                    count += 1
                    // A long session takes a second to read: the app goes on meanwhile (the backlog draws only once
                    // read).
                    if loading, count.isMultiple(of: 200) {
                        await Task.yield()
                    }
                case .loaded: showBacklog()
                case .opened: break
                }
            }
        }
        // Cut short (the card went, the connection dropped): the marks went on, so the history keeps what they read;
        // unless it is another session's now.
        if loading {
            showBacklog(self.source == source)
        }
    }

    private func check(torn: Int) {
        if torn == 5 {
            problem = Self.unknownFormat
        } else if torn == 0, problem == Self.unknownFormat {
            problem = nil
        }
    }

    private func showBacklog(_ show: Bool = true) {
        loading = false
        if show {
            history = backlog
        }
        // Let go of the copy, or the history's next line would copy it whole.
        backlog = ChatHistory()
    }
}

enum ChatAdapters {
    static let all: [any ChatAdapter.Type] = [ClaudeCode.self, Codex.self, PiAgent.self, OpenCode.self]

    /// Every adapter's side files untouched for 30 days go, then empty folders (appends do not change a folder's
    /// time; a minute old: not one a launch just made). Plain, unquoted sh: Claude Code's and Codex's hooks hold no
    /// quote. ponytail: `$HOME` unquoted (a home folder with a space keeps its files); a session idle 30 days loses
    /// its chat on a relaunch: touch the files on use if that shows up.
    static let sweep = "find $HOME/.cache/oriel/chat -mindepth 2 -mtime +30 -delete 2>/dev/null;"
        + "find $HOME/.cache/oriel/chat -mindepth 1 -type d -empty -mmin +1 -delete 2>/dev/null"

    /// The line the chooser types for an agent with a chat; nil when it has none or its run on the machine failed.
    /// `resume`: herdr's session of the agent, for Relaunch with Chat (nil also when the agent does not take it).
    static func launch(_ command: String, resume: String? = nil, on exec: any Exec) async -> String? {
        guard let adapter = adapter(command) else { return nil }
        let arguments = resume.flatMap(adapter.resume)
        guard resume == nil || arguments != nil else { return nil }
        return await adapter.prepare(UUID().uuidString.lowercased(), resume: arguments, on: exec)
    }

    static func adapter(_ command: String?) -> (any ChatAdapter.Type)? {
        all.first { $0.command == command }
    }

    /// A launch's marker: a lowercase UUID.
    static func token(_ id: some StringProtocol) -> String? {
        UUID(uuidString: String(id)) != nil && id == id.lowercased() ? String(id) : nil
    }

    /// The marker right after `/.cache/oriel/chat/` in an argument: a launch's side folder.
    static func token(in argument: String) -> String? {
        argument.range(of: "/.cache/oriel/chat/").flatMap { token(argument[$0.upperBound...].prefix(36)) }
    }

    /// The first marker `token` finds in a foreground process's argv, and the processes that carry that one.
    static func marked(_ foreground: [Program.Foreground],
                       _ token: ([String]) -> String?) -> (token: String, pids: [Int])?
    {
        var found: String?, pids: [Int] = []
        for process in foreground {
            guard let id = token(process.argv), found == nil || found == id else { continue }
            found = id
            pids.append(process.pid)
        }
        return found.map { ($0, pids) }
    }

    /// A UUID as it goes into a typed line.
    static func uuid(_ value: String) -> String? {
        UUID(uuidString: value) != nil ? value : nil
    }

    static func recognize(_ program: Program?) -> (any ChatAdapter)? {
        guard let foreground = program?.foreground, !foreground.isEmpty else { return nil }
        return all.lazy.compactMap { $0.init(foreground) }.first
    }
}

extension [String] {
    /// The argument after `flag`.
    func after(_ flag: String) -> String? {
        firstIndex(of: flag).flatMap { $0 + 1 < count ? self[$0 + 1] : nil }
    }
}
