import Foundation
import HerdrKit

/// Claude Code (resources/research/agents/claude-code.md). Started with `--session-id T` and inline hooks in
/// `--settings`: a SessionStart hook appends each session's transcript path to `~/.cache/oriel/chat/T/hooks.jsonl`, and
/// a PermissionRequest hook for AskUserQuestion only appends the question there and waits for the chat's answer file.
/// Its phase is its session record, `~/.claude/sessions/<pid>.json` (undocumented; herdr's status without one).
struct ClaudeCode: ChatAdapter {
    static let command = "claude"
    let token: String
    /// The processes that carry the marker: one of them has the session record.
    let pids: [Int]
    let stopKeys = ["escape"]

    /// Under the home folder of the pane's machine: the user's own, on a shared machine too.
    var folder: String {
        ".cache/oriel/chat/\(token)"
    }

    /// The hooks hold no quote and no backslash, so the single-quoted JSON reads the same in sh, bash, zsh and fish.
    /// `set -f`: `[:cntrl:]` is no file pattern. The question hook writes its pid to `ask` and waits for `answer` while
    /// `ask` still holds its pid (a newer question's hook, or the chat seeing it answered in the terminal, ends it) and
    /// Claude lives, 30 minutes at most.
    /// ponytail: `$HOME` unquoted, so a home folder with a space gets no chat; quote it (escaped JSON) if one shows up.
    static func flags(_ token: String) -> String {
        let folder = "umask 077;set -f;d=$HOME/.cache/oriel/chat/\(token);mkdir -p $d"
        // The launches' folders untouched for 30 days go.
        let start = "\(folder);{ tr -d [:cntrl:];echo;}>>$d/hooks.jsonl;"
            + "find $HOME/.cache/oriel/chat -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null"
        let ask = "\(folder);rm -f $d/answer;echo $$ >$d/ask;{ tr -d [:cntrl:];echo;}>>$d/hooks.jsonl;n=0;"
            + "while [ $n -lt 9000 ] && grep -qx $$ $d/ask 2>/dev/null && kill -0 $PPID 2>/dev/null;do "
            + "if [ -f $d/answer ];then cat $d/answer;rm -f $d/answer $d/ask;exit 0;fi;sleep 0.2;n=$((n+1));done;"
            + "grep -qx $$ $d/ask 2>/dev/null && rm -f $d/ask"
        let settings = #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","timeout":10,"command":"\#(start)"}]}],"#
            + #""PermissionRequest":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","timeout":1810,"#
            + #""command":"\#(ask)"}]}]}}"#
        return "--session-id \(token) --settings '\(settings)'"
    }

    /// `--session-id T` with T a UUID, and the hooks' folder for T in the same argv: the launcher's own `claude`, its
    /// `dotslash` and the native binary all carry both.
    init?(_ foreground: [Program.Foreground]) {
        var token: String?, pids: [Int] = []
        for process in foreground {
            guard let flag = process.argv.firstIndex(of: "--session-id"),
                  flag + 1 < process.argv.count else { continue }
            let id = process.argv[flag + 1]
            guard UUID(uuidString: id) != nil, id == id.lowercased(), token == nil || token == id,
                  process.argv.contains(where: { $0.contains("/.cache/oriel/chat/\(id);") }) else { continue }
            token = id
            pids.append(process.pid)
        }
        guard let token else { return nil }
        self.token = token
        self.pids = pids
    }

    @MainActor func follow(_ chat: Chat, on exec: any Exec) async {
        await withDiscardingTaskGroup { group in
            group.addTask { await hooks(chat, exec) }
            group.addTask { await phases(chat, exec) }
        }
    }

