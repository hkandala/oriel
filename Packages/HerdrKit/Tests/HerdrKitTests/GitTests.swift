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
