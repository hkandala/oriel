import Foundation
@testable import HerdrKit
import Network
import Synchronization
import Testing

/// The browser proxy's front, before a stand-in for ssh's `-D` that opens only `localhost:7` and echoes there, and
/// closes any other request without a reply, as ssh does.
@Test func `front asks for localhost and refuses at once`() async throws {
    let asked = Mutex<[String]>([])
    let ssh = try NWListener(using: .tcp, on: .any)
    ssh.newConnectionHandler = { connection in
        connection.start(queue: .global())
        Task {
            guard await connection.read(3) == Data([5, 1, 0]) else { return connection.cancel() }
            connection.send(content: Data([5, 0]), completion: .idempotent)
            guard let head = await connection.read(5), let name = await connection.read(Int(head[4])),
                  let port = await connection.read(2)
            else { return connection.cancel() }
            let host = String(decoding: name, as: UTF8.self)
            asked.withLock { $0.append(host) }
            guard host == "localhost", port == Data([0, 7]) else { return connection.cancel() }
            connection.send(content: Data([5, 0, 0, 1, 127, 0, 0, 1, 0, 7]), completion: .idempotent)
            while let data = await connection.readSome() {
                connection.send(content: data, completion: .idempotent)
            }
        }
    }
    ssh.start(queue: .global())
    defer { ssh.cancel() }
    while ssh.port?.rawValue ?? 0 == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }
    let upstream = try #require(ssh.port?.rawValue)
    let front = try await SOCKSFront.start { upstream }
    defer { front.stop() }

    // A page's CONNECT through the front: its reply code, and the connection.
    func connect(_ host: String, _ port: UInt16) async throws -> (UInt8?, NWConnection) {
        let page = try NWConnection(host: .ipv4(.loopback), port: #require(.init(rawValue: front.port)), using: .tcp)
        page.start(queue: .global())
        page.send(content: Data([5, 1, 0]), completion: .idempotent)
        #expect(await page.read(2) == Data([5, 0]))
        page.send(content: Data([5, 1, 0, 3, UInt8(host.utf8.count)]) + Data(host.utf8)
            + Data([UInt8(port >> 8), UInt8(port & 0xFF)]), completion: .idempotent)
        return await (page.read(10)?[1], page)
    }

    let (open, page) = try await connect("Devbox.localhost", 7)
    #expect(open == 0)
    page.send(content: Data("ping".utf8), completion: .idempotent)
    #expect(await page.read(4) == Data("ping".utf8))
    page.cancel()
    let (refused, _) = try await connect("devbox.localhost", 8)
    #expect(refused == 5)
    let (other, _) = try await connect("db.internal", 7)
    #expect(other == 5)
    #expect(asked.withLock { $0 } == ["localhost", "localhost", "db.internal"])
}
