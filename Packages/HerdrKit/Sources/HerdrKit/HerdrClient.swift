import Foundation

/// The oldest herdr release this kit works with.
let herdrVersion = "0.9.3"

public enum HerdrError: Error, Equatable, Sendable {
    /// No herdr binary on the machine.
    case notFound
    /// herdr is too old.
    case unsupported(String)
    /// herdr did not answer within the request's timeout.
    case timeout
    /// herdr answered with an error.
    case herdr(code: String, message: String)
    /// The command failed or printed something we cannot read.
    case failed(String)
    /// ssh needs an answer (a password, a code, a host key) to reach the machine; ssh's text. Only the user's
    /// Connect asks again.
    case disconnected(String)
    /// herdr changed nothing, for this reason (`same_tab`, `cross_tab`, `zoomed_tab`).
    case refused(String)
}

extension HerdrError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound: "herdr is not installed"
        case let .unsupported(message), let .failed(message), let .disconnected(message): message
        case .timeout: "herdr did not answer"
        case let .herdr(code, message): "\(message) (\(code))"
        case .refused("zoomed_tab"): "The tab is zoomed in herdr"
        case let .refused(reason): "herdr changed nothing (\(reason))"
        }
    }
}

/// What `Multiplexer.updates()` delivers.
public enum Update: Sendable {
    case snapshot(Snapshot)
    case error(HerdrError)
}

