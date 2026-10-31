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
        var fields = porcelain.split(separator: "\0", omittingEmptySubsequences: true)[...]
        var staged: [Self] = [], unstaged: [Self] = []
        while let field = fields.popFirst()?.utf8, field.count > 3 {
            let index = Character(Unicode.Scalar(field[field.startIndex]))
            let tree = Character(Unicode.Scalar(field[field.index(after: field.startIndex)]))
            let path = String(decoding: field.dropFirst(3), as: UTF8.self)
            // A rename in the work tree (after `add -N`) has its old path too.
            let oldPath = [index, tree].contains(where: { $0 == "R" || $0 == "C" }) ? fields.popFirst().map(String.init)
                : nil
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
