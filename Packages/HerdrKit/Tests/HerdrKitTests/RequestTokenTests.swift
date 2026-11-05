import Foundation
@testable import HerdrKit
import Testing

// The tokens a pane carries for Ovvi: float, copy and `ovvi` requests, each delivered once.

@Test func `a pane's float tokens deliver one request per nonce, never again`() async throws {
    let exec = FakeExec()
    let client = client(exec)
    let updates = try await started(client, exec)
    let pane = { (target: String, nonce: String) in
        #"{"event":"pane_updated","data":{"type":"pane_updated","pane":{"pane_id":"w1:p2","tokens":"#
            + #"{"ovvi-float":"\#(target)","ovvi-float-id":"\#(nonce)"}}}}"#
    }
    exec.event(pane("pi-herd/w3:p1", "n1"))
    exec.event(pane("pi-herd/w3:p1", "n1"))
    exec.event(pane("pi-herd", "n2"))
    exec.event(pane("/w3:p1", "n4"))
    exec.event(pane("pi-herd/w3:p2", "n3"))
    exec.event(pane("pi-herd/w3:p1", "n1"))
    exec.event(pane("pi-herd/w3:p3", "last"))
    var requests: [FloatRequest] = []
    for await update in updates {
        guard case let .float(request) = update else { continue }
        requests.append(request)
        if request.nonce == "last" {
            break
        }
    }
    #expect(requests.map(\.nonce) == ["n1", "n3", "last"])
    #expect(requests.map(\.session) == ["pi-herd", "pi-herd", "pi-herd"])
    #expect(requests.map(\.pane) == ["w3:p1", "w3:p2", "w3:p3"])
}

@Test func `a pane's copy token reads its file once per id, and only a UUID`() async throws {
    let exec = FakeExec()
    let client = client(exec)
    let updates = try await started(client, exec)
    let pane = { (id: String) in
        #"{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p2","tokens":{"ovvi-copy":"\#(id)"}}}}"#
    }
    let (first, second) = ("0a6e2b1c-4f1d-4c2e-9b7a-1d2e3f4a5b6c", "1b6e2b1c-4f1d-4c2e-9b7a-1d2e3f4a5b6c")
    for id in [first, first, "../x", "\(first);rm", "", "0a-1", second] {
        exec.event(pane(id))
    }
    let reads = { exec[\.argv].filter { $0.first == "sh" }.map(\.last) }
    #expect(await eventually { reads() == [first, second] })
    withExtendedLifetime(updates) {}
}

@Test func `a pane's ring delivers one request per id, only a UUID, the last 256 remembered`() async throws {
    let exec = FakeExec()
    let updates = try await started(client(exec), exec)
    let id = "7f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10"
    let ring = { (pane: String, id: String) in
        exec.event(#"{"event":"pane_updated","data":{"pane":{"pane_id":"\#(pane)","tokens":{"ovvi-req":"\#(id)"}}}}"#)
    }
    let others = (0 ..< 256).map { _ in UUID().uuidString.lowercased() }
    ring("w1:p2", id)
    ring("w1:p2", id)
    ring("w1:p2", "../x")
    ring("w1:p3", id.uppercased())
    others.forEach { ring("w1:p3", $0) }
    ring("w1:p4", id)
    var requests: [(String, String)] = []
    for await update in updates {
        guard case let .request(id, pane) = update else { continue }
        requests.append((id, pane))
        if pane == "w1:p4" {
            break
        }
    }
    #expect(requests.map(\.0) == [id] + others + [id])
    #expect(requests.first?.1 == "w1:p2")
}

@Test func `a ring in a snapshot, which the stream missed, delivers its request once`() async throws {
    let exec = FakeExec()
    let (id, other) = ("7f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10", "8f9c2b1e-4d0a-4c55-9a51-0b6c3e2d8f10")
    exec.state.withLock {
        $0.panes = [#"{"pane_id":"w1:p2","tab_id":"w1:t1","tokens":{"ovvi-req":"\#(id)","ovvi-shown":"1"}}"#]
    }
    let updates = try await started(client(exec), exec)
    // The same id again from another pane is a repeat.
    exec.event(#"{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p3","tokens":{"ovvi-req":"\#(id)"}}}}"#)
    exec.event(#"{"event":"pane_updated","data":{"pane":{"pane_id":"w1:p4","tokens":{"ovvi-req":"\#(other)"}}}}"#)
    var requests: [String] = []
    for await case let .request(ring, pane) in updates {
        requests.append("\(pane) \(ring)")
        if pane == "w1:p4" {
            break
        }
    }
    #expect(requests == ["w1:p2 \(id)", "w1:p4 \(other)"])
}
