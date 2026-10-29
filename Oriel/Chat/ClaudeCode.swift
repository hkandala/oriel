import Foundation
import HerdrKit

/// Claude Code (resources/research/agents/claude-code.md). Started with `--session-id T` (or `--resume <session>`) and
/// inline hooks in `--settings`: a SessionStart hook appends each session's transcript path to
/// `~/.cache/oriel/chat/T/hooks.jsonl`, and a PermissionRequest hook for AskUserQuestion only appends the question
/// there and waits for the chat's answer file. Its phase is its session record, `~/.claude/sessions/<pid>.json`
/// (undocumented; herdr's status without one).
struct ClaudeCode: ChatAdapter {
    static let command = "claude"
    let token: String
    /// The processes that carry the marker: one of them has the session record.
    let pids: [Int]
    static let stopKeys = ["escape"]
    static let quit = "/exit"

    /// The hooks hold no quote and no backslash, so the single-quoted JSON reads the same in sh, bash, zsh and fish.
    /// `set -f`: `[:cntrl:]` is no file pattern. The question hook writes its pid to `ask` and waits for `answer` while
    /// `ask` still holds its pid (a newer question's hook, or the chat seeing it answered in the terminal, ends it) and
    /// Claude lives, 30 minutes at most.
    /// ponytail: `$HOME` unquoted, so a home folder with a space gets no chat; quote it (escaped JSON) if one shows up.
    static func flags(_ token: String, resume: String?) -> String {
        let folder = "umask 077;set -f;d=$HOME/.cache/oriel/chat/\(token);mkdir -p $d"
        let start = "\(folder);{ tr -d [:cntrl:];echo;}>>$d/hooks.jsonl;" + ChatAdapters.sweep
        let ask = "\(folder);rm -f $d/answer;echo $$ >$d/ask;{ tr -d [:cntrl:];echo;}>>$d/hooks.jsonl;n=0;"
            + "while [ $n -lt 9000 ] && grep -qx $$ $d/ask 2>/dev/null && kill -0 $PPID 2>/dev/null;do "
            + "if [ -f $d/answer ];then cat $d/answer;rm -f $d/answer $d/ask;exit 0;fi;sleep 0.2;n=$((n+1));done;"
            + "grep -qx $$ $d/ask 2>/dev/null && rm -f $d/ask"
        let settings = #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","timeout":10,"command":"\#(start)"}]}],"#
            + #""PermissionRequest":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","timeout":1810,"#
            + #""command":"\#(ask)"}]}]}}"#
        return "\(resume ?? "--session-id \(token)") --settings '\(settings)'"
    }

    /// The same session again: its hooks report it (`source: resume`) with its transcript.
    static func resume(_ session: String) -> String? {
        ChatAdapters.uuid(session).map { "--resume \($0)" }
    }

    /// The hooks' folder for T in the `--settings` value: the launcher's own `claude`, its `dotslash` and the native
    /// binary all carry it.
    init?(_ foreground: [Program.Foreground]) {
        let marked = ChatAdapters.marked(foreground) { $0.after("--settings").flatMap(ChatAdapters.token(in:)) }
        guard let (token, pids) = marked else { return nil }
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
        let sideFile = folder + "/hooks.jsonl"
        await chat.followSessions(sideFile, on: exec, late: true, read: ClaudeTranscript.read) { object in
            if object["hook_event_name"] as? String == "SessionStart" {
                return object["transcript_path"] as? String
            }
            if object["tool_name"] as? String == "AskUserQuestion",
               let questions = (object["tool_input"] as? [String: Any])?["questions"] as? [[String: Any]]
            {
                // Only while its hook waits: a new chat reads the file from the start, old questions too.
                let question = Self.question(questions)
                if await exec.succeeds(#"test -f "$HOME/$1/ask""#, [folder]), !Task.isCancelled {
                    chat.question = question
                }
            }
            return nil
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
                await exec.succeeds(#"rm -f "$HOME/$1/ask""#, [folder])
            }
        }
    }

    /// Single choices with options only: the terminal answers the rest.
    private static func question(_ questions: [[String: Any]]) -> ChatQuestion? {
        guard let items = ChatQuestion.items(questions, several: "multiSelect"),
              let raw = try? JSONSerialization.data(withJSONObject: questions) else { return nil }
        return ChatQuestion(items: items, raw: raw)
    }

    /// The hook prints this decision: allow, with the questions echoed and the answers by question text. Written whole
    /// (a temporary file, then a rename), and only while the hook still waits (else false: the hook is gone).
    func answer(_ question: ChatQuestion, _ answers: [String: String], on exec: any Exec) async -> Bool {
        guard let questions = try? JSONSerialization.jsonObject(with: question.raw),
              let data = try? JSONSerialization.data(withJSONObject: [
                  "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": [
                      "behavior": "allow", "updatedInput": ["questions": questions, "answers": answers],
                  ]],
              ]) else { return false }
        let script = #"d="$HOME/$1"; [ -f "$d/ask" ] && cat >"$d/answer.tmp" && mv "$d/answer.tmp" "$d/answer""#
        return await exec.succeeds(script, [folder], input: [String(decoding: data, as: UTF8.self)])
    }
}
