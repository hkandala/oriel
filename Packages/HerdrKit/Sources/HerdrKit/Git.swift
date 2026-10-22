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

    /// The checkout's status, or nil when the folder is not in a repository (git exits nonzero) or git takes
    /// more than 5 s. `git` is found in the login shell's PATH, like herdr. No untracked scan: the rows show no
    /// file counts. No optional locks: a run every 10 s must not leave `index.lock` in the user's way.
    static func of(_ root: String, exec: any Exec) async -> GitStatus? {
        guard let channel = try? await exec.run([
            "git",
            "--no-optional-locks",
            "-C",
            root,
            "status",
            "--porcelain=v2",
            "--branch",
            "--untracked-files=no",
        ]) else { return nil }
        channel.closeInput()
        let text = try? await withTimeout(.seconds(5), onTimeout: channel.terminate) {
            await channel.lines.reduce("") { $0 + $1 + "\n" }
        }
        guard let text, await channel.exit().status == 0 else { return nil }
        return GitStatus(porcelain: text)
    }

    /// Whether git can run without macOS offering to install the developer tools: `/usr/bin/git` is a stub that
    /// opens that dialog when `xcode-select -p` finds none. Asked once at launch.
    static func usable(exec: any Exec) async -> Bool {
        let run = { (argv: [String]) async -> (status: Int32, out: String) in
            guard let channel = try? await exec.run(argv) else { return (-1, "") }
            channel.closeInput()
            let out = await channel.lines.reduce("") { $0 + $1 }
            return await (channel.exit().status, out)
        }
        let git = await run(["sh", "-c", "command -v git"])
        guard git.status == 0, !git.out.isEmpty else { return false }
        if git.out != "/usr/bin/git" {
            return true
        }
        return await run(["xcode-select", "-p"]).status == 0
    }
}
