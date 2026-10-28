/// A TCP port that listens on a machine's loopback, for a browser card's ports chip
/// (ui/browser#finding-ports), with the herdr session and workspace of its process when the machine lets the
/// user read its environment.
public struct Listener: Hashable, Sendable {
    public let port: Int
    /// The process's name; empty for another user's.
    public let command: String
    public let session: String
    public let workspace: String
}

public extension Exec {
    /// One run: `ss` (Linux), else `lsof` (macOS); each listener's `HERDR_SESSION` and `HERDR_WORKSPACE_ID` from
    /// `/proc/<pid>/environ`, else `ps -E`. By port, each once.
    func listeners() async throws -> [Listener] {
        try await output(["sh", "-c", Self.listenersScript]).split(separator: "\n").compactMap { line in
            // The output's end is trimmed, and with it the last line's empty fields.
            let field = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) + ["", "", ""]
            guard let port = Int(field[0]) else { return nil }
            return Listener(port: port, command: field[3], session: field[1], workspace: field[2])
        }
    }

    /// Prints `port \t session \t workspace \t command` for listeners a page on the machine's `localhost` reaches
    /// (any address, or loopback).
    static var listenersScript: String {
        #"""
        l=$({ if command -v ss >/dev/null 2>&1; then
            ss -ltnp 2>/dev/null | awk '$1 == "LISTEN" { a = $4; sub(/:[0-9]+$/, "", a); pid = ""; c = ""
              if (match($0, /"[^"]*",pid=[0-9]+/)) {
                split(substr($0, RSTART + 1, RLENGTH - 1), b, "\",pid="); c = b[1]; pid = b[2]
              }
              print a "\t" substr($4, length(a) + 2) "\t" pid "\t" c }'
          else
            lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null | awk '/^p/ { pid = substr($0, 2) }
              /^c/ { c = substr($0, 2) }
              /^n/ { a = substr($0, 2); sub(/:[0-9]+$/, "", a)
                print a "\t" substr($0, length(a) + 3) "\t" pid "\t" c }'
          fi; } | awk -F '\t' '{ a = $1; sub(/%.*/, "", a) }
          a ~ /^(\*|0\.0\.0\.0|\[::\]|127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\])$/ && !seen[$2]++ {
            print $2 "\t" $3 "\t" $4 }')
        p=$(printf '%s\n' "$l" | cut -f 2 | grep . | sort -u)
        { if [ -d /proc ]; then
            for i in $p; do tr '\0' '\n' <"/proc/$i/environ" 2>/dev/null | sed "s/^/$i /"; done
          elif [ -n "$p" ]; then
            ps -E -ww -o pid=,command= -p "$(echo $p | tr ' ' ,)" 2>/dev/null |
              awk '{ for (i = 2; i <= NF; i++) print $1, $i }'
          fi
          echo oriel-listeners; printf '%s\n' "$l"
        } | awk -F '\t' '!d { if ($0 == "oriel-listeners") d = 1; i = index($0, " "); k = substr($0, i + 1)
            n = substr($0, 1, i - 1)
            if (k ~ /^HERDR_SESSION=/) s[n] = substr(k, 15)
            if (k ~ /^HERDR_WORKSPACE_ID=/) w[n] = substr(k, 20)
            next }
          $1 != "" { print $1 "\t" s[$2] "\t" w[$2] "\t" $3 }'
        """#
    }
}
