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
}

@Test func `status letters from real porcelain`() {
    // `git status --porcelain=v1 -z` in a checkout with a staged rename, a conflict and odd names.
    let porcelain = " M sub/a.txt\0R  sub/de ep/f.txt\0sub/deep/f.txt\0UU both.txt\0AM new.txt\0?? sub/tab\tx\0"
        + "!! build/\0"
    #expect(Git.Change.parse(porcelain) == [
        Git.Change(letter: "M", path: "sub/a.txt", oldPath: nil),
        Git.Change(letter: "R", path: "sub/de ep/f.txt", oldPath: "sub/deep/f.txt"),
        Git.Change(letter: "C", path: "both.txt", oldPath: nil),
        Git.Change(letter: "A", path: "new.txt", oldPath: nil),
        Git.Change(letter: "U", path: "sub/tab\tx", oldPath: nil),
        Git.Change(letter: "!", path: "build/", oldPath: nil),
    ])
}

@Test func `root, status, log and graph of a repository, here and remote`() async throws {
    let repo = try await scratchRepo.value
    for exec in try await [localExec, RelayExec.start()] as [any Exec] {
        #expect(await Git.root(repo.path + "/sub", exec: exec) == repo.path)
        #expect(await Git.root("/", exec: exec) == nil)
        #expect(try await Git.status(repo.path, exec: exec).map { "\($0.letter) \($0.path)" } == [
            "M sub/a.txt", "R sub/moved/sp ace.txt", "U bin.dat", "U link", "U sub/line\nbreak", "U sub/new/f.txt",
            "U sub/tab\t\"x",
        ])
        let log = try await Git.log(repo.path, exec: exec)
        #expect(log.map(\.subject) == ["Merge branch 'side'", "main", "side", "two", "init"])
        #expect(log[0].parents == [log[1].hash, log[2].hash])
        #expect(log[4] == Git.Commit(hash: log[4].hash, parents: [], author: "t",
                                     date: Date(timeIntervalSince1970: 1_000_000_000), subject: "init"))
        // The side branch takes lane 1 from the merge down to where it forked.
        #expect(Git.graph(log) == [
            Git.GraphRow(lane: 0, children: [], parents: [0, 1], through: []),
            Git.GraphRow(lane: 0, children: [0], parents: [0], through: [1]),
            Git.GraphRow(lane: 1, children: [1], parents: [0], through: [0]),
            Git.GraphRow(lane: 0, children: [0], parents: [0], through: []),
            Git.GraphRow(lane: 0, children: [0], parents: [], through: []),
        ])
    }
}

@Test func `two branch tips and a parent two lanes wait for`() {
    let commit = { (hash: String, parents: [String]) in
        Git.Commit(hash: hash, parents: parents, author: "", date: .now, subject: "")
    }
    // b and c are tips; both have the parent a, which then frees lane 1.
    #expect(Git.graph([commit("c", ["a"]), commit("b", ["a"]), commit("a", [])]) == [
        Git.GraphRow(lane: 0, children: [], parents: [0], through: []),
        Git.GraphRow(lane: 1, children: [], parents: [0], through: [0]),
        Git.GraphRow(lane: 0, children: [0], parents: [], through: []),
    ])
}
