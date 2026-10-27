import Foundation
@testable import HerdrKit
import Synchronization
import Testing

/// The repository's root, for its scripts and resources.
let repoRoot = URL(filePath: #filePath).appending(path: "../../../../..").standardized
private let script = repoRoot.appending(path: "scripts/herdr-session.sh").path

/// Awaits the command's exit instead of blocking a thread: tests run in parallel on Swift's cooperative pool, which
/// has one thread per core, and a session start in `waitUntilExit` (up to seconds) held them; the timing test of
/// the snapshot pacing then saw its read start 100 ms late on CI's small VM.
@discardableResult
private func shell(_ argv: String...) async -> Int32 {
    await withCheckedContinuation { continuation in
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = argv
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        do { try process.run() } catch { continuation.resume(returning: -1) }
    }
}

/// This Mac's runs with the test run's environment and herdr from its PATH, not the app's login-shell lookup: its 3 s
/// bound ran out under heavy load (a load of 200), and herdr was not found.
let localExec: ProcessExec = {
    ProcessExec.prepare()
    let env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
    let herdr = env["PATH"]?.split(separator: ":").map { "\($0)/herdr" }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    return ProcessExec(env, herdr: herdr, asked: .now)
}()

private let herdrInstalled: @Sendable () async -> Bool = { await shell("which", "herdr") == 0 }

/// A client for a new throwaway session, removed after `body`.
private func withSession(_ exec: any Exec, _ body: (HerdrClient) async throws -> Void) async throws {
    let session = "oriel-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    try #require(await shell(script, "up", session) == 0)
    defer { await shell(script, "down", session) }
    try await body(HerdrClient(session: session, exec: exec))
}

/// Counts `events.subscribe` requests, so a test can tell a read caused by an event from one after
/// the stream reopened.
private final class SubscribeCounter: Exec {
    let base: ProcessExec
    let subscribes = Mutex(0)

    init(_ base: ProcessExec) {
        self.base = base
    }

    func herdr() async -> String? {
        await base.herdr()
    }

    func run(_ argv: [String]) async throws -> Channel {
        let channel = try await base.run(argv)
        return Channel(
            lines: channel.lines,
            write: { line in
                if line.contains("events.subscribe") {
                    self.subscribes.withLock { $0 += 1 }
                }
                channel.write(line)
            },
            closeInput: channel.closeInput,
            terminate: channel.terminate,
            exit: channel.exit,
        )
    }
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `stops and deletes a throwaway session`() async throws {
    try await withSession(localExec) { client in
        // herdr refuses to delete a running session, and says why.
        let refused = await #expect(throws: HerdrError.self) { try await client.deleteSession() }
        #expect(refused?.localizedDescription.contains("stop it before deleting") == true)
        try await client.stopSession()
        #expect(try await client.sessions().contains { $0.name == client.session && !$0.running })
        try await client.deleteSession()
        #expect(try await !client.sessions().contains { $0.name == client.session })
    }
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `talks to a throwaway herdr session`() async throws {
    let exec = SubscribeCounter(localExec)
    try await withSession(exec) { client in try await talk(client, exec) }
}

private func talk(_ client: HerdrClient, _ exec: SubscribeCounter) async throws {
    #expect(try await client.sessions().contains { $0.name == client.session && $0.running })
    let _: Created = try await client.call("workspace.create", ["cwd": "/tmp", "focus": false])

    let updates = await client.updates()
    let found = try await withTimeout(.seconds(10), onTimeout: {}, { () -> Snapshot? in
        var reads = 0
        for await case let .snapshot(snapshot) in updates {
            reads += 1
            // The second read follows the open events stream, so the next one comes from an event.
            if reads == 2 {
                let _: Created = try await client.call(
                    "tab.create",
                    ["workspace_id": "w1", "cwd": "/tmp", "focus": false],
                )
            }
            if snapshot.tabs.count == 2 {
                return snapshot
            }
        }
        return nil
    })
    let snapshot = try #require(found)
    // Still the first events stream: the event caused the read, not a reopened stream. A reopen
    // reads before it subscribes again, so wait past its 1 s backoff before counting.
    try await Task.sleep(for: .milliseconds(1500))
    #expect(exec.subscribes.withLock { $0 } == 1)
    withExtendedLifetime(updates) {}
    let tab = try #require(snapshot.tabs.last)
    #expect(tab.workspaceID == "w1")
    let pane = try #require(snapshot.panes.first { $0.tabID == tab.id })
    #expect(snapshot.trees[tab.id] == SplitNode.leaf(paneID: pane.id))
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `a program's OSC 52 write comes out as an update`() async throws {
    try await withSession(localExec) { client in
        let pane = try await (client.call("workspace.create", ["cwd": "/tmp", "focus": false]) as NewWorkspace)
            .root_pane
        let updates = await client.updates()
        // Over 250 bytes of base64, so its length takes bincode's three-byte form; the typed line says %s, so only
        // the program's output is the text.
        let text = String(repeating: "oriel-osc52-42 ", count: 20)
        let command = "printf '\\033]52;c;%s\\a' $(printf '\(text.replacingOccurrences(of: "42", with: "%s"))' "
            + "\(Array(repeating: "$((6*7))", count: 20).joined(separator: " ")) | base64)\r"
        struct Sent: Decodable {}
        // Sent each second: a write before the clipboard client's hello goes to no client.
        let sender = Task {
            while !Task.isCancelled {
                let _: Sent? = try? await client.call("pane.send_text", ["pane_id": pane.pane_id, "text": command])
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { sender.cancel() }
        let copied = try await withTimeout(.seconds(10), onTimeout: {}, { () -> String? in
            for await case let .clipboard(copied) in updates {
                return copied
            }
            return nil
        })
        #expect(copied == text)
    }
}

@Test func `output of fast commands always ends`() async throws {
    let exec = localExec
    try await withThrowingTaskGroup(of: [String].self) { group in
        for _ in 0 ..< 30 {
            group.addTask {
                let channel = try await exec.run(["sh", "-c", "echo hi"])
                channel.closeInput()
                return try await withTimeout(.seconds(5), onTimeout: channel.terminate) {
                    await channel.lines.reduce(into: []) { $0.append($1) }
                }
            }
        }
        for try await lines in group {
            #expect(lines == ["hi"])
        }
    }
}

@Test func `a long line and the lines around it read whole, and quickly`() async throws {
    let exec = localExec
    // 8 MB in one line, as a big session's snapshot comes (280 KB at 400 panes), in many pipe chunks.
    let channel = try await exec.run(["sh", "-c", "echo a; head -c 8000000 /dev/zero | tr '\\0' x; echo; echo b"])
    channel.closeInput()
    let start = ContinuousClock.now
    let lines = await channel.lines.reduce(into: []) { $0.append($1) }
    #expect(lines.map(\.count) == [1, 8_000_000, 1])
    // A scan from the line's start for each chunk took about 16 s here, the linear split under 1 s: a bound a slow,
    // shared CI runner meets (1 s did not).
    #expect(ContinuousClock.now - start < .seconds(6))
}

@Test func `terminate stops the readers when a grandchild keeps the pipes open`() async throws {
    let exec = localExec
    let channel = try await exec.run(["sh", "-c", "sleep 8 & echo hi"])
    #expect(await channel.lines.first { _ in true } == "hi")
    channel.terminate()
    // stderr is still open in `sleep`; without stopping its reader, this waits 8 s.
    _ = try await withTimeout(.seconds(5), onTimeout: {}, { await channel.exit() })
}

@Test func `the login shell gives its variables and herdr's path`() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "oriel-shell-\(UUID().uuidString.prefix(6))")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir.appending(path: "bin"), withIntermediateDirectories: true)
    let shell = dir.appending(path: "shell").path, herdr = dir.appending(path: "bin/herdr").path
    // Counts its runs; an rc file that prints without a final newline.
    let source = "#!/bin/sh\necho >> \"$0.count\"\nprintf motd\nsh -c \"$2\"\n"
    try source.write(toFile: shell, atomically: true, encoding: .utf8)
    try "".write(toFile: herdr, atomically: true, encoding: .utf8)
    for path in [shell, herdr] {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
    let found = await ProcessExec.loginShell(["SHELL": shell, "PATH": "\(dir.path)/bin:/usr/bin:/bin", "XDG_X": "1"])
    #expect(found.herdr == herdr && found.vars["XDG_X"] == "1")
    #expect(await ProcessExec.loginShell(["SHELL": shell, "PATH": "/usr/bin:/bin"]).herdr == nil)

    // While herdr is missing: one login shell at a time, then none for 30 s.
    try FileManager.default.removeItem(atPath: shell + ".count")
    let exec = ProcessExec(["SHELL": shell, "PATH": "/usr/bin:/bin"], herdr: nil, asked: .now - .seconds(31))
    async let first = exec.herdr(), second = exec.herdr(), third = exec.herdr()
    #expect(await [first, second, third] == [nil, nil, nil])
    #expect(await exec.herdr() == nil)
    #expect(try String(contentsOfFile: shell + ".count", encoding: .utf8) == "\n")
}

private struct NewWorkspace: Decodable {
    struct Pane: Decodable {
        let pane_id: String // swiftlint:disable:this identifier_name
        let terminal_id: String // swiftlint:disable:this identifier_name
    }

    let root_pane: Pane // swiftlint:disable:this identifier_name
}

/// How a stream ends, past its frames.
private func closedReason(_ events: inout AsyncStream<TerminalStream.Event>.Iterator) async -> TerminalStream.Closed? {
    while let event = await events.next() {
        if case let .closed(reason) = event {
            return reason
        }
    }
    return nil
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `controls a throwaway terminal`() async throws {
    try await withSession(localExec, control)
}

private func control(_ client: HerdrClient) async throws {
    let pane = try await (client.call("workspace.create", ["cwd": "/tmp", "focus": false]) as NewWorkspace).root_pane
    let terminal = pane.terminal_id

    try await withTimeout(.seconds(20), onTimeout: {}, {
        let control = try await client.terminal(terminal, cols: 60, rows: 12)
        var events = control.events.makeAsyncIterator()
        guard case let .frame(first)? = await events.next() else { throw HerdrError.failed("no first frame") }
        #expect(first.width == 60 && first.height == 12)

        control.input("echo oriel-$((6*7)); stty size\r")
        var text = ""
        for _ in 0 ..< 50 where !text.contains("12 60") {
            try await Task.sleep(for: .milliseconds(100))
            text = try await client.screen(pane.pane_id)
        }
        #expect(text.contains("oriel-42"))
        #expect(text.contains("12 60"))

        control.resize(cols: 70, rows: 15, cellWidth: 8, cellHeight: 17)
        var resized: TerminalStream.Frame?
        while resized == nil, case let .frame(frame)? = await events.next() {
            resized = frame.width == 70 ? frame : nil
        }
        #expect(resized?.width == 70 && resized?.height == 15)

        // Held: a second controller is refused, a watcher is not.
        let second = try await client.terminal(terminal, cols: 60, rows: 12)
        #expect(await second.events.first { _ in true } == .closed(.held))
        let watcher = try await client.terminal(terminal, cols: 60, rows: 12, observe: true)
        guard case let .frame(watched)? = await watcher.events.first(where: { _ in true }) else {
            throw HerdrError.failed("no observe frame")
        }
        #expect(watched.width == 60)
        // observe ignores stdin's end; its wrapper ends it, though the pane prints nothing.
        let observer = try await "^\(client.herdr()) --session \(client.session) terminal session observe"
        #expect(await shell("pgrep", "-f", observer) == 0)
        watcher.close()
        #expect(await eventually { await shell("pgrep", "-f", observer) == 1 })

        // Taken over: a controller with --takeover wins, the first one hears it.
        let taker = try await client.terminal(terminal, cols: 60, rows: 12, takeover: true)
        #expect(await closedReason(&events) == .held)
        taker.close()
        var takerEvents = taker.events.makeAsyncIterator()
        #expect(await closedReason(&takerEvents) == .ended)
    })
}

/// The server the app starts gets the CLI's user keys: with `XDG_CONFIG_HOME` elsewhere, both find the session
/// there (design: XDG fix). The app's own keys stay out (D47), and herdr runs by its absolute path.
@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `a started server shares the CLI's paths`() async throws {
    struct Moved: Exec {
        let base: ProcessExec
        let config: String
        func herdr() async -> String? {
            await base.herdr()
        }

        func run(_ argv: [String]) async throws -> Channel {
            try await base.run(["env", "XDG_CONFIG_HOME=\(config)", "__CFBundleIdentifier=dev.hkandala.oriel"] + argv)
        }
    }
    // Not the temporary directory: a socket path there is too long.
    let config = "/tmp/oriel-xdg-\(UUID().uuidString.prefix(6))"
    let session = "oriel-e2e-\(UUID().uuidString.prefix(6).lowercased())"
    defer {
        await shell("launchctl", "bootout", "gui/\(getuid())/dev.hkandala.oriel.herdr.\(session)")
        try? FileManager.default.removeItem(atPath: config)
        try? FileManager.default.removeItem(at: URL.libraryDirectory.appending(path: "Logs/Oriel/\(session).log"))
    }
    let base = localExec
    let client = HerdrClient(session: session, exec: Moved(base: base, config: config))
    try await client.startServer(within: .seconds(10))
    #expect(FileManager.default.fileExists(atPath: "\(config)/herdr/sessions/\(session)"))
    let job = try await base.output(["launchctl", "print", "gui/\(getuid())/dev.hkandala.oriel.herdr.\(session)"])
    // The login shell's herdr and its PATH as it is.
    let herdr = try #require(await base.herdr())
    #expect(job.contains("program = \(herdr)\n") && job.contains("PATH => \(base.environment["PATH"] ?? "")\n"))
    #expect(job.contains("XDG_CONFIG_HOME") && !job.contains("__CFBundleIdentifier"))
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `changes a layout in a throwaway herdr session`() async throws {
    try await withSession(localExec) { client in
        let _: Created = try await client.call("workspace.create", ["cwd": "/tmp", "focus": false])
        let second = try #require(try await client.split("w1:p1", .right))
        let third = try #require(try await client.split(second.id, .right))
        #expect(third.tabID == "w1:t1")
        let tree = try #require(try await client.snapshot().trees["w1:t1"])
        // herdr halved p2: 50 / 25 / 25; the root goes to 1/3, its second child stays at 1/2.
        let evened = tree.evened(around: third.id)
        #expect(evened.map(\.path) == [[]])
        for change in evened {
            try await client.setRatio(tab: "w1:t1", path: change.path, ratio: change.ratio)
        }
        #expect(try await client.snapshot().trees["w1:t1"]?.evened().isEmpty == true)
        // Decodes herdr's reply; the prompt may not have drawn yet.
        _ = try await client.screen("w1:p1")
        _ = try await client.recent("w1:p1", lines: 100)
        try await client.scroll("w1:p1", offsetFromBottom: 0)
        #expect(try await client.pane("w1:p1").scroll?.offsetFromBottom == 0)
        try await client.swap("w1:p1", .right)
        #expect(try await client.snapshot().trees["w1:t1"]?.paneIDs == [second.id, "w1:p1", third.id])
        try await client.rename(pane: "w1:p1", label: "named")
        #expect(try await client.pane("w1:p1").label == "named")
        try await client.rename(pane: "w1:p1", label: nil)
        #expect(try await client.pane("w1:p1").label == nil)
        let moved = try await client.move(pane: third.id, to: .newTab(workspaceID: "w1", label: "named tab"))
        #expect(moved?.tabID != "w1:t1")
        #expect(try await client.snapshot().tabs.first { $0.id == moved?.tabID }?.label
            == "named tab")
        let away = try await client.move(pane: second.id, to: .newWorkspace())
        #expect(away?.id.hasPrefix("w2:") == true)
    }
}

@Test(.enabled("herdr is not on PATH", herdrInstalled))
func `moves beside a pane, swaps by id, and throws herdr's refusals`() async throws {
    try await withSession(localExec) { client in
        let _: Created = try await client.call("workspace.create", ["cwd": "/tmp", "focus": false])
        let second = try #require(try await client.split("w1:p1", .right))
        let other = try #require(try await client.move(pane: second.id, to: .newTab(workspaceID: "w1")))
        // Back beside p1, under it.
        let back = try await client.move(pane: other.id, to: .tab("w1:t1", beside: "w1:p1", split: .down, ratio: 0.3))
        #expect(back?.tabID == "w1:t1")
        guard case let .split(direction, ratio, _, _)? = try await client.snapshot().trees["w1:t1"] else {
            Issue.record("no split")
            return
        }
        #expect(direction == .down)
        #expect(abs(ratio - 0.3) < 0.001)
        try await client.swap(second.id, with: "w1:p1")
        #expect(try await client.snapshot().trees["w1:t1"]?.paneIDs == [second.id, "w1:p1"])
        await #expect(throws: HerdrError.refused("same_tab")) {
            try await client.move(pane: second.id, to: .tab("w1:t1"))
        }
        let lone = try #require(try await client.move(pane: second.id, to: .newTab(workspaceID: "w1")))
        await #expect(throws: HerdrError.refused("cross_tab")) { try await client.swap(lone.id, with: "w1:p1") }
    }
}
