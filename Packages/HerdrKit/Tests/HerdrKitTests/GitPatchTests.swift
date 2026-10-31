import Foundation
@testable import HerdrKit
import Testing

/// The files of a patch, as its `diff --git` lines name them.
private func files(_ patch: String) -> [String] {
    patch.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("diff --git ") }.map { String($0.dropFirst(11)) }
}

@Test func `the uncommitted patch has untracked files and odd names, a commit's its first parent's`() async throws {
    let repo = try await scratchRepo.value
    for exec in try await [localExec, RelayExec.start()] as [any Exec] {
        let patch = try await Git.patch(repo.path, commit: nil, exec: exec)
        #expect(files(patch) == [
            "a/crlf.txt b/crlf.txt", "a/sub/a.txt b/sub/a.txt", "a/sub/deep/sp ace.txt b/sub/moved/sp ace.txt",
            "a/bin.dat b/bin.dat", #""a/sub/line\nbreak" "b/sub/line\nbreak""#, "a/sub/new/f.txt b/sub/new/f.txt",
            #""a/sub/tab\t\"x" "b/sub/tab\t\"x""#,
        ])
        // A CR LF file's lines keep their CR; a binary file is named, not shown.
        #expect(patch.contains("-b\r\n+c\r\n") && patch.contains("Binary files /dev/null and b/bin.dat differ"))
        let merge = try await Git.log(repo.path, exec: exec)[0].hash
        #expect(try await files(Git.patch(repo.path, commit: merge, exec: exec)) == ["a/side.txt b/side.txt"])
        await #expect(throws: HerdrError.failed("No commit --all")) {
            try await Git.patch(repo.path, commit: "--all", exec: exec)
        }
    }
}

@Test func `the uncommitted patch before the first commit`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try await localExec.checkedOutput(["sh", "-c", #"cd "$1" && git init -q && echo a >f"#, "sh", folder.path])
    #expect(try await files(Git.patch(folder.path, commit: nil, exec: localExec)) == ["a/f b/f"])
}
