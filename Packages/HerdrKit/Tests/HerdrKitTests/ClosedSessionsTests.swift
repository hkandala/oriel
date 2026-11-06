import Foundation
@testable import HerdrKit
import Testing

/// The four readers against fixture stores in a home folder of their own under /tmp, written as each agent writes
/// them (pi 0.80, Claude Code 2.1.310, Codex 0.164, OpenCode 1.18), in `Fixtures/closed-sessions`.
private struct Fixture {
    let home = URL(filePath: "/tmp/ovvi-closed-\(UUID().uuidString)")
    var exec: ProcessExec {
        ProcessExec(["HOME": home.path, "PATH": "/usr/bin:/bin"], herdr: nil, asked: .now)
    }

    /// A file under the home folder, last changed `age` seconds ago.
    func write(_ path: String, _ text: String, age: TimeInterval = 0) throws {
        let file = home.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)],
                                              ofItemAtPath: file.path)
    }

    /// A file of `Fixtures/closed-sessions` under the home folder, last changed `age` seconds ago.
    func copy(_ name: String, to path: String, age: TimeInterval) throws {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl",
                                                 subdirectory: "Fixtures/closed-sessions"))
        try write(path, String(contentsOf: url, encoding: .utf8), age: age)
    }

    func sql(_ path: String, _ statements: String) async throws {
        try FileManager.default.createDirectory(at: home.appending(path: path).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        _ = try await exec.checkedOutput(["sqlite3", home.appending(path: path).path, statements])
    }

    func remove() {
        try? FileManager.default.removeItem(at: home)
    }
}

@Test func `pi: newest first, its last name else its first prompt, paged, with no-prompt sessions left out`(
) async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let folder = ".pi/agent/sessions/--tmp-a--/"
    try fixture.copy("pi-prompt", to: folder + "1.jsonl", age: 60)
    try fixture.copy("pi-named", to: folder + "2.jsonl", age: 10)
    // Started and quit with no prompt.
    try fixture.write(folder + "3.jsonl", #"{"type":"session","version":3,"id":"01a3","cwd":"/tmp/a"}"#, age: 5)

    let first = try await fixture.exec.closedSessions(agent: "pi", offset: 0, limit: 2)
    let path = fixture.home.path + "/" + folder
    #expect(first.sessions.map(\.value) == [path + "2.jsonl"])
    #expect(first.sessions.map(\.title) == ["Trip notes"])
    #expect(first.sessions.first?.folder == "/tmp/a")
    #expect(first.more)
    let second = try await fixture.exec.closedSessions(agent: "pi", offset: 2, limit: 2)
    #expect(second.sessions.map(\.title) == [#"fix the "tab" drag please, café"#])
    #expect(!second.more)
    #expect(try await fixture.exec.closedSessions(agent: "pi", offset: 4, limit: 2) == ClosedPage())
}

@Test func `claude: a rename over its own title over the first typed prompt; the id is the file's name`(
) async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let renamed = "1b77b9f3-ed25-4373-964e-295a0158d7e8", plain = "2c88c0a4-fe36-4484-a75f-3a6b1269e8f9"
    try fixture.copy("claude-renamed", to: ".claude/projects/-tmp-b/\(renamed).jsonl", age: 100)
    try fixture.copy("claude-prompt", to: ".claude/projects/-tmp-c/\(plain).jsonl", age: 50)
    // A subagent's transcript is not a session.
    try fixture.write(".claude/projects/-tmp-c/\(plain)/subagents/agent-1.jsonl",
                      #"{"type":"user","message":{"role":"user","content":"sub"},"cwd":"/tmp/c"}"#)

    let page = try await fixture.exec.closedSessions(agent: "claude", offset: 0)
    #expect(page.sessions.map(\.value) == [plain, renamed])
    #expect(page.sessions.map(\.title) == ["write the docs", "say hi (Branch)"])
    #expect(page.sessions.map(\.folder) == ["/tmp/c", "/tmp/b"])
    #expect(!page.more)
}

@Test func `codex: its state database without subagents, exec runs and empty threads, else its rollouts`(
) async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    try await fixture.sql(".codex/state_5.sqlite", """
    create table threads (id text primary key, cwd text, title text, preview text, name text, source text,
      archived integer, recency_at_ms integer);
    insert into threads values
      ('019a-named', '/tmp/d', 'first prompt', 'first prompt', 'Renamed', 'cli', 0, 3000000),
      ('019b-plain', '/tmp/d', 'line one' || char(10) || 'line two', 'line one', null, 'vscode', 0, 2000000),
      ('019c-sub', '/tmp/d', 't', 'p', null, '{"subagent":"review"}', 0, 4000000),
      ('019d-exec', '/tmp/d', 't', 'p', null, 'exec', 0, 4000000),
      ('019e-empty', '/tmp/d', '', '', null, 'cli', 0, 4000000),
      ('019f-archived', '/tmp/d', 't', 'p', null, 'cli', 1, 4000000);
    """)
    let page = try await fixture.exec.closedSessions(agent: "codex", offset: 0)
    #expect(page.sessions.map(\.value) == ["019a-named", "019b-plain"])
    #expect(page.sessions.map(\.title) == ["Renamed", "line one line two"])
    #expect(page.sessions.first?.date == Date(timeIntervalSince1970: 3000))
    #expect(try await fixture.exec.closedSessions(agent: "codex", offset: 1, limit: 1).sessions.map(\.value)
        == ["019b-plain"])

    // No database (a machine with no sqlite3 reads the same way): the rollouts.
    try FileManager.default.removeItem(at: fixture.home.appending(path: ".codex/state_5.sqlite"))
    try fixture.write(".codex/session_index.jsonl", #"{"id":"0201-named","thread_name":"Named one","updated_at":"x"}"#)
    let day = ".codex/sessions/2026/11/01/"
    try fixture.copy("codex-named", to: day + "rollout-1-0201-named.jsonl", age: 30)
    try fixture.copy("codex-prompt", to: day + "rollout-2-0202-plain.jsonl", age: 20)
    try fixture.copy("codex-subagent", to: day + "rollout-3-0203-sub.jsonl", age: 10)
    let rollouts = try await fixture.exec.closedSessions(agent: "codex", offset: 0)
    #expect(rollouts.sessions.map(\.value) == ["0202-plain", "0201-named"])
    #expect(rollouts.sessions.map(\.title) == ["hello codex", "Named one"])
}

