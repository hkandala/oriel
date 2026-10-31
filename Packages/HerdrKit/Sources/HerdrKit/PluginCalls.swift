import Foundation
import UniformTypeIdentifiers

/// A failed plugin call: the `OrielError` code the page's promise rejects with, and the text.
public struct PluginError: Error, Equatable {
    public let code: String
    public let text: String

    public init(_ code: String, _ text: String) {
        self.code = code
        self.text = text
    }

    /// A HerdrKit error as the page reads it.
    init(_ error: any Error) {
        switch error {
        case let error as PluginError: self = error
        case FileError.tooLarge: self.init("tooLarge", "The file is over 16 MB")
        case FileError.changed: self.init("changed", "The file changed on disk")
        case HerdrError.timeout: self.init("timeout", "It took too long")
        case let HerdrError.failed(text) where text.hasPrefix("Not a file") || text.contains("No such file"):
            self.init("notFound", text)
        case let HerdrError.failed(text): self.init("failed", text)
        default: self.init("failed", error.localizedDescription)
        }
    }
}

/// A plugin page's calls on its card's machine (plugins/api): files, git and run, each behind the
/// manifest's permission. Arguments and replies are JSON, as the page sends and reads them. The card's own calls (its
/// place, state, header, toast, menus) are the app's.
public struct PluginCalls: Sendable {
    public let permissions: [String]
    public let exec: any Exec
    public let remote: Bool
    /// git may run on the machine (`HostStore.gitRuns`): on This Mac, not before the developer tools are there.
    public let gitRuns: Bool

    public init(permissions: [String], exec: any Exec, remote: Bool, gitRuns: Bool) {
        (self.permissions, self.exec, self.remote, self.gitRuns) = (permissions, exec, remote, gitRuns)
    }

    /// The permission a call needs (plugins/manifest#permissions); nil for none.
    public static func permission(_ call: String) -> String? {
        switch call {
        case "files.write": "files:write"
        case "run": "run"
        case "clipboard.write": "clipboard"
        default: call.hasPrefix("files.") ? "files:read" : call.hasPrefix("git.") ? "git" : nil
        }
    }

    /// Throws `denied` when the manifest lacks the call's permission.
    public static func check(_ call: String, _ permissions: [String]) throws(PluginError) {
        if let needed = permission(call), !permissions.contains(needed) {
            throw PluginError("denied", "\(call) needs the permission \(needed)")
        }
    }

    /// The git writes, which a card runs one at a time.
    public static let gitWrites: Set = ["git.stage", "git.unstage", "git.commit", "git.fetch", "git.pull", "git.push",
                                        "git.switch"]

    /// Runs one call; its JSON reply. Throws `denied` without its permission, `failed` for a call it does not know.
    public func call(_ name: String, _ arguments: Data) async throws(PluginError) -> Data {
        try Self.check(name, permissions)
        let reply: Any?
        do {
            let args: Args
            do {
                args = try JSONDecoder().decode(Args.self, from: arguments)
            } catch {
                throw PluginError("failed", "The arguments are wrong: \(error)")
            }
            if name.hasPrefix("git.") {
                guard gitRuns else { throw PluginError("failed", "git is not installed") }
                reply = try await git(name, args)
            } else if name == "run" {
                reply = try await run(args)
            } else {
                reply = try await files(name, args)
            }
        } catch {
            throw PluginError(error)
        }
        // Keys in one order: a page that compares replies as text sees no change where there is none.
        guard let data = try? JSONSerialization.data(withJSONObject: reply ?? NSNull(),
                                                     options: [.fragmentsAllowed, .sortedKeys])
        else { throw PluginError("failed", "The reply is not JSON") }
        return data
    }