    /// The side file: the last SessionStart's transcript is the history (a new one after `/clear`, a fork or a
    /// resume starts the history again); a question shows until it is answered. No session after 10 s: a problem.
    @MainActor private func hooks(_ chat: Chat, _ exec: any Exec) async {
        let path = folder + "/hooks.jsonl"
        var transcript: Task<Void, Never>?
        defer { transcript?.cancel() }
        let follow = { (source: String) in
            transcript?.cancel()
            transcript = Task { await history(chat, source, exec) }
        }
        if let source = chat.source {
            follow(source)
        }
        let late = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled, chat.source == nil {
                chat.problem = "Claude Code has not started a session"
            }
        }
        defer { late.cancel() }
        guard let lines = try? await exec.follow(path, from: chat.marks[path] ?? FileMark()) else { return }
        // Lines buffered before a cancel still come: not into the next follow's chat.
        for await line in lines where !Task.isCancelled {
            guard case let .line(text, mark) = line else { continue }
            chat.marks[path] = mark
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            else { continue }
            if object["hook_event_name"] as? String == "SessionStart",
               let source = object["transcript_path"] as? String
            {
                chat.problem = nil
                if source != chat.source {
                    chat.source = source
                    chat.history = ChatHistory()
                    follow(source)
                }
            } else if object["tool_name"] as? String == "AskUserQuestion",
                      let questions = (object["tool_input"] as? [String: Any])?["questions"] as? [[String: Any]]
            {
                // Only while its hook waits: a new chat reads the file from the start, old questions too.
                let question = Self.question(questions)
                if await run(["sh", "-c", #"test -f "$HOME/$1/ask""#, "sh", folder], exec) == 0, !Task.isCancelled {
                    chat.question = question
                }
            }
        }
    }

    @MainActor private func history(_ chat: Chat, _ source: String, _ exec: any Exec) async {
        guard let lines = try? await exec.follow(source, from: chat.marks[source] ?? FileMark()) else { return }
        var torn = 0
        for await line in lines where !Task.isCancelled && chat.source == source {
            switch line {
            case let .opened(_, restarted) where restarted && !chat.history.entries.isEmpty:
                chat.history = ChatHistory()
            case let .line(text, mark):
                chat.marks[source] = mark
                torn = ClaudeTranscript.read(text, into: &chat.history) ? 0 : torn + 1
                if torn == 5 {
                    chat.problem = "The transcript is not in a format the chat knows"
                }
            case .opened: break
            }
        }
    }

    /// The session record's `status`: idle (and `shell`, a background command) is ready, busy works, waiting waits for
    /// a dialog, a question or a picker. A question answered in the terminal ends the wait: its hook may go.
    @MainActor private func phases(_ chat: Chat, _ exec: any Exec) async {
        guard let records = try? await exec.watch(pids.map { ".claude/sessions/\($0).json" }) else { return }
        for await text in records where !Task.isCancelled {
            let status = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["status"]
            let waited = chat.phase == .waiting
            chat.recorded = switch status as? String {
            case "idle", "shell": .ready
            case "busy": .working
            case "waiting": .waiting
            default: nil
            }
            if waited, chat.phase != .waiting, chat.question != nil {
                chat.question = nil
                await run(["sh", "-c", #"rm -f "$HOME/$1/ask""#, "sh", folder], exec)
            }
        }
    }

    /// Single choices only: a question with several answers is answered in the terminal.
    private static func question(_ questions: [[String: Any]]) -> ChatQuestion? {
        guard !questions.isEmpty, !questions.contains(where: { $0["multiSelect"] as? Bool == true }),
              let raw = try? JSONSerialization.data(withJSONObject: questions) else { return nil }
        return ChatQuestion(items: questions.map { question in
            ChatQuestion.Item(text: question["question"] as? String ?? "",
                              options: (question["options"] as? [[String: Any]] ?? [])
                                  .compactMap { $0["label"] as? String })
        }, raw: raw)
    }

    /// A short run's exit status.
    @discardableResult
    private func run(_ argv: [String], _ exec: any Exec) async -> Int32 {
        guard let channel = try? await exec.run(argv) else { return -1 }
        channel.closeInput()
        return await channel.exit().status
    }

    /// The hook prints this decision: allow, with the questions echoed and the answers by question text. Written whole
    /// (a temporary file, then a rename), and only while the hook still waits.
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async {
        guard let questions = try? JSONSerialization.jsonObject(with: question.raw),
              let data = try? JSONSerialization.data(withJSONObject: [
                  "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": [
                      "behavior": "allow", "updatedInput": ["questions": questions, "answers": answers],
                  ]],
              ]) else { return }
        let script = #"d="$HOME/$1"; [ -f "$d/ask" ] && cat >"$d/answer.tmp" && mv "$d/answer.tmp" "$d/answer""#
        guard let channel = try? await exec.run(["sh", "-c", script, "sh", folder]) else { return }
        channel.write(String(decoding: data, as: UTF8.self))
        channel.closeInput()
        _ = await channel.exit()
    }
}
