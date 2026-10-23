import Foundation
import Synchronization

/// Runs argv on a machine. The one seam for This Mac, remote machines and iOS.
public protocol Exec: Sendable {
    func run(_ argv: [String]) async throws -> Channel
    /// herdr's absolute path on the machine, from its login shell; nil when it has none. Asked again at most every
    /// 30 s while missing or gone, so a herdr installed or moved since is found
    /// (talking-to-herdr#herdr-on-each-machine).
    func herdr() async -> String?
}

public struct Channel: Sendable {
    /// Stdout, one element per line. Ends when the command closes stdout.
    public let lines: AsyncStream<String>
    /// Writes one line to stdin, in order, without blocking the caller.
    public let write: @Sendable (String) -> Void
    /// Every long-running command the app starts exits when its stdin closes (design T6).
    public let closeInput: @Sendable () -> Void
    /// Stops reading now and kills the command if it still runs.
    public let terminate: @Sendable () -> Void
    /// Waits for the command to end and gives back its exit status and the last 8 KB of stderr.
    public let exit: @Sendable () async -> (status: Int32, stderr: String)
}

#if os(macOS)
    /// Runs commands on This Mac with the user's login-shell environment.
    /// ponytail: This Mac only, so no SSH prefix and no base64 envelope; remote machines add them.
    public final class ProcessExec: Exec {
        let environment: [String: String]
        private let lookup: Mutex<Lookup>
        private struct Lookup {
            var path: String?
            var asked: ContinuousClock.Instant
        }

        /// Reads the login shell once (herdr again while it has none); keep one instance for the app's life.
        public convenience init() async {
            // A write to a child that already exited must fail, not kill the app.
            signal(SIGPIPE, SIG_IGN)
            var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
            let (found, herdr) = await Self.loginShell(env)
            env.merge(found.filter { Self.isUserKey($0.key) }) { $1 }
            self.init(env, herdr: herdr, asked: .now)
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
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        lines.yield(String(decoding: buffer[..<newline], as: UTF8.self))
                        buffer.removeSubrange(...newline)
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

        private static func spawn(_ argv: [String], _ environment: [String: String]) throws -> Channel {
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
#endif
