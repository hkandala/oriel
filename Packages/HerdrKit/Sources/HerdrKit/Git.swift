import Foundation

/// A checkout's branch and how far it is from its upstream (design D67).
public struct GitStatus: Equatable, Sendable {
    public let branch: String
    public let ahead: Int
    public let behind: Int
}

public extension GitStatus {
    /// From `git status --porcelain=v2 --branch`: `# branch.head` (the short commit when detached) and
    /// `# branch.ab +A -B` (absent without an upstream). Nil without a head line.
    init?(porcelain: String) {
        var head: String?, oid = "", ahead = 0, behind = 0
        for line in porcelain.split(separator: "\n") {
            let words = line.split(separator: " ")
            guard words.count >= 3, words[0] == "#" else { continue }
            switch words[1] {
            case "branch.head": head = String(words[2])
            case "branch.oid": oid = String(words[2])
            case "branch.ab" where words.count >= 4:
                ahead = Int(words[2].dropFirst()) ?? 0
                behind = Int(words[3].dropFirst()) ?? 0
            default: break
            }
        }
        guard let head else { return nil }
        branch = head == "(detached)" ? String(oid.prefix(7)) : head
        self.ahead = ahead
        self.behind = behind
    }

    /// The checkout's status, or nil when the folder is not in a repository (no output) or git takes more than 5 s.
    /// `git` is found in the login shell's PATH, like herdr. No untracked scan: the rows show no
    /// file counts. No optional locks: a run every 10 s must not leave `index.lock` in the user's way.
    static func of(_ root: String, exec: any Exec) async -> GitStatus? {
        let argv = ["git", "--no-optional-locks", "-C", root, "status", "--porcelain=v2", "--branch",
                    "--untracked-files=no"]
        return await (try? exec.output(argv, timeout: .seconds(5))).flatMap(GitStatus.init(porcelain:))
    }

