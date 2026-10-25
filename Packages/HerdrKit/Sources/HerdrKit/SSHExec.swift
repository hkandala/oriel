#if os(macOS)
    import CryptoKit
    import Foundation

    /// Runs commands on a remote machine through its one ControlMaster, with the system `ssh`: the user's config,
    /// agent and keys work unchanged (machines#macos). A run starts the master when none lives, never with a prompt;
    /// only `connect(ask:)` may ask.
    public actor SSHExec: Exec {
        /// What ssh asks (a host key, a password, a code), answered by the user; nil cancels.
        public typealias Ask = @Sendable (String) async -> String?

        /// As the user types it in a terminal: `host`, `user@host`, a `~/.ssh/config` alias.
        nonisolated let target: String
        /// This Mac's login-shell environment: the user's agent and PATH for ssh.
        nonisolated let environment: [String: String]
        nonisolated let socket: String
        /// The master's pid while it lives: a check costs a `kill(pid, 0)`, not a process.
        /// ponytail: a reused pid reads as a live master until a run fails; `-O check` per run if that bites.
        private var mux: pid_t?
        private var starting: Task<Void, Error>?
        /// ssh wants an answer: no start without one until `connect` (machines#health-check).
        private var blocked: HerdrError?
        /// A start that failed for another reason (no network, host down) waits until `retry.at`, backing off.
        private var retry: (at: ContinuousClock.Instant, error: Error)?
        private var failures = 0
        /// herdr's path from the machine's login shell, asked once per master; a nil is asked again after 30 s.
        private var lookup: (task: Task<String?, Never>, at: ContinuousClock.Instant)?

        public init(target: String, local: ProcessExec) {
            self.target = target
            environment = local.environment
            let hash = SHA256.hash(data: Data(target.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
            socket = Self.folder + "/" + hash
        }

        /// A target the user may add: ssh would read a leading `-` as an option, and argv takes no spaces.
        public static func isValidTarget(_ target: String) -> Bool {
            !target.isEmpty && !target.hasPrefix("-") && !target.contains(where: \.isWhitespace)
        }

        public func run(_ argv: [String]) async throws -> Channel {
            try await up(nil)
            // Without a master these fail at once instead of opening their own connection and prompting again, and
            // they send none of the user's configured forwards (machines#macos).
            return try ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-o", "ControlMaster=no", "-o",
                                          "BatchMode=yes", "-o", "ProxyCommand=/usr/bin/false", "-S", socket,
                                          target, "--", Self.envelope(argv)], environment)
        }

        public func herdr() async throws -> String? {
            try await up(nil)
            if let lookup {
                let path = await lookup.task.value
                if path != nil || ContinuousClock.now - lookup.at < .seconds(30) {
                    return path
                }
            }
            let task = Task { await findHerdr() }
            lookup = (task, .now)
            return await task.value
        }

        /// Starts the master if none lives, asking the user what ssh asks: the Connect button and a new machine.
        public func connect(ask: @escaping Ask) async throws {
            try await up(ask)
        }

        /// Ends the master (the app quits); a run after it starts a new one.
        public nonisolated func disconnect() {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/ssh")
            process.arguments = ["-F", "/dev/null", "-S", socket, "-O", "exit", target]
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }

        /// One start at a time; the others wait for it and use its master.
        private func up(_ ask: Ask?) async throws {
            while let starting {
                _ = try? await starting.value
            }
            if let mux, kill(mux, 0) == 0 {
                return
            }
            if ask == nil {
                if let blocked {
                    throw blocked
                }
                if let retry, ContinuousClock.now < retry.at {
                    throw retry.error
                }
            }
            let task = Task {
                defer { starting = nil }
                try await start(ask)
            }
            starting = task
            try await task.value
        }

        /// Starts the master and waits until it serves (`-f`: ssh goes to the background once authenticated). Without
        /// `ask`, BatchMode: a host that needs an answer fails at once and blocks.
        private func start(_ ask: Ask?) async throws {
            // One that outlived an app that crashed is still good.
            mux = await pid()
            if mux != nil {
                return started()
            }
            // A master killed hard leaves its socket, and a new one does not bind over it.
            unlink(socket)
            // Forwarding off: a machine cannot reach the Mac's agent or ports through the long-lived connection.
            // ssh's keepalive ends a dead link's master within 15 s; the next run starts a new one.
            var argv = ["sh", "-c", #"exec "$@" 2>&1"#, "sh", "/usr/bin/ssh", "-M", "-N", "-f",
                        "-o", "ControlPersist=10m", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3",
                        "-o", "ConnectTimeout=10", "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
                        "-o", "ClearAllForwardings=yes"]
            var environment = environment
            if ask == nil {
                argv += ["-o", "BatchMode=yes"]
            } else {
                // ssh runs the helper with its own stdin and stderr: the question comes out on our pipe, the answer
                // goes in through ssh's stdin. Never stored.
                environment["SSH_ASKPASS"] = Self.askpass
                environment["SSH_ASKPASS_REQUIRE"] = "force"
            }
            let channel = try ProcessExec.spawn(argv + ["-S", socket, target], environment)
            var said: [String] = []
            for await line in channel.lines.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                if line.hasPrefix(Self.question), let ask {
                    let prompt = Data(base64Encoded: String(line.dropFirst(Self.question.count)))
                        .map { String(decoding: $0, as: UTF8.self) } ?? ""
                    guard let answer = await ask(prompt) else {
                        channel.terminate()
                        let error = HerdrError.disconnected("Canceled")
                        blocked = error
                        throw error
                    }
                    channel.write(answer)
                } else if !line.isEmpty {
                    said.append(line)
                }
            }
            channel.closeInput()
            let (status, _) = await channel.exit()
            guard status == 0 else { throw failed(status, said.joined(separator: "\n")) }
            mux = await pid()
            guard mux != nil else { throw failed(0, "The SSH connection did not start") }
            started()
        }

        /// A new master: herdr's path is asked again (it may be installed since).
        private func started() {
            blocked = nil
            retry = nil
            failures = 0
            lookup = nil
        }

        /// A start that failed: one that needs an answer blocks, any other backs off (2, 4 … 30 s).
        private func failed(_ status: Int32, _ text: String) -> HerdrError {
            let needsAnswer = ["Permission denied", "Host key verification failed", "passphrase",
                               "IDENTIFICATION HAS CHANGED"].contains { text.contains($0) }
            if needsAnswer {
                blocked = .disconnected(text)
                return .disconnected(text)
            }
            failures += 1
            let error = HerdrError.failed(text.isEmpty ? "ssh exited \(status)" : text)
            retry = (.now + .seconds(min(1 << min(failures, 5), 30)), error)
            return error
        }

        /// The master's pid, from "Master running (pid=123)".
        private func pid() async -> pid_t? {
            guard let check = try? ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-S", socket, "-O", "check",
                                                      target], environment)
            else { return nil }
            check.closeInput()
            let reply = await check.exit().stderr
            return reply.split(separator: "pid=").last.flatMap { pid_t($0.prefix { $0.isNumber }) }
        }

        /// The last absolute path the login shell prints after our marker (an rc file may print first).
        private func findHerdr() async -> String? {
            let marker = "oriel-herdr"
            let shell = #"exec "${SHELL:-sh}" -lic "$0" </dev/null 2>/dev/null"#
            guard let text = try? await output(["sh", "-c", shell, "echo \(marker); command -v herdr"])
            else { return nil }
            let path = text.components(separatedBy: marker).last?
                .split(separator: "\n").last.map(String.init) ?? ""
            return path.hasPrefix("/") ? path : nil
        }

        /// The remote command envelope (talking-to-herdr#run-and-dial): the machine's login shell may be bash, zsh or
        /// fish, so it gets only base64, which every shell passes through; `sh` decodes and runs the quoted argv.
        static func envelope(_ argv: [String]) -> String {
            let command = argv.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
                .joined(separator: " ")
            return #"sh -c 'eval "$(printf %s "$1" | base64 -d)"' sh "# + Data(command.utf8).base64EncodedString()
        }

        private static let question = "oriel-askpass "

        /// The sockets' folder: per user, 0700, no spaces; a socket path stays under the 104-byte limit.
        static let folder: String = {
            let path = URL.cachesDirectory.appending(path: "oriel").path(percentEncoded: false)
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            return path
        }()

        /// The askpass helper, written at launch beside the sockets. A `none` prompt (a security key's touch) only
        /// informs: it gets no question.
        static let askpass: String = {
            let path = folder + "/askpass"
            let script = """
            #!/bin/sh
            [ "$SSH_ASKPASS_PROMPT" = none ] && exit 0
            printf '\(question)%s\\n' "$(printf %s "$1" | base64 | tr -d '\\n')" >&2
            IFS= read -r answer || exit 1
            printf '%s\\n' "$answer"

            """
            FileManager.default.createFile(atPath: path, contents: Data(script.utf8),
                                           attributes: [.posixPermissions: 0o700])
            return path
        }()
    }
#endif
