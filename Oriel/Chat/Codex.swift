import Foundation
import HerdrKit

/// Codex (resources/research/agents/codex.md). Started with an inline SessionStart hook (`-c hooks.SessionStart=…`)
/// that appends each session's JSON, with its rollout's path, to `~/.cache/oriel/chat/T/hooks.jsonl`, and that hook's
/// trust hash (`-c hooks.state=…`), so Codex asks nothing and no bypass flag trusts other hooks. Tool approvals and
/// questions stay in its terminal: herdr reports them as blocked.
struct Codex: ChatAdapter {
    static let command = "codex"
    let token: String
    let stopKeys = ["escape"]

    /// Codex runs it with the user's login shell (`$SHELL -lc`), fish too: plain commands with no variable of its
    /// own, no quote and no backslash. It runs at each session's first prompt, not at launch. The launches' folders
    /// untouched for 30 days go.
    /// ponytail: `$HOME` unquoted, so a home folder with a space gets no chat, as with Claude Code.
    static func hook(_ token: String) -> String {
        let folder = "$HOME/.cache/oriel/chat/\(token)", file = "$HOME/.cache/oriel/chat/\(token)/hooks.jsonl"
        return "umask 077;mkdir -p \(folder);cat>>\(file);echo>>\(file);"
            + "find $HOME/.cache/oriel/chat -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} +"
    }

    /// The trust key is the `-c` layer's own (`codex-rs/hooks`); an inline table, as the `-c` parser splits a dotted
    /// key on every dot.
    static func flags(_ token: String) -> String {
        let hook = hook(token), trust = CodexRollout.trust(hook)
        return #"-c 'hooks.SessionStart=[{hooks=[{type="command",command="\#(hook)"}]}]' "#
            + #"-c 'hooks.state={"/<session-flags>/config.toml:session_start:0:0"={trusted_hash="\#(trust)"}}'"#
    }

    /// The hook's folder for T in a `hooks.SessionStart` value: the launcher's `codex` and the native binary both
    /// carry it.
    init?(_ foreground: [Program.Foreground]) {
        let token = foreground.lazy.flatMap(\.argv).compactMap { argument -> String? in
            guard argument.hasPrefix("hooks.SessionStart="),
                  let folder = argument.range(of: "/.cache/oriel/chat/") else { return nil }
            let id = String(argument[folder.upperBound...].prefix(36))
            return UUID(uuidString: id) != nil && id == id.lowercased() ? id : nil
        }.first
        guard let token else { return nil }
        self.token = token
    }

    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        await withDiscardingTaskGroup { group in
            group.addTask { await sessions(chat, exec) }
            group.addTask { await screens(chat) }
        }
    }

    /// The last SessionStart with a rollout is the history: a new one after `/new`, `/clear`, a fork or a resume,
    /// at its first prompt. One with no rollout (a hidden thread of Codex's own) is not.
    @MainActor private func sessions(_ chat: Chat, _ exec: any Exec) async {
        let path = ".cache/oriel/chat/\(token)/hooks.jsonl"
        var rollout: Task<Void, Never>?
        defer { rollout?.cancel() }
        let follow = { (source: String) in
            rollout?.cancel()
            rollout = Task { await chat.follow(history: source, on: exec, read: CodexRollout.read) }
        }
        if let source = chat.source {
            follow(source)
        }
        guard let lines = try? await exec.follow(path, from: chat.marks[path] ?? FileMark()) else { return }
        // Lines buffered before a cancel still come: not into the next follow's chat.
        for await line in lines where !Task.isCancelled {
            guard case let .line(text, mark) = line else { continue }
            chat.marks[path] = mark
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let source = object["transcript_path"] as? String, source != chat.source else { continue }
            chat.source = source
            chat.history = ChatHistory()
            follow(source)
        }
    }

    /// herdr reports a picker or a dialog as idle: while it says idle or working, a screen whose last rows lack the
    /// input box above the status row waits too (two reads in a row, not a redraw), so the live terminal shows and
    /// nothing is sent into the picker. The last rows, not the visible ones: the user may have scrolled the pane.
    @MainActor private func screens(_ chat: Chat) async {
        var misses = 0
        while !Task.isCancelled {
            var ready = true
            if let state = chat.store?.pane(chat.paneID)?.state, state != .needsYou, let client = chat.store?.client,
               let screen = try? await client.recent(chat.paneID, lines: 8)
            {
                ready = CodexRollout.ready(screen)
            }
            misses = ready ? 0 : misses + 1
            let recorded: Chat.Phase? = misses >= 2 ? .waiting : nil
            // Only a change: Observation reports equal writes too.
            if !Task.isCancelled, chat.recorded != recorded {
                chat.recorded = recorded
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}
