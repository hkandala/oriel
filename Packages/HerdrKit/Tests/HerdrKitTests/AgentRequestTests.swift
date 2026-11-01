import Foundation
@testable import HerdrKit
import Testing

private let id = "7f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10"

private func request(_ fields: [String]) -> Data {
    Data(fields.map { $0 + "\0" }.joined().utf8)
}

@Test func `a request is its folder and arguments, empty ones too`() throws {
    let parsed = try AgentRequest(request(["oriel-req", "1", "/repo", "open", "git", "", "uncommitted"]))
    #expect(parsed.cwd == "/repo")
    #expect(parsed.argv == ["open", "git", "", "uncommitted"])
    #expect(try AgentRequest(request(["oriel-req", "1", "/"])).argv.isEmpty)
}

@Test func `a request that is not one, too large or too new is refused`() {
    #expect(throws: AgentRequest.Problem.unreadable) { try AgentRequest(Data("oriel-req\u{0}1\u{0}/".utf8)) }
    #expect(throws: AgentRequest.Problem.unreadable) { try AgentRequest(request(["oriel-float", "1", "/"])) }
    #expect(throws: AgentRequest.Problem.unreadable) { try AgentRequest(request(["oriel-req", "x", "/"])) }
    #expect(throws: AgentRequest.Problem.unreadable) { try AgentRequest(request(["oriel-req", "1"])) }
    #expect(throws: AgentRequest.Problem.newer(2)) { try AgentRequest(request(["oriel-req", "2", "/", "info"])) }
    let fields = ["oriel-req", "1", "/"] + Array(repeating: "a", count: 62)
    #expect(throws: AgentRequest.Problem.tooLarge) { try AgentRequest(request(fields)) }
    #expect(throws: Never.self) { try AgentRequest(request(fields.dropLast())) }
    let big = String(repeating: "a", count: AgentRequest.limit)
    #expect(throws: AgentRequest.Problem.tooLarge) { try AgentRequest(request(["oriel-req", "1", "/", big])) }
}

@Test func `only a lowercase UUID version 4 is an id`() {
    #expect(AgentRequest.isID(id))
    for bad in [id.uppercased(), "7f9c2b1e-4d0a-3c55-9a51-0b6c3e2d8f10", "7f9c2b1e-4d0a-4c55-7a51-0b6c3e2d8f10",
                "../" + id, id + "\n", id + ".req", "", "7f9c2b1e"]
    {
        #expect(!AgentRequest.isID(bad), "\(bad)")
    }
}

/// The real runs, against a mailbox in a temporary home.
private func mailbox() throws -> (ProcessExec, URL) {
    let home = FileManager.default.temporaryDirectory.appending(path: "oriel-mailbox-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return (ProcessExec(["HOME": home.path, "PATH": "/usr/bin:/bin"], herdr: nil, asked: .now), home)
}

@Test func `one take wins, and the answer replaces the request`() async throws {
    let (exec, home) = try mailbox()
    defer { try? FileManager.default.removeItem(at: home) }
    await exec.prepareAgent(script: Data("#!/bin/sh\n# oriel-cli 1\n".utf8))
    let rpc = home.appending(path: ".cache/oriel/rpc")
    let mode = try FileManager.default.attributesOfItem(atPath: rpc.path)[.posixPermissions] as? Int
    #expect(mode == 0o700)
    let fields = request(["oriel-req", "1", "/repo", "copy"])
    try fields.write(to: rpc.appending(path: "\(id).req"))
    try Data("text".utf8).write(to: rpc.appending(path: "\(id).in"))

    #expect(try await exec.take(request: id) == fields)
    #expect(try await exec.take(request: id) == nil)
    #expect(try await exec.input(request: id) == Data("text".utf8))
    try await exec.answer(request: id, code: 1, out: Data("{\"a\":1}\n".utf8), err: "oriel: no\n")
    let files = try FileManager.default.contentsOfDirectory(atPath: rpc.path).sorted()
    #expect(files == ["\(id).exit", "\(id).out"])
    #expect(try String(contentsOf: rpc.appending(path: "\(id).out"), encoding: .utf8) == "{\"a\":1}\n")
    #expect(try String(contentsOf: rpc.appending(path: "\(id).exit"), encoding: .utf8) == "1\noriel: no\n")
    #expect(try await exec.input(request: id).isEmpty)
}

@Test func `the script is written when missing or older, never over a newer one`() async throws {
    let (exec, home) = try mailbox()
    defer { try? FileManager.default.removeItem(at: home) }
    let script = home.appending(path: ".cache/oriel/bin/oriel")
    let ours = Data("#!/bin/sh\n# oriel-cli 1.2\necho ours\n".utf8)
    await exec.prepareAgent(script: ours)
    #expect(try Data(contentsOf: script) == ours)
    #expect(FileManager.default.isExecutableFile(atPath: script.path))

    for newer in ["1.3", "2", "2.0"] {
        let theirs = Data("#!/bin/sh\n# oriel-cli \(newer)\n".utf8)
        try theirs.write(to: script)
        await exec.prepareAgent(script: ours)
        #expect(try Data(contentsOf: script) == theirs, "\(newer)")
    }
    for older in ["1", "1.1", "0.9", "x"] {
        try Data("#!/bin/sh\n# oriel-cli \(older)\n".utf8).write(to: script)
        await exec.prepareAgent(script: ours)
        #expect(try Data(contentsOf: script) == ours, "\(older)")
    }
}
