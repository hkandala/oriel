import Foundation
@testable import HerdrKit
import Testing

/// This repository's commit 0e6d450d (`git show -M -m --first-parent --format=` with Git.diff's flags): changes,
/// binary files added, a rename with changes and a deleted file.
@Test func `parses a real commit's patch`() throws {
    let url = try #require(Bundle.module.url(forResource: "show-0e6d450d", withExtension: "patch",
                                             subdirectory: "Fixtures"))
    let files = try DiffFile.parse(String(contentsOf: url, encoding: .utf8))
    #expect(files.map { "\($0.letter) \($0.path) +\($0.added) -\($0.removed)" } == [
        "M .github/workflows/docs-deploy.yml +0 -4",
        "M README.md +4 -4",
        "M docs/.gitignore +0 -1",
        "M docs/next.config.mjs +1 -1",
        "M docs/package.json +0 -2",
        "A docs/public/inspirations/cube-07-terminal-and-file-tree-screen.jpg +0 -0",
        "A docs/public/inspirations/one-08-agent-list-grouped-by-project.jpg +0 -0",
        "A docs/public/inspirations/rex-peek-01-single-terminal-glass-window.jpg +0 -0",
        "A docs/public/inspirations/rex-status-05-focused-vs-dimmed-pane.jpg +0 -0",
        "R docs/public/overview/index.html +10 -10",
        "D docs/scripts/copy-overview.mjs +0 -9",
    ])
    #expect(files[5].binary && !files[1].binary)
    #expect(files[9].oldPath == "resources/design.html")
    let hunk = files[1].hunks[0]
    #expect(hunk.header.hasPrefix("@@ -45,8 +45,8 @@ Packages/HerdrKit/"))
    let changed = hunk.lines.filter { $0.kind != .context }
    #expect(changed.map { "\($0.old ?? 0) \($0.new ?? 0)" } == ["48 0", "49 0", "0 48", "0 49"])
    #expect(hunk.lines.first?.old == 45 && hunk.lines.first?.new == 45)
    // Only the words the line gained.
    let gained = changed[2]
    #expect(changed[0].words.isEmpty)
    #expect(gained.words.map { (gained.text as NSString).substring(with: NSRange($0)) }
        == [", the overview in docs/public/overview/"])
}

@Test func `changed words, none when nothing is in common`() {
    #expect(DiffFile.words("let a = 1", "let bc = 1") == ([4 ..< 5], [4 ..< 6]))
    #expect(DiffFile.words("🙂 x", "🙂 y") == ([3 ..< 4], [3 ..< 4]))
    #expect(DiffFile.words("abc", "xyz") == ([], []))
}

@Test func `the uncommitted patch has untracked files and odd names, a commit's its first parent's`() async throws {
    let repo = try await scratchRepo.value
    for exec in try await [localExec, RelayExec.start()] as [any Exec] {
        let files = try await Git.diff(repo.path, commit: nil, exec: exec)
        #expect(files.map { "\($0.letter) \($0.oldPath ?? "")>\($0.path) \($0.binary)" } == [
            "M >sub/a.txt false", "R sub/deep/sp ace.txt>sub/moved/sp ace.txt false", "A >bin.dat true",
            "A >sub/line\nbreak false", "A >sub/new/f.txt false", "A >sub/tab\t\"x false",
        ])
        #expect(files[0].hunks.flatMap(\.lines).map(\.text) == ["a", "m", "c"])
        let merge = try await Git.log(repo.path, exec: exec)[0].hash
        #expect(try await Git.diff(repo.path, commit: merge, exec: exec).map(\.path) == ["side.txt"])
        await #expect(throws: HerdrError.failed("No commit --all")) {
            try await Git.diff(repo.path, commit: "--all", exec: exec)
        }
    }
}
