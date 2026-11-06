import Foundation

/// A session of an agent, from the agent's own store on its machine: what the Agents view's Archived shelf lists and
/// resumes.
public struct ClosedSession: Sendable, Hashable, Identifiable {
    /// herdr's agent name, the chooser's command (`claude`).
    public let agent: String
    /// As herdr's `agent_session` value: pi's session file, the others' ids.
    public let value: String
    public let title: String
    /// The folder the agent ran in.
    public let folder: String
    /// Its last activity.
    public let date: Date

    public var id: String {
        agent + " " + value
    }

    public init(agent: String, value: String, title: String, folder: String, date: Date) {
        (self.agent, self.value, self.title, self.folder, self.date) = (agent, value, title, folder, date)
    }
}

/// One agent's page of sessions, newest first.
public struct ClosedPage: Sendable, Equatable {
    public var sessions: [ClosedSession] = []
    /// The store may hold older ones.
    public var more = false
    /// Why the store could not be read, for the user ("needs sqlite3").
    public var problem: String?
    /// The sessions looked at, those left out too: the next page's offset.
    public var looked = 0
    /// The last activity of the oldest one looked at.
    public var oldest: Date?

    public init(sessions: [ClosedSession] = [], more: Bool = false, problem: String? = nil) {
        (self.sessions, self.more, self.problem) = (sessions, more, problem)
    }
}

/// The pages read so far of each agent, as one list newest first.
public struct ClosedList: Sendable, Equatable {
    public private(set) var agents: [String: ClosedPage] = [:]

    public init() {}

    public mutating func add(_ page: ClosedPage, for agent: String) {
        var all = agents[agent] ?? ClosedPage()
        all.sessions += page.sessions
        (all.more, all.problem, all.looked) = (page.more, page.problem, all.looked + page.looked)
        all.oldest = page.oldest ?? all.oldest
        agents[agent] = all
    }

    /// The sessions of the `shown` agents, newest first, down to where every one with more pages has been read: an
    /// agent's next page may hold newer ones than another's last.
    public func sessions(of shown: [String]) -> [ClosedSession] {
        let cutoff = cutoff(shown) ?? .distantPast
        return shown.flatMap { agents[$0]?.sessions ?? [] }.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
    }

    /// The agents whose next page the list's end needs: those read least far back.
    public func next(of shown: [String]) -> [String] {
        let cutoff = cutoff(shown)
        return shown.filter { agents[$0]?.more == true && agents[$0]?.oldest == cutoff }
    }

    private func cutoff(_ shown: [String]) -> Date? {
        shown.compactMap { agents[$0].flatMap { $0.more ? $0.oldest : nil } }.max()
    }
}

