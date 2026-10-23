import Foundation

#if os(macOS)
    public extension HerdrClient {
        /// Starts this session's server as a one-shot launchd job, so launchd, not the app, is its parent
        /// and responsible process (design D47), and waits until it answers. No KeepAlive: once
        /// `herdr session stop` ends it, launchd keeps the job loaded but never runs it again. False when it
        /// already ran.
        /// ponytail: This Mac only; remote machines start herdr over SSH.
        @discardableResult
        nonisolated func startServer(within timeout: Duration) async throws -> Bool {
            // The name goes into a launchd label and file paths.
            guard Session.isValidName(session) else { throw HerdrError.failed("“\(session)” is not a session name") }
            // Already up (started elsewhere since): booting out its job would stop it. No or old herdr: say so.
            do {
                _ = try await snapshot()
                return false
            } catch {
                switch error {
                case HerdrError.notFound, HerdrError.unsupported: throw error
                default: break
                }
            }
            // The CLI's user keys, so the server and the CLI agree on paths (XDG_CONFIG_HOME moves herdr's
            // sessions).
            var environment: [String: String] = [:]
            for entry in try await Self.output(exec, ["env", "-0"]).split(separator: "\0") {
                let pair = entry.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2, ProcessExec.isUserKey(pair[0]) {
                    environment[pair[0]] = pair[1]
                }
            }
            let label = "dev.hkandala.oriel.herdr.\(session)"
            let domain = "gui/\(getuid())"
            let plist = FileManager.default.temporaryDirectory.appending(path: "\(label).plist")
            let logs = URL.libraryDirectory.appending(path: "Logs/Oriel")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appending(path: "\(session).log").path
            // Interactive: launchd's default throttles the CPU and I/O of the server and every agent in it.
            let job: [String: Any] = try await ["Label": label,
                                                "ProgramArguments": [herdr(), "--session", session, "server"],
                                                "EnvironmentVariables": environment, "RunAtLoad": true,
                                                "ProcessType": "Interactive", "StandardErrorPath": log]
            try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: plist)
            defer { try? FileManager.default.removeItem(at: plist) }
            // The job of a server that stopped since is still loaded, and a label loads only once.
            _ = try? await Self.output(exec, ["launchctl", "bootout", "\(domain)/\(label)"])
            let channel = try await exec.run(["launchctl", "bootstrap", domain, plist.path])
            channel.closeInput()
            let (status, stderr) = await channel.exit()
            guard status == 0 else {
                throw HerdrError.failed("launchctl bootstrap exited \(status): \(stderr)")
            }
            // No check at all with no time (e2e's start failure): the job still starts, so Retry finds it running.
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if await (try? snapshot()) != nil {
                    return true
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw HerdrError.failed("The server did not answer within \(timeout.components.seconds) s; see \(log)")
        }
    }
#endif
