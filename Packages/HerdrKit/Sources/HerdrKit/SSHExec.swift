import CryptoKit
import Foundation
import Network

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
    /// The master's pid while it lives: a check costs a `kill(pid, 0)`, not a process. A reused pid reads as a live
    /// master until its relay is needed again and does not start (`currentRelay`).
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
    /// The machine's browser proxy while its cards use it (`openProxy`).
    private var proxy: (front: SOCKSFront, users: Int)?
    /// ssh's `-D` port and the master it is on: a new master forwards it again.
    private var dynamic: (port: UInt16, pid: pid_t)?
    private var forwarding: Task<UInt16, Error>?

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
        // `exec`: the run's pid is the command's own on every `sh`, so a kill reaches it.
        return try await currentRelay().run("exec " + Self.quoted(argv))
    }

    /// The live relay, started on first use. One that does not start (no Perl, a login slower than 10 s) is tried
    /// again by the next run.
    private func currentRelay() async throws -> Relay {
        if let relay, relay.alive {
            return relay
        }
        // Runs during a start wait for it, and fail with it: a slow or Perl-less host gets one session, not one per
        // run.
        if let relayStart {
            guard let started = await relayStart.value else { throw Self.noRelay(target) }
            return started
        }
        let task = Task { () -> Relay? in
            guard let channel = try? session(["perl", "-e", Relay.script]) else { return nil }
            return await Relay.start(channel)
        }
        relayStart = task
        let started = await task.value
        if relayStart == task {
            relayStart = nil
        }
        relay = started
        guard let started else {
            // A master gone with its pid reused, or with its socket deleted, serves no session: the next run
            // starts a new one.
            if await pid() != connection {
                connection = nil
                throw HerdrError.failed("The SSH connection to \(target) closed")
            }
            throw Self.noRelay(target)
        }
        return started
    }

    private static func noRelay(_ target: String) -> HerdrError {
        .failed("Oriel needs Perl on \(target): its relay did not start")
    }

    /// One SSH session on the master that runs the command. Without a master it fails at once instead of opening
    /// its own connection and prompting again, and it sends none of the user's configured forwards
    /// (machines#macos).
    private func session(_ argv: [String]) throws -> Channel {
        try ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-o", "ControlMaster=no", "-o", "BatchMode=yes",
                               "-o", "ProxyCommand=/usr/bin/false", "-S", socket, "--", target,
                               Self.envelope(argv)], environment)
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

    /// Ends the master (the app quits); a run after it starts a new one. No wait: a stopped (SIGSTOP) master never
    /// answers, and the quit must not hang on it; the `ssh -O exit` outlives the app.
    public nonisolated func disconnect() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ssh")
        process.arguments = ["-F", "/dev/null", "-S", socket, "-O", "exit", "--", target]
        process.standardError = FileHandle.nullDevice
        try? process.run()
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
        // ssh's keepalive ends a dead link's master within 15 s; the next run starts a new one. LogLevel=ERROR:
        // a failure shows ssh's own error, not the server's login banner or ssh's notices (both INFO).
        var argv = ["sh", "-c", #"exec "$@" 2>&1"#, "sh", "/usr/bin/ssh", "-M", "-N", "-f",
                    "-o", "ControlPersist=10m", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3",
                    "-o", "ConnectTimeout=10", "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
                    "-o", "ClearAllForwardings=yes", "-o", "LogLevel=ERROR"]
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
        // key under BatchMode) must not hold every run. One that asks has no limit: the user answers.
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
                // One line: the rest of a multi-line paste would answer ssh's next question.
                channel.write(String(answer.prefix { !$0.isNewline }))
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
        // LogLevel=ERROR also hides ssh's "Connection closed by …" (INFO): no text says only that.
        let error = HerdrError
            .failed(text.isEmpty ? "The connection to \(target) closed (ssh exited \(status))" : text)
        retry = (.now + .seconds(min(1 << min(failures, 5), 30)), error)
        return error
    }

    /// The master's pid, from "Master running (pid=123)".
    private func pid() async -> pid_t? {
        await control(["-O", "check"])?.stderr.split(separator: "pid=").last
            .flatMap { pid_t($0.prefix { $0.isNumber }) }
    }

    /// An `ssh -O` command to the master; nil when it did not answer within 5 s (a master stopped with SIGSTOP never
    /// does).
    private func control(_ command: [String]) async -> (status: Int32, stderr: String)? {
        guard let channel = try? ProcessExec.spawn(["/usr/bin/ssh", "-F", "/dev/null", "-S", socket] + command
            + ["--", target], environment)
        else { return nil }
        channel.closeInput()
        return try? await withTimeout(.seconds(5), onTimeout: channel.terminate) { await channel.exit() }
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

    /// The askpass helper, written beside the sockets on the first connect that may ask. A `none` prompt (a
    /// security key's touch) only informs: it gets no question.
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

/// The browser's proxy.
extension SSHExec {
    /// The local port of the machine's SOCKS proxy for its browser cards (future-work/web-page#remote-localhost),
    /// started by the first card; each call is balanced by a `closeProxy`. The proxy forwards through ssh's `-D` on
    /// the master, started with the first page connection and again on each new master. No password prompt: a
    /// machine that needs one fails the page until Connect.
    public func openProxy() async throws -> NWEndpoint.Port {
        if proxy == nil {
            let front = try await SOCKSFront.start { [weak self] in
                guard let self else { throw HerdrError.disconnected("Closed") }
                return try await dynamicPort()
            }
            // Another card's start may have won meanwhile.
            if proxy == nil {
                proxy = (front, 0)
            } else {
                front.stop()
            }
        }
        proxy?.users += 1
        return proxy?.front.port ?? .any
    }

    /// The machine's last browser card went: the proxy and ssh's `-D` end.
    public func closeProxy() async {
        guard let proxy else { return }
        guard proxy.users <= 1 else {
            self.proxy?.users -= 1
            return
        }
        self.proxy = nil
        proxy.front.stop()
        await cancelForward()
    }

    private func cancelForward() async {
        guard let dynamic, dynamic.pid == connection else { return }
        self.dynamic = nil
        _ = await control(["-O", "cancel", "-D", "127.0.0.1:\(dynamic.port)"])
    }

    /// ssh's `-D` port on the live master, forwarded once per master (one at a time).
    private func dynamicPort() async throws -> UInt16 {
        try await up(nil)
        if let dynamic, dynamic.pid == connection {
            return dynamic.port
        }
        if let forwarding {
            return try await forwarding.value
        }
        let task = Task { try await forward() }
        forwarding = task
        defer {
            if forwarding == task {
                forwarding = nil
            }
        }
        return try await task.value
    }

    /// A port ssh found taken meanwhile is tried again with another.
    private func forward() async throws -> UInt16 {
        for _ in 0 ..< 3 {
            guard let pid = connection, let port = SOCKSFront.freePort() else { break }
            guard await control(["-O", "forward", "-D", "127.0.0.1:\(port)"])?.status == 0 else { continue }
            dynamic = (port, pid)
            // The last card went while ssh forwarded.
            if proxy == nil {
                await cancelForward()
            }
            return port
        }
        throw HerdrError.failed("ssh did not forward a port to \(target)")
    }
}
