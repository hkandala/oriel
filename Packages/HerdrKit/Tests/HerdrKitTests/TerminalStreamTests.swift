import Foundation
@testable import HerdrKit
import Synchronization
import Testing

@Test func `reads frames and skips other lines`() {
    let line = #"{"type":"terminal.frame","seq":3,"encoding":"ansi","width":80,"height":24,"full":true,"#
        + #""bytes":"G1sySmhp"}"#
    #expect(TerminalStream.event(line) == .frame(.init(width: 80, height: 24, full: true,
                                                       bytes: Data("\u{1B}[2Jhi".utf8))))
    #expect(TerminalStream.event(#"{"type":"terminal.frame","width":80,"height":24,"bytes":"%%"}"#) == nil)
    #expect(TerminalStream.event(#"{"type":"terminal.graphics"}"#) == nil)
    #expect(TerminalStream.event("herdr: warning") == nil)
}

@Test(arguments: [
    ("terminal attach failed: terminal term_1 already has an attached client; retry with --takeover", .held),
    ("terminal attach taken over", .held),
    ("terminal session control failed: terminal target term_1 not found", .ended),
    ("terminal term_1 exited", .ended),
    ("detached", .ended),
    ("live update in progress; reconnect after handoff completes", .liveUpdate),
    ("server shutting down", .failed("server shutting down")),
] as [(String, TerminalStream.Closed)])
func `sorts closed reasons`(reason: String, closed: TerminalStream.Closed) {
    let line = #"{"type":"terminal.closed","reason":"\#(reason)"}"#
    #expect(TerminalStream.event(line) == .closed(closed))
}

@Test func `encodes scroll and mouse commands`() {
    let written = Mutex<[String]>([])
    let stream = TerminalStream(Channel(
        lines: AsyncStream { _ in },
        write: { line in written.withLock { $0.append(line) } },
        closeInput: {},
        terminate: {},
        exit: { (0, "") },
    ))
    stream.scroll(lines: -3, column: 4, row: 5, modifiers: 0)
    stream.scroll(lines: 2, column: 0, row: 0, modifiers: 1)
    stream.mouse(.down, .right, column: 7, row: 2, modifiers: 6)
    #expect(written.withLock { $0 } == [
        #"{"column":4,"direction":"up","lines":3,"modifiers":0,"row":5,"type":"terminal.scroll"}"#,
        #"{"column":0,"direction":"down","lines":2,"modifiers":1,"row":0,"type":"terminal.scroll"}"#,
        #"{"action":"down","button":"right","column":7,"modifiers":6,"row":2,"type":"terminal.mouse"}"#,
    ])
}

@Test func `a run that ends without a closed line fails with stderr`() async {
    let (lines, end) = AsyncStream<String>.makeStream()
    let stream = TerminalStream(Channel(lines: lines, write: { _ in }, closeInput: {}, terminate: {},
                                        exit: { (1, "herdr: failed to connect\n") }))
    end.finish()
    #expect(await stream.events.first { _ in true } == .closed(.failed("herdr: failed to connect")))
}

@Test func `an observe that fails by itself ends with its reason`() async throws {
    let herdr = FileManager.default.temporaryDirectory.appending(path: "herdr-\(UUID().uuidString)").path
    try "#!/bin/sh\necho 'handshake failed' >&2; exit 1\n".write(toFile: herdr, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: herdr)
    defer { try? FileManager.default.removeItem(atPath: herdr) }
    let client = HerdrClient(session: "oriel-e2e-none", exec: ProcessExec([:], herdr: herdr, asked: .now))
    let stream = try await client.terminal("term_1", cols: 10, rows: 5, observe: true)
    // Stdin stays open: the stream must end without it.
    let closed = try await withTimeout(.seconds(5), onTimeout: {}, { await stream.events.first { _ in true } })
    #expect(closed == .closed(.failed("handshake failed")))
}