/// One script per agent, one process for a page of 50, never one per session file (a process costs about 20 ms on a
/// Mac with endpoint security). `$1` the page's size, `$2` how many newer ones to skip, `$3` the perl prelude. Each
/// prints a JSON line per
/// session it looked at, `{"t": seconds, "v": value, "c": folder, "n": title}`, with an empty title for one with no
/// prompt (left out here, but counted, so a page of noise still has a next one). pi and Claude Code keep a JSONL file
/// a session, newest by its modification time; their strings are cut from the JSON as they are (still escaped), so
/// perl decodes nothing. Codex and OpenCode keep an SQLite index, sorted on its own index. Only reads.
enum ClosedSessions {
    /// Prints a line; a string cut inside a `\u` escape or a surrogate pair loses the part.
    static let perl = #"""
    sub cut { my $s = shift // ""; $s =~ s/\\u[0-9a-fA-F]{0,3}$//; $s =~ s/\\u[dD][89abAB][0-9a-fA-F]{2}$//; $s }
    sub row { my ($t, $v, $c, $n) = @_; $v =~ s/(["\\])/\\$1/g;
      print qq({"t":$t,"v":"$v","c":"), cut($c), qq(","n":"), cut($n), qq("}\n) }
    sub newest { my ($n, $k, @f) = @_; @f = sort { $b->[1] <=> $a->[1] } map { [$_, (stat)[9]] } @f;
      $k > $#f ? () : @f[$k .. ($k + $n - 1 > $#f ? $#f : $k + $n - 1)] }
    my $S = qr/((?:[^"\\]|\\.){0,300})/;
    """#

    static let scripts = [
        // Line 1 holds the folder; the title is the last `/name` (anywhere in the file), else the first prompt.
        "pi": #"""
        perl -e "$3"'
        for (newest(@ARGV, glob("$ENV{HOME}/.pi/agent/sessions/*/*.jsonl"))) { my ($p, $m) = @$_;
          open my $h, "<", $p; my $l = <$h> // ""; my ($c) = $l =~ /"cwd":"((?:[^"\\]|\\.)*)"/; my ($u, $s) = ("", "");
          while (<$h>) { $u = $2 if $u eq "" && /"message":\{"role":"user","content":(\[\{"type":"text","text":)?"$S/;
            $s = $1 if index($_, q({"type":"session_info")) == 0 && /"name":"$S"/ }
          row($m, $p, $c, $s ne "" ? $s : $u) }' "$1" "$2"
        """#,
        // The id is the file's name; the title the last `/rename`, else Claude Code's own, else the first typed prompt
        // (not its commands' wrappers, which start with `<`).
        "claude": #"""
        perl -e "$3"'
        for (newest(@ARGV, glob("$ENV{HOME}/.claude/projects/*/*.jsonl"))) { my ($p, $m) = @$_;
          my ($id) = $p =~ m{([^/]+)\.jsonl$}; open my $h, "<", $p; my ($c, $u, $a, $r) = ("", "", "", "");
          while (<$h>) { $c = $1 if $c eq "" && /"cwd":"((?:[^"\\]|\\.)*)"/;
            $r = $1 if /^\{"type":"custom-title","customTitle":"$S/; $a = $1 if /^\{"type":"ai-title","aiTitle":"$S/;
            $u = $2 if $u eq "" && !/"isMeta":true/
              && /"message":\{"role":"user","content":(\[\{"type":"text","text":)?"(?!<)$S/ }
          row($m, $id, $c, $r || $a || $u) }' "$1" "$2"
        """#,
        // The newest state database (its number is a schema version). Left out: subagents, `codex exec` runs and
        // empty threads. With no sqlite3, or a schema without these columns: the rollout files, whose line 1 holds the
        // id and folder, with the name from `session_index.jsonl`, else the first prompt.
        "codex": #"""
        d=$(ls -t "$HOME"/.codex/state_*.sqlite | head -n 1)
        [ -n "$d" ] && sqlite3 -readonly -cmd '.timeout 1000' "$d" "select json_object('t', recency_at_ms / 1000,
          'v', id, 'c', cwd, 'n', substr(coalesce(nullif(name, ''), nullif(title, ''), preview), 1, 300)) from threads
          where archived = 0 and source not like '{%' and source <> 'exec' and preview <> ''
          order by recency_at_ms desc limit $1 offset $2" || perl -e "$3"'
        my %name; if (open my $i, "<", "$ENV{HOME}/.codex/session_index.jsonl") { while (<$i>) {
          $name{$1} = $2 if /"id":"([^"]+)","thread_name":"$S"/ } }
        for (newest(@ARGV, glob("$ENV{HOME}/.codex/sessions/*/*/*/rollout-*.jsonl"))) { my ($p, $m) = @$_;
          open my $h, "<", $p; my $l = <$h> // "";
          my ($id) = $l =~ /"payload":\{(?:"session_id":"[^"]*",)?"id":"([^"]+)"/;
          my ($c) = $l =~ /"cwd":"((?:[^"\\]|\\.)*)"/; my $u = $name{$id // ""} // ""; my $i = 0;
          my $skip = $l =~ /"source":(\{|"exec")/;
          while ($u eq "" && ++$i < 400 && defined($_ = <$h>)) {
            $u = $1 if /"type":"user_message","message":"$S/ || /"type":"UserMessage".*?"text":"$S/ }
          row($m, $id // "", $c, $skip ? "" : $u) }' "$1" "$2"
        """#,
        // Left out: child sessions (a task's), archived ones, and OpenCode's placeholder titles (no prompt yet).
        "opencode": #"""
        command -v sqlite3 >/dev/null || { echo '{"problem":"needs sqlite3"}'; exit; }
        sqlite3 -readonly -cmd '.timeout 1000' "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db" "select
          json_object('t', time_updated / 1000, 'v', id, 'c', directory, 'n', substr(title, 1, 300)) from session
          where parent_id is null and time_archived is null and title not like 'New session - %'
          order by time_updated desc limit $1 offset $2"
        """#,
    ]

    /// The page in a script's output: `limit` lines looked at means there may be more.
    static func parse(agent: String, _ text: String, limit: Int) -> ClosedPage {
        var page = ClosedPage()
        let lines = text.split(separator: "\n")
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            page.problem = object["problem"] as? String ?? page.problem
            guard let time = object["t"] as? Double else { continue }
            page.oldest = min(page.oldest ?? .distantFuture, Date(timeIntervalSince1970: time))
            guard let value = object["v"] as? String, valid(agent, value),
                  let folder = object["c"] as? String, folder.hasPrefix("/"),
                  let title = (object["n"] as? String).flatMap(clean) else { continue }
            page.sessions.append(ClosedSession(agent: agent, value: value, title: title, folder: folder,
                                               date: Date(timeIntervalSince1970: time)))
        }
        page.looked = lines.count
        page.more = lines.count >= limit && page.problem == nil
        return page
    }

    /// One line, no control characters, at most 200 characters; nil when nothing is left.
    static func clean(_ text: String) -> String? {
        let line = text.map { $0.isNewline || $0 == "\t" ? " " : $0 }.filter { !$0.isControl }
        let clean = String(line).trimmingCharacters(in: .whitespaces).prefix(200)
        return clean.isEmpty ? nil : String(clean)
    }

    /// A value as herdr gives `agent_session`'s: pi's an absolute path, the others' letters, digits, `-` and `_` only
    /// (they go into OpenCode's SQL and Claude Code's file name, and every one into a typed line).
    static func valid(_ agent: String, _ value: String) -> Bool {
        if agent == "pi" {
            return value.hasPrefix("/")
        }
        return !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }
    }
}

public extension Exec {
    /// A page of an agent's sessions, newest first, from its own store on the machine: `limit` of them after the
    /// `offset` newest. Empty when the agent has no store there. Throws when the machine did not answer in 10 s.
    func closedSessions(agent: String, offset: Int, limit: Int = 50) async throws -> ClosedPage {
        guard let script = ClosedSessions.scripts[agent] else { return ClosedPage() }
        let text = try await output(["sh", "-c", "{ \(script)\n} 2>/dev/null", "sh", "\(limit)", "\(offset)",
                                     ClosedSessions.perl])
        return ClosedSessions.parse(agent: agent, text, limit: limit)
    }
}
