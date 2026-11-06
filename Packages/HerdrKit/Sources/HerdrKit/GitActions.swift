import Foundation

/// The Git card's reads and writes beyond `Git.swift`'s: the changes as the index keeps them, the branches, and the
/// commands its buttons run.
public extension Git {
    /// The changes in two lists: staged (the index against HEAD) and unstaged (the work tree against the index,
    /// untracked files included). A file can be in both. A conflict is unstaged only.
    static func changes(_ root: String, exec: any Exec) async throws
        -> (staged: [Change], unstaged: [Change])
    {
        try await Change.split(exec.checkedOutput(["git", "--no-optional-locks", "-C", root, "status",
                                                   "--porcelain=v1", "-z", "--untracked-files=all"]))
    }

    /// A branch to switch to.
    struct Branch: Equatable, Sendable {
        /// `main`, or `origin/main` for a remote one.
        public let name: String
        public let remote: Bool
        public let current: Bool
    }

    /// The local branches, then the remote ones that have no local branch of their name (a switch to one makes it).
    static func branches(_ root: String, exec: any Exec) async throws -> [Branch] {
        let lines = try await exec.checkedOutput(["git", "-C", root, "for-each-ref", "--format=%(HEAD)%(refname)",
                                                  "refs/heads", "refs/remotes"]).split(separator: "\n")
        let local = lines.compactMap { line in
            line.dropFirst().hasPrefix("refs/heads/") ? Branch(name: String(line.dropFirst(12)), remote: false,
                                                               current: line.first == "*") : nil
        }
        let names = Set(local.map(\.name))
        let remote = lines.compactMap { line -> Branch? in
            guard line.dropFirst().hasPrefix("refs/remotes/") else { return nil }
            let name = String(line.dropFirst(14))
            // `origin/HEAD` names another one.
            guard !name.hasSuffix("/HEAD"), let slash = name.firstIndex(of: "/"),
                  !names.contains(String(name[name.index(after: slash)...])) else { return nil }
            return Branch(name: name, remote: true, current: false)
        }
        return local + remote
    }

    /// Puts the paths (literal, from the root) back as HEAD has them, in the index and the work tree: the tracked
    /// ones restored (`git restore`, which knows no untracked path), then the untracked ones deleted (`git clean`,
    /// which leaves ignored files), so a failed restore deletes nothing. With a tracked path it fails before the first
    /// commit: there is no HEAD to go back to.
    /// ponytail: the paths go in argv, twice; thousands of them (an unignored `node_modules`) can pass the argument
    /// limit, then `--pathspec-from-file=-` on stdin.
    static func revert(_ root: String, _ paths: [String], exec: any Exec) async throws {
        let untracked = try await run(root, ["--literal-pathspecs", "ls-files", "-z", "--others", "--exclude-standard",
                                             "--"] + paths, timeout: .seconds(30), exec: exec)
            .split(separator: "\0").map(String.init)
        let gone = Set(untracked), tracked = paths.filter { !gone.contains($0) }
        if !tracked.isEmpty {
            try await run(root, ["--literal-pathspecs", "restore", "--staged", "--worktree", "--source=HEAD", "--"]
                + tracked, timeout: .seconds(30), exec: exec)
        }
        if !untracked.isEmpty {
            try await run(root, ["--literal-pathspecs", "clean", "-fq", "--"] + untracked, timeout: .seconds(30),
                          exec: exec)
        }
    }

    /// Fetch, Pull and Push: the Git card's buttons and a workspace's menu.
    enum Sync: String, Sendable {
        case fetch, pull, push

        /// Fetch from every remote; Push sets the upstream of a branch that has none.
        public var arguments: [String] {
            switch self {
            case .fetch: ["fetch", "--all"]
            case .pull: ["pull"]
            case .push: ["-c", "push.autoSetupRemote=true", "push"]
            }
        }
    }

    /// `git <arguments>` in the repository, for a button: git never asks for a password (it fails instead), and
    /// git's own message is the error. Its output.
    @discardableResult
    static func run(_ root: String, _ arguments: [String], timeout: Duration = .seconds(120),
                    exec: any Exec) async throws -> String
    {
        try await exec.checkedOutput(["env", "GIT_TERMINAL_PROMPT=0", "git", "-C", root] + arguments,
                                     timeout: timeout)
    }
}

extension Git.Change {
    /// From `git status --porcelain=v1 -z`: the index's letter for the staged list, the work tree's for the other.
    static func split(_ porcelain: String) -> (staged: [Self], unstaged: [Self]) {
        var staged: [Self] = [], unstaged: [Self] = []
        for entry in entries(porcelain) {
            let (index, tree, path, oldPath) = (entry.index, entry.tree, entry.path, entry.oldPath)
            switch (index, tree) {
            case ("?", "?"): unstaged.append(Self(letter: "U", path: path, oldPath: nil))
            case ("!", "!"): continue
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"):
                unstaged.append(Self(letter: "C", path: path, oldPath: nil))
            default:
                if index != " " {
                    staged.append(Self(letter: index == "C" ? "A" : index, path: path, oldPath: oldPath))
                }
                if tree != " " {
                    unstaged.append(Self(letter: tree, path: path, oldPath: nil))
                }
            }
        }
        return (staged, unstaged)
    }
}