    private func files(_ name: String, _ args: Args) async throws -> Any? {
        let path = try args.path(\.path, "path")
        switch name {
        case "files.read":
            let file = try await Files.read(path, exec: exec)
            // Not `String(data:encoding:)`, which drops a byte order mark a save would not write back.
            guard let text = String(validating: file.data, as: UTF8.self) else {
                throw PluginError("notText", "The file is not UTF-8 text")
            }
            return ["text": text, "hash": file.hash, "writable": !remote || file.data.count <= Files.remoteEditLimit]
        case "files.readBytes":
            let file = try await Files.read(path, exec: exec)
            let type = UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType
            return ["base64": file.data.base64EncodedString(), "type": type ?? "application/octet-stream",
                    "hash": file.hash]
        case "files.info":
            let lines = try await exec.checkedOutput(["sh", "-c", Self.infoScript, "sh", path]).split(separator: "\n")
            let size = lines.first?.trimmingCharacters(in: .whitespaces) ?? "", folder = size == "d"
            let type = folder ? UTType.folder : UTType(filenameExtension: (path as NSString).pathExtension) ?? .data
            return ["name": (path as NSString).lastPathComponent, "size": Int(size) ?? 0, "folder": folder,
                    "kind": type.localizedDescription ?? "Document", "type": type.identifier,
                    "hash": lines.count > 1 ? String(lines[1]) : ""]
        case "files.list":
            return try await Files.list(path, repo: repo(path), exec: exec)
                .map { ["name": $0.name, "folder": $0.isFolder, "ignored": $0.ignored] }
        case "files.paths":
            return try await Files.paths(path, repo: repo(path), exec: exec)
        case "files.write":
            let data = try args.base64.flatMap { Data(base64Encoded: $0) } ?? Data(args.need(\.text, "text").utf8)
            return try await ["hash": Files.save(data, to: path, replacing: args.over, exec: exec)]
        default:
            throw PluginError("failed", "No call \(name)")
        }
    }

