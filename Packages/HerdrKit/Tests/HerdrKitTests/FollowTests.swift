import Foundation
@testable import HerdrKit
import Testing

/// The chat's file follower on This Mac (the relay runs the same script): a file made late, a split write, a resume
/// from a mark, a rotated file, and a big file read from the first line start in its last 256 KiB.
@Test func `follow reads whole lines and goes on from its mark`() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "oriel-follow-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "t.jsonl")
    func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    var lines = try await localExec.follow(file.path, from: FileMark()).makeAsyncIterator()
    try Data("a\n{\"b\":".utf8).write(to: file)
    guard case let .opened(first, restarted)? = await lines.next() else { Issue.record("not opened"); return }
    #expect(restarted && first.offset == 0)
    guard case .line("a", _)? = await lines.next() else { Issue.record("no a"); return }
    try append("2}\n")
    guard case let .line(line, mark)? = await lines.next() else { Issue.record("no b"); return }
    #expect(line == #"{"b":2}"#)
    #expect(mark.offset == 10)

    // A new run from the mark reads only what came since.
    try append("c\n")
    var again = try await localExec.follow(file.path, from: mark).makeAsyncIterator()
    guard case .opened(_, false)? = await again.next(), case .line("c", _)? = await again.next() else {
        Issue.record("no resume"); return
    }
    // Rotated: another file under the name starts again.
    try FileManager.default.removeItem(at: file)
    try Data("d\n".utf8).write(to: file)
    var rotated = try await localExec.follow(file.path, from: mark).makeAsyncIterator()
    guard case .opened(_, true)? = await rotated.next(), case .line("d", _)? = await rotated.next() else {
        Issue.record("no restart"); return
    }

    // The cut lands inside a two-byte character: the mark still counts bytes from a line start.
    let big = folder.appending(path: "big.jsonl")
    try Data((String(repeating: "é", count: 150_000) + "\nlast\n").utf8).write(to: big)
    var cut = try await localExec.follow(big.path, from: FileMark()).makeAsyncIterator()
    guard case let .opened(start, true)? = await cut.next(), case let .line("last", end)? = await cut.next() else {
        Issue.record("not cut"); return
    }
    #expect(start.offset == 300_001 && end.offset == 300_006)
}

@Test func `watch prints a file each time it changes`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "oriel-watch-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    var lines = try await localExec.watch(["/nonexistent/x.json", file.path]).makeAsyncIterator()
    #expect(await lines.next() == "")
    try Data("{\"status\":\n\"idle\"}".utf8).write(to: file)
    #expect(await lines.next() == #"{"status":"idle"}"#)
    try Data(#"{"status":"busy"}"#.utf8).write(to: file)
    #expect(await lines.next() == #"{"status":"busy"}"#)
}
