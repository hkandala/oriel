import Foundation
@testable import HerdrKit
import Testing

@Test func `git status gives the branch and its ahead and behind counts`() {
    let status = GitStatus(porcelain: """
    # branch.oid 1a2b3c4d5e6f7a8b9c0d
    # branch.head feature/rows
    # branch.upstream origin/feature/rows
    # branch.ab +2 -13
    1 .M N... 100644 100644 100644 abc abc file.swift
    """)
    #expect(status == GitStatus(branch: "feature/rows", ahead: 2, behind: 13))
}

@Test func `a detached head shows the short commit, no upstream counts zero`() {
    let status = GitStatus(porcelain: "# branch.oid 1a2b3c4d5e6f7a8b9c0d\n# branch.head (detached)\n")
    #expect(status == GitStatus(branch: "1a2b3c4", ahead: 0, behind: 0))
}

@Test func `output without a head line is no status`() {
    #expect(GitStatus(porcelain: "") == nil)
    #expect(GitStatus(porcelain: "fatal: not a git repository") == nil)
}

@Test func `reads a checkout's status and nothing outside one`() async {
    let exec = ProcessExec(ProcessInfo.processInfo.environment, herdr: nil, asked: .now)
    #expect(await GitStatus.of(URL(filePath: #filePath).deletingLastPathComponent().path, exec: exec) != nil)
    #expect(await GitStatus.of("/", exec: exec) == nil)
    #expect(await GitStatus.usable(exec: exec))
}

@Test func `status letters from real porcelain`() {
    // `git status --porcelain=v1 -z` in a checkout with a staged rename, a conflict and odd names.
    let porcelain = " M sub/a.txt\0R  sub/de ep/f.txt\0sub/deep/f.txt\0UU both.txt\0AM new.txt\0?? sub/tab\tx\0"
        + "!! build/\0C  copy.txt\0orig.txt\0?? \u{301}x\0"
    #expect(Git.Change.parse(porcelain) == [
        Git.Change(letter: "M", path: "sub/a.txt", oldPath: nil),
        Git.Change(letter: "R", path: "sub/de ep/f.txt", oldPath: "sub/deep/f.txt"),
        Git.Change(letter: "C", path: "both.txt", oldPath: nil),
        Git.Change(letter: "A", path: "new.txt", oldPath: nil),
        Git.Change(letter: "U", path: "sub/tab\tx", oldPath: nil),
        Git.Change(letter: "!", path: "build/", oldPath: nil),
        Git.Change(letter: "A", path: "copy.txt", oldPath: "orig.txt"),
        Git.Change(letter: "U", path: "\u{301}x", oldPath: nil),
    ])
}

@Test func `root, status, log and graph of a repository, here and remote`() async throws {
    let repo = try await scratchRepo.value
    for exec in try await [localExec, RelayExec.start()] as [any Exec] {
        #expect(await Git.root(repo.path + "/sub", exec: exec) == repo.path)
        #expect(await Git.root("/", exec: exec) == nil)
        #expect(try await Git.status(repo.path, exec: exec).map { "\($0.letter) \($0.path)" } == [
            "M crlf.txt", "M sub/a.txt", "R sub/moved/sp ace.txt", "U bin.dat", "U link", "U sub/line\nbreak",
            "U sub/new/f.txt",
            "U sub/tab\t\"x",
        ])
        let log = try await Git.log(repo.path, exec: exec)
        // Topological: the merged branch first.
        #expect(log.map(\.subject) == ["Merge branch 'side'", "side", "main", "two", "init"])
        #expect(log[0].parents == [log[2].hash, log[1].hash])
        #expect(log[4] == Git.Commit(hash: log[4].hash, parents: [], author: "t",
                                     date: Date(timeIntervalSince1970: 1_000_000_000), subject: "init"))
        #expect(log.map(\.refs) == [["HEAD -> refs/heads/main"], ["refs/heads/side"], [], [], []])
        // The side branch takes lane 1 from the merge down to where it forked; main stays in lane 0.
        #expect(Git.graph(log) == [
            Git.GraphRow(lane: 0, children: [], parents: [0, 1], through: []),
            Git.GraphRow(lane: 1, children: [1], parents: [1], through: [0]),
            Git.GraphRow(lane: 0, children: [0], parents: [0], through: [1]),
            Git.GraphRow(lane: 0, children: [0, 1], parents: [0], through: []),
            Git.GraphRow(lane: 0, children: [0], parents: [], through: []),
        ])
    }
}