/// Talks to one herdr session: requests over `remote-api-bridge`, one events stream, paced snapshots. herdr runs
/// by the absolute path its machine's login shell gives (`Exec.herdr()`).
public actor HerdrClient {
    nonisolated let session: String
    nonisolated let exec: any Exec
    nonisolated let timeout: Duration

    private var out: AsyncStream<Update>.Continuation?
    /// When the last good snapshot was read; nil since the start or the last failure.
    private var lastRead: ContinuousClock.Instant?
    private var reading = false
    private var readAgain = false
    private var heartbeat: Task<Void, Never>?
    private var events: Task<Void, Never>?
    /// Agent panes of the open events stream; nil when no stream is open.
    private var subscribed: [String]?

    /// `timeout` bounds each request.
    public init(session: String, exec: any Exec, timeout: Duration = .seconds(10)) {
        self.session = session
        self.exec = exec
        self.timeout = timeout
    }

    // MARK: Requests

    /// Sends one request through a new `remote-api-bridge` run and decodes its `result`.
    nonisolated func call<Result: Decodable & Sendable>(
        _ method: String,
        _ params: [String: any Sendable] = [:],
    ) async throws -> Result {
        guard let line = jsonLine(["id": "1", "method": method, "params": params]) else {
            throw HerdrError.failed("\(method): params are not JSON")
        }
        let channel = try await exec.run([herdr(), "--session", session, "remote-api-bridge"])
        channel.write(line)
        let reply = try await withTimeout(timeout, onTimeout: channel.terminate) {
            await channel.lines.first { _ in true }
        }
        channel.closeInput()
        guard let reply else {
            let (status, stderr) = await channel.exit()
            throw HerdrError.failed("herdr exited \(status): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let decoded = try decode(Reply<Result>.self, reply)
        if let error = decoded.error {
            throw HerdrError.herdr(code: error.code, message: error.message)
        }
        guard let result = decoded.result else { throw HerdrError.failed("\(method): no result") }
        return result
    }

    public nonisolated func sessions() async throws -> [Session] {
        let list = try await exec.output([herdr(), "--session", session, "session", "list", "--json"])
        return try decode(SessionList.self, list).sessions
    }

    /// `herdr session stop` or `delete` of this session; herdr's reason when it refuses. Bounded by `timeout`, as a
    /// request is.
    nonisolated func session(_ command: String) async throws {
        let channel = try await exec.run([herdr(), "--session", session, "session", command, session, "--json"])
        channel.closeInput()
        try await withTimeout(timeout, onTimeout: channel.terminate) {
            for await _ in channel.lines {}
        }
        let (status, stderr) = await channel.exit()
        guard status != 0 else { return }
        let error = try? JSONDecoder().decode(Reply<String>.self, from: Data(stderr.utf8)).error
        throw error.map { HerdrError.herdr(code: $0.code, message: $0.message) }
            ?? HerdrError.failed("herdr session \(command) exited \(status)")
    }

    public nonisolated func pane(_ paneID: String) async throws -> Pane {
        try await (call("pane.get", ["pane_id": paneID]) as PaneResult).pane
    }

    public nonisolated func program(_ paneID: String) async throws -> Program? {
        try await (call("pane.process_info", ["pane_id": paneID]) as ProcessInfoResult).processInfo.program
    }

    /// Throws `.unsupported` when herdr is too old.
    public nonisolated func snapshot() async throws -> Snapshot {
        var snapshot = try await (call("session.snapshot") as SnapshotResult).snapshot
        // Leading digits per part, so 0.9.4-rc1 counts as 0.9.4.
        let numbers = { (version: String) in
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        if let version = snapshot.version, numbers(version).lexicographicallyPrecedes(numbers(herdrVersion)) {
            throw HerdrError.unsupported("herdr \(version) is too old; \(herdrVersion) or newer needed")
        }
        for layout in snapshot.layouts {
            if let tree = SplitNode(layout) {
                snapshot.trees[layout.tabID] = tree
            } else {
                let export: ExportResult = try await call("layout.export", ["tab_id": layout.tabID])
                snapshot.trees[layout.tabID] = export.layout.root
            }
        }
        return snapshot
    }

    // MARK: Updates

    /// Paced as design T4 says; a precondition holds it to one call.
    public func updates() -> AsyncStream<Update> {
        precondition(out == nil, "updates() is called once per client")
        let (stream, out) = AsyncStream<Update>.makeStream()
        self.out = out
        out.onTermination = { _ in Task { await self.stop() } }
        heartbeat = Task { await self.beat() }
        return stream
    }

    /// Design T4.
    public func refresh() {
        guard out != nil else { return }
        if reading {
            readAgain = true
            return
        }
        reading = true
        Task { [self] in
            repeat {
                readAgain = false
                let started = ContinuousClock.now
                do {
                    let snapshot = try await snapshot()
                    lastRead = .now
                    out?.yield(.snapshot(snapshot))
                    let agentPanes = snapshot.agents.map(\.paneID).sorted()
                    if out != nil, agentPanes != subscribed {
                        subscribe(agentPanes)
                    }
                } catch {
                    // Too old too: the heartbeat finds herdr again once it is updated.
                    lastRead = nil
                    out?.yield(.error(error as? HerdrError ?? .failed("\(error)")))
                }
                // Events during the read: the next one starts `spacing` after this one did, so a hundred agents'
                // titles and states (an event each) are not reads back to back, each a 400 KB snapshot (phase 29).
                if readAgain {
                    try? await Task.sleep(until: started + Self.spacing)
                }
            } while readAgain && out != nil
            reading = false
        }
    }

    /// The least time from one read's start to the next one's while events keep coming.
    static let spacing = Duration.milliseconds(250)

    private func stop() {
        out = nil
        heartbeat?.cancel()
        events?.cancel()
    }

    /// (Re)opens the one events stream. Every line on it means "read the snapshot again".
    private func subscribe(_ agentPanes: [String]) {
        events?.cancel()
        subscribed = agentPanes
        let types = [
            "workspace.created", "workspace.updated", "workspace.metadata_updated", "workspace.renamed",
            "workspace.moved", "workspace.reordered", "workspace.closed",
            "tab.created", "tab.closed", "tab.renamed", "tab.moved",
            "pane.created", "pane.closed", "pane.moved", "pane.exited", "pane.agent_detected",
            // herdr sends it on a terminal title change; a title can pick a pane's icon.
            "pane.updated", "layout.updated",
        ]
        // No *.focused: the app ignores herdr's focus. Each agent entry makes herdr poll that pane
        // every 100 ms, so plain shells are left out.
        let subscriptions = types.map { ["type": $0] }
            + agentPanes.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        let params = ["subscriptions": subscriptions]
        // Only strings: serializing cannot fail.
        let request = jsonLine(["id": "events", "method": "events.subscribe", "params": params]) ?? ""
        events = Task { [self] in
            do {
                let channel = try await exec.run([herdr(), "--session", session, "remote-api-bridge"])
                channel.write(request)
                for await line in channel.lines {
                    let message = try? JSONDecoder().decode(EventLine.self, from: Data(line.utf8))
                    // events_lost, pane_not_found: start over.
                    if message?.error != nil {
                        break
                    }
                    // Every other line, the first too (subscription_started: catch up on what came before it).
                    refresh()
                }
                channel.terminate()
            } catch {}
            // The stream ended on its own: wait a little, then a fresh snapshot opens it again.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            subscribed = nil
            refresh()
        }
    }

    /// The one health check (design T3): a snapshot read now and every 30 s, every 2 s while reads fail. It also
    /// catches events the stream missed, and finds a stopped session again once it answers.
    private func beat() async {
        repeat {
            // A 2 s tick, so a read that fails mid-wait (the session stopped) is retried soon.
            if lastRead.map({ ContinuousClock.now - $0 >= .seconds(30) }) ?? true {
                refresh()
            }
        } while await (try? Task.sleep(for: .seconds(2))) != nil
    }

    nonisolated func herdr() async throws -> String {
        guard let path = try await exec.herdr() else { throw HerdrError.notFound }
        return path
    }
}

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: Data(text.utf8))
    } catch {
        throw HerdrError.failed("unreadable reply from herdr: \(error)")
    }
}

struct Reply<Result: Decodable>: Decodable {
    let result: Result?
    let error: ReplyError?
}

struct ReplyError: Decodable {
    let code: String
    let message: String
}

private struct EventLine: Decodable {
    let error: ReplyError?
}

private struct SessionList: Decodable {
    let sessions: [Session]
}

struct PaneResult: Decodable {
    let pane: Pane
}

struct SnapshotResult: Decodable {
    let snapshot: Snapshot
}

struct ExportResult: Decodable {
    struct Layout: Decodable { let root: SplitNode }
    let layout: Layout
}

/// Runs body; past the deadline, calls onTimeout (which must make body end) and throws `.timeout`.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    onTimeout: @escaping @Sendable () -> Void,
    _ body: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: body)
        group.addTask {
            try await Task.sleep(for: duration)
            throw HerdrError.timeout
        }
        defer { group.cancelAll() }
        do {
            guard let value = try await group.next() else { throw HerdrError.timeout }
            return value
        } catch {
            onTimeout()
            throw error
        }
    }
}

/// One NDJSON line, keys sorted so tests can compare lines; nil when the object is not JSON.
func jsonLine(_ object: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
}
