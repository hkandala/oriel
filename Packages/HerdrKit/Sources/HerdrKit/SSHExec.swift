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
        private var connection: pid_t?
        private var starting: Task<Void, Error>?
        /// ssh wants an answer: no start without one until `connect` (machines#health-check).
        private var blocked: HerdrError?
        /// A start that failed for another reason (no network, host down) waits until `retry.at`, backing off.
        private var retry: (at: ContinuousClock.Instant, error: Error)?
        private var failures = 0
        /// herdr's path from the machine's login shell, asked once per master; a nil is asked again after 30 s.
        private var lookup: (task: Task<String?, Error>, at: ContinuousClock.Instant)?
        /// The one SSH session every run goes through (`Relay`), started by the first run on a master.
        private var relay: Relay?
        private var relayStart: Task<Relay?, Never>?
        /// The machine has no Perl: each run takes its own SSH session until the next master.
        private var noRelay = false
        /// Without a relay: the sessions open on the master, and runs waiting for one. sshd allows 10 per connection by
        /// default (`MaxSessions`) and refuses the 11th.
        /// ponytail: a fixed 10 that long-lived streams hold too, and a run that waits 10 s fails (the page shows
        /// Reconnecting, not a freeze).
        private var channels = 0
        private var waiting: [(id: UUID, go: CheckedContinuation<Bool, Never>)] = []

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
            if let relay = await currentRelay() {
                return try relay.run(Self.quoted(argv))
            }
            if channels < 10 {
                channels += 1
            } else {
                // A closing channel hands its place over.
                let id = UUID()
                let timer = Task {
                    try? await Task.sleep(for: .seconds(10))
                    waiting.first { $0.id == id }?.go.resume(returning: false)
                    waiting.removeAll { $0.id == id }
                }
                let got = await withCheckedContinuation { waiting.append((id, $0)) }
                timer.cancel()
                guard got else { throw HerdrError.failed("All 10 SSH sessions to \(target) are in use") }
            }
            let channel: Channel
            do {
                channel = try session(argv)
            } catch {
                closed()
                throw error
            }
            Task {
                _ = await channel.exit()
                closed()
            }
            return channel
        }

        /// The live relay, started on first use; nil while the machine has none.
        private func currentRelay() async -> Relay? {
            if let relay, relay.alive {
                return relay
            }
            if noRelay {
                return nil
            }
            if let relayStart {
                return await relayStart.value
            }
            let task = Task { () -> Relay? in
                guard let channel = try? session(["perl", "-e", Relay.script]) else { return nil }
                return await Relay.start(channel)
            }
            relayStart = task
            let started = await task.value
            relayStart = nil
            relay = started
            noRelay = started == nil
            return started
        }

        /// One SSH session on the master that runs the command. Without a master it fails at once instead of opening
        /// its own connection and prompting again, and it sends none of the user's configured forwards
        /// (machines#macos).
        private func session(_ argv: [String]) throws -> Channel {
            try ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-o", "ControlMaster=no", "-o", "BatchMode=yes",
                                   "-o", "ProxyCommand=/usr/bin/false", "-S", socket, "--", target,
                                   Self.envelope(argv)], environment)
        }

        private func closed() {
            if waiting.isEmpty {
                channels -= 1
            } else {
                waiting.removeFirst().go.resume(returning: true)
            }
        }

        public func herdr() async throws -> String? {
            try await up(nil)
            // A run that failed is no answer: it is asked again at once.
            do {
                if let lookup {
                    let path = try await lookup.task.value
                    if path != nil || ContinuousClock.now - lookup.at < .seconds(30) {
                        return path
                    }
                }
                let task = Task { try await findHerdr() }
                lookup = (task, .now)
                return try await task.value
            } catch {
                lookup = nil
                throw error
            }
        }

        /// Starts the master if none lives, asking the user what ssh asks: the Connect button and a new machine.
        public func connect(ask: @escaping Ask) async throws {
            try await up(ask)
        }

        /// Ends the master (the app quits); a run after it starts a new one.
        public nonisolated func disconnect() {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/ssh")
            process.arguments = ["-F", "/dev/null", "-S", socket, "-O", "exit", "--", target]
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }

        /// One start at a time; the others wait for it and use its master.
        private func up(_ ask: Ask?) async throws {
            while let starting {
                _ = try? await starting.value
            }
            if let connection, kill(connection, 0) == 0 {
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
            connection = nil
            // A master killed hard leaves its socket, and a new one does not bind over it. One that outlived an app
            // that crashed is not used: it may still hold that app's sessions (sshd allows 10); it ends by itself
            // 10 min after its last one.
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
            let channel = try ProcessExec.spawn(argv + ["-S", socket, "--", target], environment)
            // ConnectTimeout covers only the TCP connect and the banner: a login that hangs (a jump host, a security
            // key
            // under BatchMode) must not hold every run. One that asks has no limit: the user answers.
            let began = ContinuousClock.now
            let limit = ask == nil ? Task {
                try await Task.sleep(for: .seconds(30))
                channel.terminate()
            } : nil
            defer { limit?.cancel() }
            var said: [String] = []
            for await line in channel.lines.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                if line.hasPrefix(Self.question), let ask {
                    let prompt = Data(base64Encoded: String(line.dropFirst(Self.question.count)))
                        .map { String(decoding: $0, as: UTF8.self) } ?? ""
                    guard let answer = await ask(prompt) else {
                        channel.closeInput()
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
            guard status == 0 else {
                throw failed(status, ContinuousClock.now - began >= .seconds(30) ? "ssh did not connect within 30 s"
                    : said.joined(separator: "\n"))
            }
            connection = await pid()
            guard connection != nil else { throw failed(0, "The SSH connection did not start") }
            started()
        }

        /// A new master: herdr's path is asked again (it may be installed since).
        private func started() {
            blocked = nil
            retry = nil
            failures = 0
            lookup = nil
            relay = nil
            noRelay = false
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
                                                      "--", target], environment)
            else { return nil }
            check.closeInput()
            // A master that is stopped (SIGSTOP) never answers.
            guard let reply = try? await withTimeout(
                .seconds(5),
                onTimeout: check.terminate,
                { await check.exit().stderr },
            )
            else { return nil }
            return reply.split(separator: "pid=").last.flatMap { pid_t($0.prefix { $0.isNumber }) }
        }

        /// The last absolute path the login shell prints after our marker (an rc file may print first).
        private func findHerdr() async throws -> String? {
            let marker = "oriel-herdr"
            let shell = #"exec "${SHELL:-sh}" -lic "$0" </dev/null 2>/dev/null"#
            let text = try await output(["sh", "-c", shell, "echo \(marker); command -v herdr"])
            let path = text.components(separatedBy: marker).last?
                .split(separator: "\n").last.map(String.init) ?? ""
            return path.hasPrefix("/") ? path : nil
        }
    }

    extension SSHExec {
        /// The remote command envelope (talking-to-herdr#run-and-dial): the machine's login shell may be bash, zsh or
        /// fish, so it gets only base64, which every shell passes through; `sh` decodes and runs the quoted argv.
        static func envelope(_ argv: [String]) -> String {
            #"sh -c 'eval "$(printf %s "$1" | base64 -d)"' sh "# + Data(quoted(argv).utf8).base64EncodedString()
        }

        /// The argv as one POSIX `sh` command, every element single-quoted.
        static func quoted(_ argv: [String]) -> String {
            argv.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }.joined(separator: " ")
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
