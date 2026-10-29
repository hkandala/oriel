import Foundation

/// Where each agent keeps its session's title (resources/research/agents): Claude Code in its transcript (`ai-title`
/// lines it writes itself, `custom-title` from `/rename`), Codex in `~/.codex/session_index.jsonl` (`thread_name`),
/// pi in its session file (`session_info` from `/name`; pi names no session itself), OpenCode in its database
/// (`session.title`, the same as its server's). Each script prints the lines `parse` reads, on the pane's machine.
enum SessionTitle {
    static let scripts = [
        // The id's transcript, in any project folder.
        "claude": #"f=$(ls "$HOME"/.claude/projects/*/"$1".jsonl | head -n 1); "#
            + #"grep -a '"type":"custom-title"' "$f" | tail -n 1; grep -a '"type":"ai-title"' "$f" | tail -n 1"#,
        "codex": #"grep -a -F "\"id\":\"$1\"" "$HOME/.codex/session_index.jsonl" | tail -n 1"#,
        "pi": #"grep -a '"type":"session_info"' "$1" | tail -n 1"#,
        "opencode": #"sqlite3 -readonly -cmd '.timeout 1000' "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/"#
            + #"opencode.db" "select title from session where id = '$1'""#,
    ]

    /// The title in the script's output; nil when there is none yet (OpenCode's own placeholder too).
    static func parse(agent: String, _ text: String) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        let title: String? = if agent == "opencode" {
            lines.first.flatMap { $0.hasPrefix("New session - ") || $0.hasPrefix("Child session - ") ? nil : $0 }
        } else {
            lines.lazy.compactMap { line in
                let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                return ["customTitle", "aiTitle", "thread_name", "name"].lazy.compactMap { object?[$0] as? String }
                    .first
            }.first
        }
        let clean = title?.filter { !$0.isControl }.trimmingCharacters(in: .whitespaces).prefix(200)
        return clean.flatMap { $0.isEmpty ? nil : String($0) }
    }
}

public extension Exec {
    /// The title of an agent's session, from herdr's `agent_session` value; nil when it has none yet, or for an agent
    /// with no known place for one.
    func sessionTitle(agent: String, session: String) async -> String? {
        // pi's is a file; the others' ids go into OpenCode's SQL and Claude Code's file name: letters, digits, `-` and
        // `_` only.
        let plain = session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
        let id = !session.isEmpty && plain
        guard let script = SessionTitle.scripts[agent], agent == "pi" ? session.hasPrefix("/") : id else { return nil }
        let text = try? await output(["sh", "-c", "{ \(script); } 2>/dev/null", "sh", session], timeout: .seconds(5))
        return SessionTitle.parse(agent: agent, text ?? "")
    }
}