    /// `d` for a folder, else the size and the `cksum` (`Files.read`'s hash); fails for nothing there.
    static let infoScript = #"""
    if [ -d "$1" ]; then echo d; elif [ -e "$1" ]; then wc -c <"$1" && cksum <"$1"
    else echo "No such file" >&2; exit 1; fi
    """#

    /// The repository a folder is in, for git's letters and ignored files.
    /// ponytail: one `git rev-parse` per listing; keep the roots per card if remote listings get slow.
    private func repo(_ folder: String) async -> String? {
        gitRuns ? await Git.root(folder, exec: exec) : nil
    }

    private func git(_ name: String, _ args: Args) async throws -> Any? {
        let root = try name == "git.root" ? args.path(\.folder, "folder") : args.path(\.root, "root")
        if Self.gitWrites.contains(name) {
            let (arguments, long) = try await write(name, root, args)
            try await Git.run(root, arguments, timeout: .seconds(long ? 120 : 30), exec: exec)
            return nil
        }
        switch name {
        case "git.root": return await Git.root(root, exec: exec)
        case "git.status": return try await Git.status(root, exec: exec).map(Self.json)
        case "git.changes":
            let changes = try await Git.changes(root, exec: exec)
            return ["staged": changes.staged.map(Self.json), "unstaged": changes.unstaged.map(Self.json)]
        case "git.head":
            return await GitStatus.of(root, exec: exec).map { ["branch": $0.branch, "ahead": $0.ahead,
                                                               "behind": $0.behind] }
        case "git.branches":
            return try await Git.branches(root, exec: exec)
                .map { ["name": $0.name, "remote": $0.remote, "current": $0.current] }
        case "git.log":
            let commits = try await Git.log(root, exec: exec)
            return zip(commits, Git.graph(commits)).prefix(args.limit ?? .max).map { commit, row in
                ["hash": commit.hash, "subject": commit.subject, "author": commit.author,
                 "date": commit.date.timeIntervalSince1970 * 1000, "refs": commit.refs, "lane": row.lane,
                 "children": row.children, "parents": row.parents, "through": row.through] as [String: Any]
            }
        case "git.diff":
            let source = try args.need(\.source, "source")
            return try await Git.patch(root, commit: source == "uncommitted" ? nil : source, exec: exec)
        default: throw PluginError("failed", "No call \(name)")
        }
    }

    /// A write's git arguments, never asking for a password (`Git.run`), and whether it may take long: the network's,
    /// and a commit's hooks.
    private func write(_ name: String, _ root: String, _ args: Args) async throws -> ([String], Bool) {
        // A path, not a pattern: `*.txt` stages that file alone. `reset` also before the first commit.
        let paths = args.paths.map { ["--"] + $0 }
        switch name {
        case "git.stage": return (paths.map { ["--literal-pathspecs", "add", "-A"] + $0 } ?? ["add", "-A"], false)
        case "git.unstage": return (paths.map { ["--literal-pathspecs", "reset", "-q"] + $0 } ?? ["reset", "-q"], false)
        case "git.commit":
            let text = try args.need(\.message, "message").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw PluginError("failed", "The message is empty") }
            return (["commit", "-m", text], true)
        case "git.fetch": return (["fetch", "--all"], true)
        case "git.pull": return (["pull"], true)
        case "git.push": return (["-c", "push.autoSetupRemote=true", "push"], true)
        default:
            let branch = try args.need(\.branch, "branch")
            guard !branch.hasPrefix("-") else { throw PluginError("failed", "No branch \(branch)") }
            // A remote branch makes a local one that tracks it.
            let remote = try await Git.branches(root, exec: exec).contains { $0.remote && $0.name == branch }
            return (["switch"] + (remote ? ["--track", branch] : [branch]), true)
        }
    }

    private static func json(_ change: Git.Change) -> [String: Any] {
        var json: [String: Any] = ["letter": String(change.letter), "path": change.path]
        json["oldPath"] = change.oldPath
        return json
    }

    /// argv in `cwd`, no shell between: `sh` only changes the folder and runs it.
    /// ponytail: stdout as lines (a last line break is added, NUL bytes pass) and stderr's last 8 KB, as `Exec` gives
    /// them; a stream per call when a plugin needs bytes.
    private func run(_ args: Args) async throws -> Any? {
        guard let argv = args.argv, let first = argv.first, !first.isEmpty else {
            throw PluginError("failed", "argv is empty")
        }
        let channel = try await exec.run(["sh", "-c", #"cd "$1" || exit 127; shift; exec "$@""#, "sh",
                                          args.path(\.cwd, "cwd")] + argv)
        if let stdin = args.stdin {
            (stdin.hasSuffix("\n") ? String(stdin.dropLast()) : stdin).split(
                separator: "\n",
                omittingEmptySubsequences: false,
            )
            .forEach { channel.write(String($0)) }
        }
        channel.closeInput()
        let limit = 4 << 20, timeout = Duration.milliseconds(args.timeout ?? 30000)
        let (stdout, truncated) = try await withTimeout(timeout, onTimeout: channel.terminate) {
            var stdout = "", truncated = false
            for await line in channel.lines {
                guard stdout.utf8.count + line.utf8.count < limit else {
                    truncated = true
                    channel.terminate()
                    break
                }
                stdout += line + "\n"
            }
            return (stdout, truncated)
        }
        let (code, stderr) = await channel.exit()
        return ["code": Int(code), "stdout": stdout, "stderr": stderr, "truncated": truncated]
    }
}

/// A call's arguments, each call's own: a path is absolute (so never an option). `JSONDecoder`, not
/// `JSONSerialization`, which drops a byte order mark from a string.
private struct Args: Decodable {
    let path, folder, root, cwd: String?
    let text, base64, over, source, message, branch, stdin: String?
    let paths, argv: [String]?
    let limit, timeout: Int?

    func need(_ key: KeyPath<Self, String?>, _ name: String) throws -> String {
        guard let text = self[keyPath: key] else { throw PluginError("failed", "\(name) is missing") }
        return text
    }

    func path(_ key: KeyPath<Self, String?>, _ name: String) throws -> String {
        let path = try need(key, name)
        guard path.hasPrefix("/") else { throw PluginError("failed", "\(name) must be an absolute path") }
        return path
    }
}