    /// Whether git can run without macOS offering to install the developer tools: on a Mac `/usr/bin/git` is a stub
    /// that opens that dialog when `xcode-select -p` finds none. Asked once at launch.
    static func usable(exec: any Exec) async -> Bool {
        await exec.succeeds(#"""
        g=$(command -v git) &&
          { [ "$g" != /usr/bin/git ] || [ "$(uname)" != Darwin ] || xcode-select -p; } >/dev/null 2>&1
        """#, [])
    }
}

/// A repository's data for the Files and Diff plugins, through `Exec` on This Mac and remote machines alike. Callers
/// check `GitStatus.usable` first: on a Mac without the developer tools, any git run opens the install dialog.
public enum Git {
    /// The repository's root folder, or nil when `folder` is in none.
    public static func root(_ folder: String, exec: any Exec) async -> String? {
        let root = await (try? exec.output(["git", "-C", folder, "rev-parse", "--show-toplevel"],
                                           timeout: .seconds(5))) ?? ""
        return root.isEmpty ? nil : root
    }

    /// The changed files, each untracked file on its own.
    public static func status(_ root: String, exec: any Exec) async throws -> [Change] {
        try await Change.parse(exec.checkedOutput(["git", "--no-optional-locks", "-C", root, "status",
                                                   "--porcelain=v1", "-z", "--untracked-files=all"]))
    }

    /// The last 500 commits of every branch, tag and remote branch, newest first, each child before its parents.
    /// ponytail: 500 rows; a Show More row when a longer history must show.
    public static func log(_ root: String, exec: any Exec) async throws -> [Commit] {
        try await exec.checkedOutput(["git", "-C", root, "log", "--all", "-n", "500", "--topo-order",
                                      "--no-show-signature", "--decorate=full",
                                      "--format=%H%x1f%P%x1f%an%x1f%at%x1f%D%x1f%s"], timeout: .seconds(30))
            .split(separator: "\n").compactMap(Commit.init)
    }
}

public extension Git {
    /// A file in `git status`.
    struct Change: Equatable, Sendable {
        /// `M`, `A` (also a copy), `D`, `R`, `T`, `U` (untracked), `C` (conflict), or `!` (ignored).
        public let letter: Character
        /// From the repository's root; a folder's ends in `/`.
        public let path: String
        /// The path before a rename.
        public let oldPath: String?
    }

    /// A commit in the history graph.
    struct Commit: Equatable, Sendable {
        public let hash: String
        public let parents: [String]
        public let author: String
        public let date: Date
        public let subject: String
        /// The names on it, as `%D` prints them with `--decorate=full`: `HEAD -> refs/heads/main`, `HEAD` when
        /// detached, `refs/heads/…`, `refs/remotes/…`, `tag: refs/tags/…`.
        public var refs: [String] = []
    }

    /// One commit's row of the history graph. Lanes are columns, 0 on the left; a lane keeps its column while its
    /// line runs, so a line that passes a row is straight.
    struct GraphRow: Equatable, Sendable {
        /// The commit's dot.
        public let lane: Int
        /// The lanes whose lines come from the row's top into the dot.
        public let children: [Int]
        /// The lanes the dot's lines go to at the row's bottom.
        public let parents: [Int]
        /// The lanes that pass the row from top to bottom.
        public let through: [Int]
    }
}

extension Git.Change {
    /// From `git status --porcelain=v1 -z`: `XY path`, and a rename's old path as the next field.
    static func parse(_ porcelain: String) -> [Self] {
        var fields = porcelain.split(separator: "\0", omittingEmptySubsequences: true)[...]
        var changes: [Self] = []
        // By bytes: a path may start with a combining character.
        while let field = fields.popFirst()?.utf8, field.count > 3 {
            let index = Character(Unicode.Scalar(field[field.startIndex]))
            let tree = Character(Unicode.Scalar(field[field.index(after: field.startIndex)]))
            let oldPath = index == "R" || index == "C" ? fields.popFirst().map(String.init) : nil
            changes.append(Self(letter: letter(index, tree), path: String(decoding: field.dropFirst(3), as: UTF8.self),
                                oldPath: oldPath))
        }
        return changes
    }

    /// From the index's and the work tree's letters.
    private static func letter(_ index: Character, _ tree: Character) -> Character {
        switch (index, tree) {
        case ("?", "?"): "U"
        case ("!", "!"): "!"
        case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): "C"
        case ("C", _): "A" // a copy
        case ("A", _), ("R", _), (_, " "): index
        default: tree
        }
    }
}

extension Git.Commit {
    /// One line of `git log --format=%H%x1f%P%x1f%an%x1f%at%x1f%D%x1f%s`.
    init?(_ line: Substring) {
        let fields = line.split(separator: "\u{1F}", maxSplits: 5, omittingEmptySubsequences: false)
        guard fields.count == 6, let time = TimeInterval(fields[3]) else { return nil }
        self.init(hash: String(fields[0]), parents: fields[1].split(separator: " ").map(String.init),
                  author: String(fields[2]), date: Date(timeIntervalSince1970: time), subject: String(fields[5]),
                  refs: fields[4].split(separator: ", ").map(String.init))
    }
}

public extension Git {
    /// The graph's rows for `log`'s commits, in order.
    static func graph(_ commits: [Commit]) -> [GraphRow] {
        // Each lane waits for the commit it runs to; nil is a free column.
        var lanes: [String?] = []
        return commits.map { commit in
            let children = lanes.indices.filter { lanes[$0] == commit.hash }
            let lane = children.first ?? lanes.firstIndex(of: nil) ?? lanes.endIndex
            if lane == lanes.endIndex {
                lanes.append(nil)
            }
            children.forEach { lanes[$0] = nil }
            let through = lanes.indices.filter { lanes[$0] != nil }
            var parents: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                // The first parent keeps the dot's lane, also when another lane waits for it: their lines meet at
                // its dot, in the left one, as in `git log --graph`. Another parent joins a lane that waits for it.
                let next = index == 0 ? lane : lanes.firstIndex(of: parent) ?? lanes.firstIndex(of: nil) ?? lanes
                    .endIndex
                if next == lanes.endIndex {
                    lanes.append(parent)
                } else {
                    lanes[next] = parent
                }
                parents.append(next)
            }
            while lanes.last == .some(nil) {
                lanes.removeLast()
            }
            return GraphRow(lane: lane, children: children, parents: parents, through: through)
        }
    }
}
