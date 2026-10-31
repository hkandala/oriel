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
    /// By hand, not a `Regex`: matching one took about 0.1 ms, and every card asks at every render (a fifth of the main
    /// thread's time in a swipe across tabs).
    public init?(_ label: String?) {
        guard let label, label.hasPrefix("oriel:") else { return nil }
        let body = label.dropFirst(6), head = body.prefix { $0 != " " }
        guard let hash = head.firstIndex(of: "#") else { return nil }
        let name = head[..<hash], iid = head[head.index(after: hash)...]
        let parts = name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        func word(_ text: Substring, _ most: Int, _ also: String) -> Bool {
            let low = { (char: Character) in char.isASCII && (char.isLowercase || char.isNumber) }
            return (1 ... most).contains(text.count) && text.first.map(low) == true
                && text.allSatisfy { low($0) || also.contains($0) }
        }
        guard word(parts[0], 64, "._-"), parts.count == 1 || word(parts[1], 32, "-"), iid.count == 6,
              word(iid, 6, "") else { return nil }
        let arg = String(body[head.endIndex...].drop { $0 == " " })
        guard arg.count <= 1024, !arg.contains(where: \.isControl) else { return nil }
        self.init(plugin: String(parts[0]), iid: String(iid), arg: arg)
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

    /// The argument as the card reads it. A folder ends in `/`: a File Explorer's root, and a Git card's, so a root
    /// that ends in a word is never read as a source. An old Files label names its root without it; an old Diff
    /// label is `<root> <source>`.
    public var place: String {
        guard !arg.hasSuffix("/") else { return arg }
        switch plugin {
        case "files": return arg + "/"
        case "diff":
            guard let space = arg.lastIndex(of: " ") else { return arg + "/" }
            return arg[..<space].hasSuffix("/") ? arg : arg[..<space] + "/" + arg[space...]
        default: return arg
        }
    }

    /// A Git card's diff source (`uncommitted` or a commit hash), from its place: `<root>/` is the home, `<root>/
    /// <source>` a diff.
    public var diffSource: String? {
        let place = place
        guard let space = place.lastIndex(of: " "), place[..<space].hasSuffix("/") else { return nil }
        return String(place[place.index(after: space)...])
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
