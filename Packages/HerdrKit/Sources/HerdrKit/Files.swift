import Foundation

/// A file or folder in a listing.
public struct FileEntry: Equatable, Sendable {
    public let name: String
    public let isFolder: Bool
    /// The git letter (`Change.letter`); a folder's is that of a change inside it.
    public let letter: Character?
    /// git ignores it, or the folder it is in.
    public let ignored: Bool
}

/// A file's bytes and their `cksum`, which a save checks against the disk.
public struct FileContents: Equatable, Sendable {
    public let data: Data
    public let hash: String
}

public enum FileError: Error, Equatable, Sendable {
    /// Over `Files.viewLimit`; the file's size.
    case tooLarge(Int)
    /// The file changed on disk since it was read.
    case changed
}

/// Files on a machine for the plugins, through `Exec` on This Mac and remote machines alike. The relay carries lines,
/// so names come NUL-separated and bytes as base64.
public enum Files {
    /// Bigger files show the preview's info view.
    public static let viewLimit = 16 << 20
    /// Bigger files on a remote machine open read only: a save queues the whole file on the machine's one relay.
    public static let remoteEditLimit = 4 << 20

    /// A folder's files and folders but `.git` (as VS Code), folders first, by name as the Finder sorts. `repo` is the
    /// root of the git repository the folder is in (`Git.root`), nil for none or when git cannot run: then no git runs.
    public static func list(_ folder: String, repo: String?, exec: any Exec) async throws -> [FileEntry] {
        // Links to folders are folders; a name may hold a line break.
        let script = #"""
        cd "$1" || exit
        for f in * .[!.]* ..?*; do
          if [ -d "$f" ]; then printf '%s/\0' "$f"; elif [ -e "$f" ] || [ -h "$f" ]; then printf '%s\0' "$f"; fi
        done
        """#
        async let names = exec.checkedOutput(["sh", "-c", script, "sh", folder])
        var changes: [Git.Change] = []
        var prefix = ""
        // The folder's own `-- .`: a name with `*` in it is no pattern there.
        if let repo, folder == repo || folder.hasPrefix(repo + "/") {
            changes = await Git.Change.parse((try? exec.checkedOutput(["git", "--no-optional-locks", "-C", folder,
                                                                       "status", "--porcelain=v1", "-z", "--ignored",
                                                                       "-unormal", "--", "."])) ?? "")
            prefix = folder == repo ? "" : folder.dropFirst(repo.count + 1) + "/"
        }
        // git names an untracked or ignored folder once, with a `/`, not the files in it; a link without one. Such
        // a folder may hold the whole listing.
        let all = changes.first { $0.path.hasSuffix("/") && prefix.hasPrefix($0.path) }
        let byName = Dictionary(grouping: changes.filter { $0.path.hasPrefix(prefix) }) {
            $0.path.dropFirst(prefix.count).prefix { $0 != "/" }
        }
        return try await names.split(separator: "\0").filter { $0 != ".git/" && $0 != ".git" }.map { name in
            let isFolder = name.hasSuffix("/")
            let name = String(isFolder ? name.dropLast() : name)
            let path = prefix + name
            let mine = byName[Substring(name)] ?? []
            let covering = all ?? mine.first { $0.path == path || $0.path == path + "/" }
            let inside = isFolder ? mine.first { $0.letter != "!" && $0.path.count > path.count + 1 } : nil
            let ignored = covering?.letter == "!"
            return FileEntry(name: name, isFolder: isFolder, letter: ignored ? nil : covering?.letter ?? inside?.letter,
                             ignored: ignored)
        }
        .sorted {
            $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Every file under `root`, from it, for the filter; with a `repo` (only whether there is one counts) the files git
    /// does not ignore, and tracked files deleted since.
    /// ponytail: the first 8 MB of names (about 150,000 files); a search on the machine when roots get bigger.
    public static func paths(_ root: String, repo: String?, exec: any Exec) async throws -> [String] {
        let script = #"""
        cd "$1" || exit
        if [ "$2" ]; then git ls-files -z -co --exclude-standard; else find . -name .git -prune -o -type f -print0; fi |
          head -c 8388608
        """#
        // The last name is cut short, or empty after the last NUL.
        return try await exec.checkedOutput(["sh", "-c", script, "sh", root, repo == nil ? "" : "git"],
                                            timeout: .seconds(30))
            .split(separator: "\0", omittingEmptySubsequences: false).dropLast()
            .map { String($0.hasPrefix("./") ? $0.dropFirst(2) : $0) }
    }

    /// The file's bytes, up to `viewLimit`.
    public static func read(_ path: String, exec: any Exec) async throws -> FileContents {
        // The hash first: a change between the two reads makes a save stop with `changed`, never lose it.
        let script = #"""
        [ -f "$1" ] || { echo "Not a file" >&2; exit 1; }
        s=$(wc -c <"$1") || exit
        echo $s; [ $s -le $2 ] || exit 0
        cksum <"$1" && base64 <"$1"
        """#
        let lines = try await exec.checkedOutput(["sh", "-c", script, "sh", path, String(viewLimit)],
                                                 timeout: .seconds(60)).split(separator: "\n", maxSplits: 2)
        let size = Int(lines.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        guard size <= viewLimit else { throw FileError.tooLarge(size) }
        guard lines.count >= 2,
              let data = Data(
                  base64Encoded: lines.count == 3 ? String(lines[2]) : "",
                  options: .ignoreUnknownCharacters,
              )
        else { throw HerdrError.failed("Could not read \(path)") }
        return FileContents(data: data, hash: String(lines[1]))
    }

    /// The file's size in bytes, for the info view of a file not read.
    public static func size(_ path: String, exec: any Exec) async throws -> Int {
        let text = try await exec.checkedOutput(["sh", "-c", #"wc -c <"$1""#, "sh", path])
        guard let size = Int(text.trimmingCharacters(in: .whitespaces)) else { throw HerdrError.failed(text) }
        return size
    }

    /// Writes `data` over the file at once (a new file beside it, then `mv`) if its disk hash is still `hash`; nil
    /// overwrites whatever is there. A link is written through, so it stays a link. Gives the new hash; throws
    /// `changed` and writes nothing otherwise.
    public static func save(_ data: Data, to path: String, replacing hash: String?, exec: any Exec) async throws
        -> String
    {
        let result = try await exec.checkedOutput(["sh", "-c", saveScript, "sh", path, hash ?? "", String(data.count)],
                                                  input: base64Lines(data), timeout: .seconds(60))
        guard result != "changed" else { throw FileError.changed }
        return result
    }

    /// `cp -p` gives the new file the old one's mode. The size check: a run whose stdin closed early (the connection
    /// dropped, the app quit) decodes what came and exits 0.
    static let saveScript = #"""
    t=$(mktemp "$(dirname "$1")/.oriel-save.XXXXXX") || exit
    trap 'rm -f "$t"' EXIT
    cp -p "$1" "$t" 2>/dev/null; base64 -d >"$t" || exit
    [ "$(wc -c <"$t")" -eq "$3" ] || { echo "The save was cut short" >&2; exit 1; }
    [ -z "$2" ] || [ "$(cksum <"$1")" = "$2" ] || { echo changed; exit 0; }
    cksum <"$t"
    if [ -h "$1" ]; then cat "$t" >"$1"; else mv -f "$t" "$1"; fi
    """#

    /// Yields when the file, or anything under the folder, may have changed: compare `read`'s hash to skip your own
    /// saves; list a folder's open folders again for new files and git letters. On This Mac file system events for
    /// the path, whatever file it names now; on a remote machine a check every 2 s while the stream is read.
    public static func watch(_ path: String, exec: any Exec) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        if exec is ProcessExec {
            let events = Events(path, continuation)
            continuation.onTermination = { _ in events.stop() }
        } else {
            let task = Task { await poll(path, exec: exec, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
        return stream
    }

    /// ponytail: a file's check reads it whole (up to 16 MB) every 2 s, and the caller reads it again to compare
    /// hashes; yield the hash when that costs too much. A folder's check sees its own entries, what `git status` sees
    /// under it and the changed files' text (an edit to a file already changed), not a new file in an ignored folder;
    /// its git runs without `GitStatus.usable`.
    private static func poll(_ path: String, exec: any Exec, _ changed: AsyncStream<Void>.Continuation) async {
        let script = #"""
        if [ -d "$1" ]; then
          { ls -1Ap "$1"; git --no-optional-locks -C "$1" status --porcelain=v1 -z -unormal -- . 2>/dev/null
            git -C "$1" ls-files -z -m -o --exclude-standard -- . 2>/dev/null |
              (cd "$1" && xargs -0 cat 2>/dev/null); } | cksum
        else cksum <"$1"; fi
        """#
        // Nil before the first check; then nil inside while the file is gone.
        var last: String??
        while !Task.isCancelled {
            let now = try? await exec.checkedOutput(["sh", "-c", script, "sh", path])
            if let last, last != now {
                changed.yield()
            }
            last = now
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// File system events on This Mac for a path and anything under it, whatever file it names now: a file an editor
/// replaced, or one that comes back, is still seen. The stream is on the nearest folder that exists: one made later
/// sends nothing.
private final class Events: Sendable {
    private static let queue = DispatchQueue(label: "oriel.files.watch")
    private let changed: AsyncStream<Void>.Continuation
    /// Canonical, as the events name paths (`/private/tmp`).
    private let target: String
    /// Set once in init and released once in `stop`, which the stream's end calls once.
    private nonisolated(unsafe) var stream: FSEventStreamRef?

    init(_ path: String, _ changed: AsyncStream<Void>.Continuation) {
        var root = path, isFolder: ObjCBool = false
        while root != "/",
              !(FileManager.default.fileExists(atPath: root, isDirectory: &isFolder) && isFolder.boolValue)
        {
            root = (root as NSString).deletingLastPathComponent
        }
        let canonical = (try? URL(filePath: root).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? root
        target = canonical + path.dropFirst(root.count)
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
                                           release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let events = Unmanaged<Events>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if changed.contains(where: { $0 == events.target || $0.hasPrefix(events.target + "/") }) {
                events.changed.yield()
            }
        }
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        // A second's latency: a folder lists again at most that often while a build writes.
        stream = FSEventStreamCreate(nil, callback, &context, [root] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
                                     FSEventStreamCreateFlags(flags))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, Self.queue)
            FSEventStreamStart(stream)
        }
    }

    /// On the events' queue: a callback that runs now uses `self`, which the context does not keep.
    func stop() {
        Self.queue.async { [self] in
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
