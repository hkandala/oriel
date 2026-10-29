import Foundation
import Synchronization

/// Runs argv on a machine. The one seam for This Mac and remote machines.
public protocol Exec: Sendable {
    func run(_ argv: [String]) async throws -> Channel
    /// herdr's absolute path on the machine, from its login shell; nil when it has none. Asked again at most every
    /// 30 s while missing or gone, so a herdr installed or moved since is found
    /// (talking-to-herdr#herdr-on-each-machine). Throws when the machine cannot be reached.
    func herdr() async throws -> String?
}

extension Exec {
    /// A command's whole stdout, trimmed; past `timeout` the command is killed and this throws.
    func output(_ argv: [String], timeout: Duration = .seconds(10)) async throws -> String {
        let channel = try await run(argv)
        channel.closeInput()
        return try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.reduce(into: "") { $0 += $1 + "\n" }
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A command's stdout, its lines joined by "\n" (NUL bytes kept), with `input` on its stdin, a line per write.
    /// Throws the command's stderr when it exits non-zero; past `timeout` the command is killed.
    func checkedOutput(_ argv: [String], input: [String] = [],
                       timeout: Duration = .seconds(10)) async throws -> String
    {
        let channel = try await run(argv)
        input.forEach(channel.write)
        channel.closeInput()
        let output = try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.reduce(into: []) { $0.append($1) }.joined(separator: "\n")
        }
        let (status, stderr) = await channel.exit()
        guard status == 0 else {
            let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrError.failed(text.isEmpty ? "\(argv[0]) failed (\(status))" : text)
        }
        return output
    }

    /// Runs `sh -c script` with the arguments and `input` on its stdin, a line per write: true when it exits 0.
    @discardableResult
    public func succeeds(_ script: String, _ arguments: [String], input: [String] = []) async -> Bool {
        guard let channel = try? await run(["sh", "-c", script, "sh"] + arguments) else { return false }
        input.forEach(channel.write)
        channel.closeInput()
        return await channel.exit().status == 0
    }

    /// Copies the file to a new folder of its own in `oriel-drops-<uid>` in the machine's temporary folder and gives
    /// back its path there, as herdr's remote client does with a dropped image (`herdr-clipboard-images-<uid>`): the
    /// folder is the user's alone (0700), and each copy removes the folders older than a day. The bytes go as base64
    /// lines, which the relay's line protocol carries.
    /// ponytail: the whole file is queued on the machine's one relay at once, ahead of its panes' streams and keys, so
    /// files over 16 MB (herdr's limit for a dropped image) are refused; stream it with backpressure if bigger files
    /// are needed.
    public func upload(_ file: URL) async throws -> String {
        let name = file.lastPathComponent
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw HerdrError.failed("\(name) is not a file") }
        guard values.fileSize ?? 0 <= 16 << 20 else { throw HerdrError.failed("\(name) is over 16 MB") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let channel = try await run(["sh", "-c", Self.uploadScript, "sh", name])
        // Whole groups of 3 bytes: no padding inside the stream.
        while let chunk = try handle.read(upToCount: 49152), !chunk.isEmpty {
            channel.write(chunk.base64EncodedString())
        }
        channel.closeInput()
        let folder = await channel.lines.reduce("") { $1 }
        let (status, stderr) = await channel.exit()
        guard status == 0, folder.hasPrefix("/") else {
            let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrError.failed(text.isEmpty ? "Copying \(name) failed (\(status))" : text)
        }
        return folder + "/" + name
    }

