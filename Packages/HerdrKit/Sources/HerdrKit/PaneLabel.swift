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
        guard let label, label.hasPrefix("oriel:") else { return nil }
        let head = label.dropFirst(6).prefix { $0 != " " }
        let arg = label.dropFirst(6 + head.count).drop { $0 == " " }
        let parts = head.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, let plugin = parts[0].split(separator: "/").first,
              Self.matches(plugin, first: Self.lowercase + Self.digits, rest: "._-", max: 64),
              parts[0].split(separator: "/", omittingEmptySubsequences: false).count <= 2,
              parts[1].count == 6, parts[1].allSatisfy({ Self.lowercase.contains($0) || Self.digits.contains($0) }),
              arg.count <= 1024, !arg.contains(where: \.isControl)
        else { return nil }
        self.init(plugin: String(plugin), iid: String(parts[1]), arg: String(arg))
    }

    public var text: String {
        "oriel:\(plugin)#\(iid)" + (arg.isEmpty ? "" : " \(arg)")
    }

    /// A browser pane's label.
    public static func browser(_ url: String = "", taken: Set<String>) -> PaneLabel {
        PaneLabel(plugin: "browser", iid: newIID(taken: taken), arg: url)
    }

    /// 6 random `[a-z0-9]`, not one of `taken` (the session's labels' iids).
    public static func newIID(taken: Set<String>) -> String {
        let alphabet = Array(lowercase + digits)
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

    private static let lowercase = "abcdefghijklmnopqrstuvwxyz", digits = "0123456789"

    private static func matches(_ text: Substring, first: String, rest: String, max: Int) -> Bool {
        guard let head = text.first, first.contains(head), text.count <= max else { return false }
        return text.dropFirst().allSatisfy { first.contains($0) || rest.contains($0) }
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
        guard let channel = try? await run(["sh", "-c", script, "sh", path]) else { return }
        channel.write(line)
        channel.closeInput()
        _ = await channel.exit()
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
