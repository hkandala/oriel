import Foundation
@testable import HerdrKit
import Testing

/// The envelope runs in the remote login shell; `sh` here stands in for it.
@Test func `envelope runs the argv unchanged`() async throws {
    let argv = ["printf", "%s|", "it's", "a b", "$HOME", "\"q\"", "`x`", "ü\n2"]
    let exec = localExec
    let out = try await exec.output(["sh", "-c", SSHExec.envelope(argv)])
    #expect(out == "it's|a b|$HOME|\"q\"|`x`|ü\n2|")
}

@Test func `targets that are not options`() {
    #expect(SSHExec.isValidTarget("user@devbox"))
    #expect(!SSHExec.isValidTarget("-oProxyCommand=x"))
    #expect(!SSHExec.isValidTarget("a b"))
    #expect(!SSHExec.isValidTarget(""))
}

/// The relay here, without ssh: runs at once over one process, their stdin, exits and kills.
@Test func `relay carries runs over one process`() async throws {
    let local = localExec
    let relay = try #require(await Relay.start(ProcessExec.spawn(["perl", "-e", Relay.script], local.environment)))
    let failing = try relay.run("echo out; echo err >&2; exit 3")
    let echo = try relay.run("cat")
    let sleeping = try relay.run("sleep 100")
    echo.write(#"{"a": "b c"}"#)
    echo.closeInput()
    #expect(await echo.lines.reduce([]) { $0 + [$1] } == [#"{"a": "b c"}"#])
    #expect(await echo.exit() == (0, ""))
    #expect(await failing.lines.reduce([]) { $0 + [$1] } == ["out"])
    #expect(await failing.exit() == (3, "err\n"))
    sleeping.terminate()
    #expect(await sleeping.exit().status == 9)
    // A kill closes stdin too: the observe wrapper's background child ends, and so the run (T6).
    let watching = try relay.run(SSHExec.quoted([
        "sh",
        "-c",
        TerminalStream.observeWrapper,
        "sh",
        "sh",
        "-c",
        "while :; do echo t; sleep 0.1; done",
    ]))
    #expect(await watching.lines.first { _ in true } == "t")
    watching.terminate()
    #expect(await watching.exit().status == 9)
}

/// A remote machine's runs, here without ssh: SSHExec's relay and command.
struct RelayExec: Exec {
    let relay: Relay

    static func start() async throws -> RelayExec {
        try await RelayExec(relay: #require(Relay.start(ProcessExec.spawn(["perl", "-e", Relay.script],
                                                                          localExec.environment))))
    }

    func run(_ argv: [String]) throws -> Channel {
        try relay.run("exec " + SSHExec.quoted(argv))
    }

    func herdr() -> String? {
        nil
    }
}

/// A dropped file's copy over the relay (here without ssh): the same bytes under the same name, in a folder of its own.
@Test func `upload copies a file whole`() async throws {
    let exec = try await RelayExec.start()
    let folder = URL.temporaryDirectory.appending(path: "oriel-upload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "it's a\nfile.bin")
    let bytes = Data((0 ..< 100_001).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    try bytes.write(to: file)
    let copy = try await URL(filePath: exec.upload(file))
    #expect(copy.lastPathComponent == file.lastPathComponent)
    #expect(copy.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "oriel-drops-\(getuid())")
    #expect(try Data(contentsOf: copy) == bytes)
    try FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    await #expect(throws: HerdrError.failed("\(folder.lastPathComponent) is not a file")) {
        try await exec.upload(folder)
    }
}

/// `git … -z` output keeps its NUL bytes over the relay, also past the relay's 64 KB reads.
@Test func `relay passes NUL bytes unchanged`() async throws {
    let relay = try #require(await Relay.start(ProcessExec.spawn(["perl", "-e", Relay.script], localExec.environment)))
    let run = try relay
        .run(#"printf 'a\000b c\000\n'; i=0; while [ $i -lt 20000 ]; do printf 'x/y z\000'; i=$((i+1)); done"#)
    run.closeInput()
    let lines = await run.lines.reduce([]) { $0 + [$1] }
    #expect(lines.first == "a\0b c\0")
    #expect(lines.count == 2 && lines[1] == String(repeating: "x/y z\0", count: 20000))
}