@Test func `two branch tips and a parent two lanes wait for`() {
    let commit = { (hash: String, parents: [String]) in
        Git.Commit(hash: hash, parents: parents, author: "", date: .now, subject: "")
    }
    // b and c are tips; their lines meet at their parent a, in lane 0.
    #expect(Git.graph([commit("c", ["a"]), commit("b", ["a"]), commit("a", [])]) == [
        Git.GraphRow(lane: 0, children: [], parents: [0], through: []),
        Git.GraphRow(lane: 1, children: [], parents: [1], through: [0]),
        Git.GraphRow(lane: 0, children: [0, 1], parents: [], through: []),
    ])
}

@Test func `staged and unstaged changes from real porcelain`() {
    let porcelain = "MM both.txt\0R  new name\0old name\0 D gone.txt\0UU clash.txt\0?? new.txt\0!! build/\0"
        + "C  copy.txt\0orig.txt\0"
    let (staged, unstaged) = Git.Change.split(porcelain)
    #expect(staged == [
        Git.Change(letter: "M", path: "both.txt", oldPath: nil),
        Git.Change(letter: "R", path: "new name", oldPath: "old name"),
        Git.Change(letter: "A", path: "copy.txt", oldPath: "orig.txt"),
    ])
    #expect(unstaged.map { "\($0.letter) \($0.path)" } == ["M both.txt", "D gone.txt", "C clash.txt", "U new.txt"])
}

@Test func `stage, commit, push, fetch, pull and switch in a throwaway repository`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // Without the user's config: no signing, hooks or other defaults.
    var env = ProcessInfo.processInfo.environment
    env.merge(["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "t",
               "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"]) { $1 }
    let exec = ProcessExec(env, herdr: nil, asked: .now)
    let work = folder.path + "/work", other = folder.path + "/other"
    _ = try await exec.checkedOutput(["sh", "-c", #"""
    set -e; cd "$1"; git init -q --bare -b main remote.git; git clone -q remote.git work 2>/dev/null
    cd work; echo a >a; git add a; git commit -qm one; git push -q -u origin main 2>/dev/null
    cd ..; git clone -q remote.git other; cd work; git branch side; git push -q origin side 2>/dev/null; echo b >b
    """#, "sh", folder.path], timeout: .seconds(60))
    try await Git.run(work, ["add", "-A", "--", "b"], exec: exec)
    #expect(try await Git.changes(work, exec: exec).staged.map(\.path) == ["b"])
    try await Git.run(work, ["commit", "-m", "two"], exec: exec)
    #expect(try await Git.changes(work, exec: exec) == ([], []))
    try await Git.run(work, ["push"], exec: exec)
    try await Git.run(other, ["fetch", "--all"], exec: exec)
    #expect(try await Git.branches(other, exec: exec) == [
        Git.Branch(name: "main", remote: false, current: true),
        Git.Branch(name: "origin/side", remote: true, current: false),
    ])
    try await Git.run(other, ["pull"], exec: exec)
    #expect(try await Git.log(other, exec: exec).map(\.subject) == ["two", "one"])
    try await Git.run(other, ["switch", "side"], exec: exec)
    #expect(try await Git.branches(other, exec: exec).filter(\.current).map(\.name) == ["side"])
    // git's own words, not a prompt.
    let error = await #expect(throws: HerdrError.self) { try await Git.run(other, ["switch", "nope"], exec: exec) }
    #expect(error?.localizedDescription.contains("nope") == true)
}
