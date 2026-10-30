import Foundation
@testable import HerdrKit
import Testing

/// A follow's lines one by one, as its batches bring them.
private func lineByLine(_ path: String, from mark: FileMark,
                        skip: String = "0") async throws -> AsyncStream<FollowedLine>
{
    let batches = try await localExec.follow(path, from: mark, skip: skip)
    let (stream, continuation) = AsyncStream<FollowedLine>.makeStream()
    let task = Task {
        for await batch in batches {
            batch.forEach { continuation.yield($0) }
        }
        continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
}

/// The chat's file follower on This Mac (the relay runs the same script): a file made late, a split write, a resume
/// from a mark, a rotated file, and a big file read whole.
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

    var lines = try await lineByLine(file.path, from: FileMark()).makeAsyncIterator()
    try Data("a\n{\"b\":".utf8).write(to: file)
    guard case let .opened(first, restarted)? = await lines.next() else { Issue.record("not opened"); return }
    #expect(restarted && first.offset == 0)
    // `loaded` before the line still being written.
    guard case .line("a", _)? = await lines.next(), case .loaded? = await lines.next() else {
        Issue.record("no a"); return
    }
    try append("2}\n")
    guard case let .line(line, mark)? = await lines.next() else { Issue.record("no b"); return }
    #expect(line == #"{"b":2}"#)
    #expect(mark.offset == 10)

    // A new run from the mark reads only what came since.
    try append("c\n")
    var again = try await lineByLine(file.path, from: mark).makeAsyncIterator()
    guard case .opened(_, false)? = await again.next(), case .line("c", _)? = await again.next() else {
        Issue.record("no resume"); return
    }
    // Rotated: another file under the name starts again.
    try FileManager.default.removeItem(at: file)
    try Data("d\n".utf8).write(to: file)
    var rotated = try await lineByLine(file.path, from: mark).makeAsyncIterator()
    guard case .opened(_, true)? = await rotated.next(), case .line("d", _)? = await rotated.next() else {
        Issue.record("no restart"); return
    }

    // A new file is read whole, from its first line, also past 256 KiB; then `loaded`.
    let big = folder.appending(path: "big.jsonl")
    try Data(("first\n" + String(repeating: "é", count: 150_000) + "\nlast\n").utf8).write(to: big)
    var whole = try await lineByLine(big.path, from: FileMark()).makeAsyncIterator()
    guard case .opened(_, true)? = await whole.next(), case .line("first", _)? = await whole.next(),
          case .line(_, _)? = await whole.next(), case let .line("last", end)? = await whole.next(),
          case .loaded? = await whole.next() else { Issue.record("not whole"); return }
    #expect(end.offset == 300_012)
}

