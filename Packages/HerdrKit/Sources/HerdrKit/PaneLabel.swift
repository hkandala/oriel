import Foundation

/// A plugin pane's herdr label (future-work/plugins/labels): `oriel:<plugin>[/<pane>]#<iid>[ <arg>]`. The label marks
/// the pane: it survives moves and herdr restarts, and every device sees it.
public struct PaneLabel: Equatable, Sendable {
    public let plugin: String
    public let iid: String
    /// What the pane shows: a browser's typed address. Empty when none.
    public let arg: String

    public init(plugin: String, iid: String, arg: String = "") {
        self.plugin = plugin
        self.iid = iid
        self.arg = arg
    }

    /// Nil for a user's own label (`todo: fix login`) or one that breaks the grammar.
    public init?(_ label: String?) {
        // Most labels are a user's: no regex for them (every card asks at every render).
        guard let label, label.hasPrefix("oriel:") else { return nil }
        let grammar = /oriel:([a-z0-9][a-z0-9._-]{0,63})(?:\/[a-z0-9][a-z0-9-]{0,31})?#([a-z0-9]{6})(?: +(.*))?/
        guard let match = try? grammar.wholeMatch(in: label) else { return nil }
        let arg = match.3.map(String.init) ?? ""
        guard arg.count <= 1024, !arg.contains(where: \.isControl) else { return nil }
        self.init(plugin: String(match.1), iid: String(match.2), arg: arg)
    }

    public var text: String {
        "oriel:\(plugin)#\(iid)" + (arg.isEmpty ? "" : " \(arg)")
    }

    /// 6 random `[a-z0-9]`, not one of `taken` (the session's labels' iids).
    public static func newIID(taken: Set<String>) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        while true {
            let iid = String((0 ..< 6).map { _ in alphabet.randomElement() ?? "a" })
            if !taken.contains(iid) {
                return iid
            }
        }
    }

    /// The instance state file, relative to the home folder (future-work/plugins/state).
    public func statePath(session: String) -> String {
        ".local/state/oriel/\(session)/\(plugin)/\(iid).json"
    }
}

extension Character {
    var isControl: Bool {
        unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public extension Exec {
    /// A file under the home folder, or nil when it is missing or unreadable.
    func read(home path: String) async -> String? {
        let text = try? await output(["sh", "-c", #"cat "$HOME/$1" 2>/dev/null"#, "sh", path], timeout: .seconds(5))
        return text?.isEmpty == false ? text : nil
    }

    /// Writes one line atomically, each writer through its own temporary file; last writer wins. Only the user can read
    /// it.
    func write(home path: String, _ line: String) async {
        let script = #"umask 077; f="$HOME/$1"; mkdir -p "${f%/*}" && cat >"$f.$$" && mv "$f.$$" "$f""#
        await succeeds(script, [path], input: [line])
    }

    /// Once on connect: the session's state files untouched for 30 days (every write refreshes a file's age).
    func pruneState(session: String) async {
        _ = try? await output([
            "sh",
            "-c",
            #"find "$HOME/.local/state/oriel/$1" -type f -mtime +30 -delete 2>/dev/null"#,
            "sh",
            session,
        ])
    }

    func remove(home path: String) async {
        _ = try? await output(["sh", "-c", #"rm -f "$HOME/$1""#, "sh", path])
    }
}