@Test func `opencode: top sessions with a title, and a machine with no sqlite3 says so`() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    try await fixture.sql(".local/share/opencode/opencode.db", """
    create table session (id text primary key, parent_id text, directory text, title text, time_updated integer,
      time_archived integer);
    insert into session values
      ('ses_new', null, '/tmp/f', 'Port the CLI', 9000, null),
      ('ses_old', null, '/tmp/g', 'Older', 5000, null),
      ('ses_child', 'ses_new', '/tmp/f', 'Child', 9500, null),
      ('ses_archived', null, '/tmp/f', 'Gone', 9600, 9700),
      ('ses_blank', null, '/tmp/f', 'New session - 2026-09-18T05:33:51.827Z', 9800, null);
    """)
    let page = try await fixture.exec.closedSessions(agent: "opencode", offset: 0)
    #expect(page.sessions.map(\.value) == ["ses_new", "ses_old"])
    #expect(page.sessions.map(\.folder) == ["/tmp/f", "/tmp/g"])
    #expect(page.sessions.first?.date == Date(timeIntervalSince1970: 9))

    // A PATH with a shell and no sqlite3.
    let bin = fixture.home.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: bin.appending(path: "sh"),
        withDestinationURL: URL(filePath: "/bin/sh"),
    )
    let bare = ProcessExec(["HOME": fixture.home.path, "PATH": bin.path], herdr: nil, asked: .now)
    let none = try await bare.closedSessions(agent: "opencode", offset: 0)
    #expect(none.problem == "needs sqlite3")
    #expect(none.sessions.isEmpty && !none.more)
}

@Test func `rows with an unsafe value or no folder are left out, and a cut escape still reads`() {
    let text = #"""
    {"t":1,"v":"x' or '1'='1","c":"/tmp","n":"bad id"}
    {"t":2,"v":"ok-1","c":"","n":"no folder"}
    {"t":3,"v":"ok-2","c":"/tmp","n":"  "}
    {"t":4,"v":"ok-3","c":"/tmp","n":"fine"}
    """#
    let page = ClosedSessions.parse(agent: "claude", text, limit: 4)
    #expect(page.sessions.map(\.value) == ["ok-3"])
    #expect(page.more)
    #expect(ClosedSessions.parse(agent: "pi", #"{"t":1,"v":"rel.jsonl","c":"/tmp","n":"x"}"#, limit: 50).sessions
        .isEmpty)
}

@Test func `perl cuts a title inside an escape to whole characters`() async throws {
    let script = ClosedSessions.perl + #" row(1, "v", "/tmp", "ab\\u00e9\\u00"); row(2, "v", "/tmp", "x\\ud83d");"#
    let text = try await localExec.output(["perl", "-e", script])
    #expect(ClosedSessions.parse(agent: "codex", text, limit: 50).sessions.map(\.title) == ["abé", "x"])
}

@Test func `the list shows only as far back as every agent with more pages was read`() {
    func page(_ agent: String, _ times: [Double], more: Bool) -> ClosedPage {
        var page = ClosedPage(sessions: times.map {
            ClosedSession(
                agent: agent,
                value: "\(agent)\(Int($0))",
                title: "t",
                folder: "/",
                date: Date(timeIntervalSince1970: $0),
            )
        }, more: more)
        (page.looked, page.oldest) = (times.count, times.last.map { Date(timeIntervalSince1970: $0) })
        return page
    }
    var list = ClosedList()
    list.add(page("codex", [90, 80], more: true), for: "codex")
    list.add(page("pi", [95, 50, 10], more: false), for: "pi")
    // pi's 50 waits: codex's next page may be newer.
    #expect(list.sessions(of: ["codex", "pi"]).map(\.value) == ["pi95", "codex90", "codex80"])
    #expect(list.next(of: ["codex", "pi"]) == ["codex"])
    #expect(list.sessions(of: ["pi"]).map(\.value) == ["pi95", "pi50", "pi10"])
    #expect(list.next(of: ["pi"]).isEmpty)
    list.add(page("codex", [60], more: false), for: "codex")
    #expect(list.sessions(of: ["codex", "pi"]).map(\.value) == [
        "pi95",
        "codex90",
        "codex80",
        "codex60",
        "pi50",
        "pi10",
    ])
    #expect(list.agents["codex"]?.looked == 3)
}