/// Skipped lines never come, but the mark counts their bytes; `loaded` comes at the open's last whole line, before the
/// line still being written.
@Test func `follow skips the lines no parser reads`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "oriel-skip-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(#"{"type":"blob","é":1}\#n{"keep":1}\#n{"type":"blob"}\#n{"ke"#.utf8).write(to: file)
    var lines = try await lineByLine(file.path, from: FileMark(), skip: #"/^[{]"type":"blob"/"#)
        .makeAsyncIterator()
    guard case .opened? = await lines.next(), case let .line(#"{"keep":1}"#, mark)? = await lines.next(),
          case .loaded? = await lines.next() else { Issue.record("not skipped"); return }
    #expect(mark.offset == 34)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"ep":2}\#n"#.utf8))
    try handle.close()
    guard case let .line(#"{"keep":2}"#, last)? = await lines.next() else { Issue.record("no last"); return }
    #expect(last.offset == 61)
}

/// A follow dropped in the middle of its backlog sends no more of it: a remote one would flood the relay, and through
/// awk a `head` left behind would hang on the FIFO. (Without awk, this Mac's reader drains the pipe before the kill.)
@Test(.timeLimit(.minutes(1))) func `a dropped follow stops its backlog`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "oriel-drop-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    let line = String(repeating: "x", count: 999)
    try Data(String(repeating: line + "\n", count: 20000).utf8).write(to: file)
    let channel = try await localExec.run(["sh", "-c", TerminalStream.observeWrapper, "sh", "sh", "-c",
                                           ProcessExec.followScript, "sh", file.path, "0", "", "/^skip/"])
    var after = 0, closed = false
    for await text in channel.lines where text == line {
        if !closed {
            channel.closeInput()
            closed = true
            // A slow reader, as a relay over SSH: the kill lands while the pipes are full.
            try await Task.sleep(for: .milliseconds(500))
        }
        after += 1
    }
    // The pipes' buffers (32–65 lines), not the 20,000 lines.
    #expect(after < 10000)
}

/// A pi session can pass 100 MB: its backlog loads at `head`'s speed (0.9 s at a load of 15), not at macOS `tail`'s
/// 17 MB a second (5.3 s). The bound leaves room for a busier Mac.
@Test func `a big backlog loads fast`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "oriel-backlog-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(String(repeating: String(repeating: "x", count: 7999) + "\n", count: 10000).utf8).write(to: file)
    let start = ContinuousClock.now
    for await line in try await lineByLine(file.path, from: FileMark()) {
        if case .loaded = line {
            break
        }
    }
    #expect(ContinuousClock.now - start < .milliseconds(2500))
}

/// A burst written at once (150 turns of a long session) comes in one or two batches to a reader that is busy, as the
/// app is while it draws: not one batch per line, each of which would draw the chat again.
@Test func `a burst comes in few batches`() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "oriel-burst-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("a\n".utf8).write(to: file)
    var batches = try await localExec.follow(file.path, from: FileMark()).makeAsyncIterator()
    var lines = 0
    while lines < 1 {
        lines += try await batches.next()?.count(where: {
            if case .line = $0 {
                true
            } else {
                false
            }
        }) ?? 0
    }
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(String(repeating: #"{"type":"user","message":{"content":"Question"}}"# + "\n",
                                             count: 600).utf8))
    try handle.close()
    var count = 0
    while lines < 601, let batch = try await batches.next() {
        lines += batch.count
        count += 1
        // Busy: the rest of the burst comes meanwhile.
        try await Task.sleep(for: .milliseconds(300))
    }
    #expect(lines == 601 && count <= 2)
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

/// A recorded session with lines of the kinds its parser skips, in their real shapes: followed with the parser's
/// pattern, it gives the same history as the whole file, from fewer lines.
@Test(arguments: [
    ("claude-transcript", ClaudeTranscript.unread, [
        #"{"type":"api-request-blob","sessionId":"s","hash":"h","blob":"x"}"#,
        #"{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_success"},"type":"attachment"}"#,
    ]),
    ("codex-rollout", CodexRollout.unread, [
        #"{"timestamp":"2026-10-28T12:17:47Z","ordinal":5,"type":"response_item","payload":{"type":"message"}}"#,
    ]),
])
func `follow drops only what the parser skips`(name: String, unread: String, extra: [String]) async throws {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init) + extra
    let read = name == "codex-rollout" ? CodexRollout.read : ClaudeTranscript.read
    let file = FileManager.default.temporaryDirectory.appending(path: "oriel-unread-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: file) }
    try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: file)
    var whole = ChatHistory(), followed = ChatHistory(), count = 0
    lines.forEach { _ = read($0, &whole) }
    for await line in try await lineByLine(file.path, from: FileMark(), skip: unread) {
        if case .loaded = line {
            break
        }
        if case let .line(text, _) = line {
            _ = read(text, &followed)
            count += 1
        }
    }
    #expect(followed.entries.map(\.kind) == whole.entries.map(\.kind) && followed.model == whole.model)
    #expect(count <= lines.count - extra.count)
}
