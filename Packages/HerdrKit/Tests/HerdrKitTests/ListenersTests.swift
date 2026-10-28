import Foundation
@testable import HerdrKit
import Testing

/// A listener started with a herdr pane's environment, found by `lsof` (This Mac) and by `ss` (Linux; here a stand-in
/// on PATH that prints what Linux's prints, with the real pid).
@Test func `listeners with their herdr workspace`() async throws {
    var env = localExec.environment
    env["HERDR_SESSION"] = "oriel-e2e-ports"
    env["HERDR_WORKSPACE_ID"] = "w9"
    // Python, as perl moves its environment where `ps -E` does not find it.
    let server = try ProcessExec.spawn(["python3", "-c", """
    import os, socket, sys
    s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen()
    print(s.getsockname()[1], os.getpid(), flush=True); sys.stdin.read()
    """], env)
    defer { server.closeInput() }
    let started = try #require(await server.lines.first { _ in true }).split(separator: " ")
    let port = try #require(Int(started[0])), pid = started[1]
    let expected = Listener(port: port, command: "Python", session: "oriel-e2e-ports", workspace: "w9")
    #expect(try await localExec.listeners().contains(expected))

    let folder = URL.temporaryDirectory.appending(path: "oriel-ss-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let stand = folder.appending(path: "ss")
    try """
    #!/bin/sh
    echo 'State  Recv-Q Send-Q Local Address:Port  Peer Address:Port Process'
    echo 'LISTEN 0      4096   127.0.0.53%lo:53         0.0.0.0:*'
    echo 'LISTEN 0      128          0.0.0.0:\(port)    0.0.0.0:*     users:(("Python",pid=\(pid),fd=3))'
    echo 'LISTEN 0      128             [::]:\(port)       [::]:*     users:(("Python",pid=\(pid),fd=4))'
    echo 'LISTEN 0      128             [::]:22            [::]:*'
    echo 'LISTEN 0      128         10.0.0.5:8080       0.0.0.0:*'

    """.write(to: stand, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stand.path)
    var linux = localExec.environment
    linux["PATH"] = folder.path + ":" + (linux["PATH"] ?? "")
    let listed = try await ProcessExec(linux, herdr: nil, asked: .now).listeners()
    #expect(listed == [expected, Listener(port: 22, command: "", session: "", workspace: "")])
}