    /// Prints only the new folder, whose name holds no line break (a file's may): the path is put together here. The
    /// shared folder must be the user's own, not a link another user made.
    static var uploadScript: String {
        #"""
        umask 077; r=${TMPDIR:-/tmp}; r=${r%/}/oriel-drops-$(id -u)
        mkdir -p "$r" && [ ! -h "$r" ] && [ -O "$r" ] && chmod 700 "$r" || exit 1
        find "$r" -mindepth 1 -maxdepth 1 -mtime +0 -exec rm -rf {} + 2>/dev/null
        d=$(mktemp -d "$r/XXXXXXXX") && base64 -d >"$d/$1" && echo "$d"
        """#
    }
}

public struct Channel: Sendable {
    /// Stdout, one element per line. Ends when the command closes stdout.
    public let lines: AsyncStream<String>
    /// Writes one line to stdin, in order, without blocking the caller.
    public let write: @Sendable (String) -> Void
    /// Every long-running command the app starts exits when its stdin closes (talking-to-herdr, Running commands).
    public let closeInput: @Sendable () -> Void
    /// Stops reading now and kills the command if it still runs.
    public let terminate: @Sendable () -> Void
    /// Waits for the command to end and gives back its exit status and the last 8 KB of stderr.
    public let exit: @Sendable () async -> (status: Int32, stderr: String)
}

/// Runs commands on This Mac with the user's login-shell environment.
public final class ProcessExec: Exec {
    let environment: [String: String]
    private let lookup: Mutex<Lookup>
    private struct Lookup {
        var path: String?
        var asked: ContinuousClock.Instant
    }

    /// Reads the login shell once (herdr again while it has none); keep one instance for the app's life.
    public convenience init() async {
        Self.prepare()
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
        let (found, herdr) = await Self.loginShell(env)
        env.merge(found.filter { Self.isUserKey($0.key) }) { $1 }
        self.init(env, herdr: herdr, asked: .now)
    }

    static func prepare() {
        // A write to a child that already exited must fail, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        // A GUI app's soft limit is 256 fds; the first snapshot asks every pane at once, three pipes per run.
        var files = rlimit()
        if getrlimit(RLIMIT_NOFILE, &files) == 0, files.rlim_cur < rlim_t(OPEN_MAX) {
            files.rlim_cur = min(files.rlim_max, rlim_t(OPEN_MAX))
            setrlimit(RLIMIT_NOFILE, &files)
        }
    }

    init(_ environment: [String: String], herdr: String?, asked: ContinuousClock.Instant) {
        self.environment = environment
        lookup = Mutex(Lookup(path: herdr, asked: asked))
    }

    public func run(_ argv: [String]) async throws -> Channel {
        try Self.spawn(argv, environment)
    }

    public func herdr() async -> String? {
        if let path = lookup.withLock({ $0.path }), FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Missing or gone since: ask again at most every 30 s (it runs the user's rc files); nil in between.
        // `asked` is set as the run starts, and the 3 s shell timeout keeps the run inside the window, so one
        // runs at a time.
        let ask = lookup.withLock {
            guard ContinuousClock.now - $0.asked >= .seconds(30) else { return false }
            $0.asked = .now
            return true
        }
        guard ask else { return nil }
        let path = await Self.loginShell(environment).herdr
        lookup.withLock { $0 = Lookup(path: path, asked: .now) }
        return path
    }

    /// A GUI app does not get the shell's environment, so ask the login shell, in one run, for its
    /// variables and for herdr.
    static func loginShell(_ env: [String: String]) async -> (vars: [String: String], herdr: String?) {
        let marker = "oriel-env-\(UUID().uuidString)"
        guard let channel = try? spawn(
            [env["SHELL"] ?? "/bin/zsh", "-lic",
             "echo \(marker); /usr/bin/env; echo \(marker); command -v herdr; echo \(marker)"],
            env,
        ) else { return ([:], nil) }
        // Closed stdin reads like /dev/null.
        channel.closeInput()
        return await (try? withTimeout(.seconds(3), onTimeout: channel.terminate) {
            var vars: [String: String] = [:]
            var herdr: String?
            var seen = 0
            // Stop at the last marker: a process the shell started may keep stdout open.
            for await line in channel.lines {
                if line.hasSuffix(marker) { // an rc file may print without a final newline
                    seen += 1
                    if seen == 3 {
                        break
                    }
                } else if seen == 1, let equals = line.firstIndex(of: "=") {
                    vars[String(line[..<equals])] = String(line[line.index(after: equals)...])
                } else if seen == 2 {
                    // The last line: a hook may print first. An alias or function is not a path.
                    herdr = line.hasPrefix("/") ? line : nil
                }
            }
            return (vars, herdr)
        }) ?? ([:], nil)
    }

    /// The keys taken from the login shell and given to This Mac's server. The rest of the app's environment
    /// (`__CFBundleIdentifier`, `XPC_*`, `DYLD_*`) must not reach a pane (design D47).
    static func isUserKey(_ key: String) -> Bool {
        ["PATH", "HOME", "SSH_AUTH_SOCK"].contains(key) || key.hasPrefix("XDG_")
    }

    /// A pipe's output until EOF. Not `FileHandle.bytes`: with several pipes open at once it
    /// stalls (seen on macOS 27 with a second bridge run while the events stream is open).
    private static func chunks(_ handle: FileHandle) -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        // The handler holds the handle until EOF or until the reader stops: once a fast child's Process
        // and Pipe are released, nothing else does, and EOF never arrived (seen on CI as a 10 s timeout
        // after `sh -c` exited).
        handle.readabilityHandler = { _ in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        continuation.onTermination = { _ in handle.readabilityHandler = nil }
        return stream
    }

    private static func split(_ handle: FileHandle,
                              into lines: AsyncStream<String>.Continuation) -> Task<Void, Never>
    {
        let output = chunks(handle)
        return Task {
            var buffer = Data()
            for await data in output {
                // Only the new bytes: a scan from the start for each chunk made a 280 KB snapshot line cost
                // O(n²), the app's top function in a stress profile.
                var from = buffer.endIndex
                buffer.append(data)
                while let newline = buffer[from...].firstIndex(of: UInt8(ascii: "\n")) {
                    lines.yield(String(decoding: buffer[..<newline], as: UTF8.self))
                    buffer.removeSubrange(...newline)
                    from = buffer.startIndex
                }
            }
            if !buffer.isEmpty {
                lines.yield(String(decoding: buffer, as: UTF8.self))
            }
            lines.finish()
        }
    }

    /// The end of a pipe's output as text. Only the tail: long-lived streams may log for hours.
    private static func tail(_ handle: FileHandle) -> Task<String, Never> {
        let output = chunks(handle)
        return Task {
            var data = Data()
            for await chunk in output {
                data = (data + chunk).suffix(8192)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func spawn(_ argv: [String], _ environment: [String: String]) throws -> Channel {
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = argv
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let (ended, endedContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = {
            endedContinuation.yield($0.terminationStatus)
            endedContinuation.finish()
        }
        try process.run()
        let pid = process.processIdentifier

        let (lines, linesContinuation) = AsyncStream<String>.makeStream()
        let reader = split(stdout.fileHandleForReading, into: linesContinuation)
        let errors = tail(stderr.fileHandleForReading)
        // Running until reaped: after that, its pid may belong to another process.
        let kill: @Sendable () -> Void = {
            if process.isRunning {
                Darwin.kill(pid, SIGKILL)
            }
        }
        // Ends the stream too, so a reader never waits on a child that ignores the signal, and stops
        // both pipe readers, so a grandchild that keeps a pipe open cannot keep them alive.
        let terminate: @Sendable () -> Void = {
            kill()
            linesContinuation.finish()
            reader.cancel()
            errors.cancel()
        }
        // A dropped stream terminates; one that ended at EOF leaves stderr to finish for `exit`.
        linesContinuation.onTermination = { reason in
            if case .cancelled = reason {
                terminate()
            } else {
                kill()
            }
        }
        let status = Task { await ended.first { _ in true } ?? -1 }
        let input = stdin.fileHandleForWriting
        // A full pipe blocks this queue, never the caller (keystrokes come from the main actor).
        let writes = DispatchQueue(label: "oriel.exec.stdin")
        return Channel(
            lines: lines,
            write: { line in writes.async { try? input.write(contentsOf: Data((line + "\n").utf8)) } },
            closeInput: { writes.async { try? input.close() } },
            terminate: terminate,
            exit: { await (status.value, errors.value) },
        )
    }
}
