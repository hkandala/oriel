import Foundation
@testable import HerdrKit
import Testing

/// A new folder in the temporary folder, removed by the caller.
func scratchFolder() throws -> URL {
    let folder = URL.temporaryDirectory.appending(path: "oriel-files-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // git's paths: `/private/var`, not `/var`.
    return try URL(filePath: #require(folder.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath))
}

/// A repository with a merge and every kind of change uncommitted, built once by real git without the user's config;
/// the tests only read it. It stays in the temporary folder: building one per test took minutes on a loaded Mac.
let scratchRepo = Task { try await makeScratchRepo() }

private func makeScratchRepo() async throws -> URL {
    let folder = try scratchFolder()
    _ = try await localExec.checkedOutput(["sh", "-c", #"""
    set -e; cd "$1"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
      GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    at() { export GIT_AUTHOR_DATE="$1 +0000" GIT_COMMITTER_DATE="$1 +0000"; }
    git init -q -b main
    mkdir -p sub/deep build
    printf 'a\n' >sub/a.txt; printf 'b\n' >'sub/deep/sp ace.txt'; printf 'build/\n*.log\n' >.gitignore
    echo x >build/out; echo y >err.log; printf 'a\r\nb\r\n' >crlf.txt
    git add -A; at 1000000000; git commit -qm init
    echo two >two.txt; git add -A; at 1000000100; git commit -qm two
    git checkout -qb side; echo s >side.txt; git add -A; at 1000000200; git commit -qm side
    git checkout -q main; echo m >>sub/a.txt; at 1000000300; git commit -qam main
    at 1000000400; git merge -q --no-ff --no-edit side
    printf 'a\nc\n' >sub/a.txt; printf 'a\r\nc\r\n' >crlf.txt
    git mv sub/deep sub/moved
    mkdir sub/new; echo n >sub/new/f.txt
    echo q >'sub/tab	"x'; printf 'l\n' >'sub/line
    break'
    printf '\000\001' >bin.dat; ln -s sub link
    """#, "sh", folder.path], timeout: .seconds(120))
    return folder
}

private func execs() async throws -> [any Exec] {
    try await [localExec, RelayExec.start()]
}

@Test func `lists a folder with git letters and ignored files, here and remote`() async throws {
    let repo = try await scratchRepo.value
    for exec in try await execs() {
        let root = try await Files.list(repo.path, repo: repo.path, exec: exec)
        #expect(root == [
            FileEntry(name: "build", isFolder: true, letter: nil, ignored: true),
            FileEntry(name: "link", isFolder: true, letter: "U", ignored: false),
            FileEntry(name: "sub", isFolder: true, letter: "M", ignored: false),
            FileEntry(name: ".gitignore", isFolder: false, letter: nil, ignored: false),
            FileEntry(name: "bin.dat", isFolder: false, letter: "U", ignored: false),
            FileEntry(name: "crlf.txt", isFolder: false, letter: "M", ignored: false),
            FileEntry(name: "err.log", isFolder: false, letter: nil, ignored: true),
            FileEntry(name: "side.txt", isFolder: false, letter: nil, ignored: false),
            FileEntry(name: "two.txt", isFolder: false, letter: nil, ignored: false),
        ])
        let sub = try await Files.list(repo.path + "/sub", repo: repo.path, exec: exec)
        #expect(sub == [
            FileEntry(name: "moved", isFolder: true, letter: "R", ignored: false),
            FileEntry(name: "new", isFolder: true, letter: "U", ignored: false),
            FileEntry(name: "a.txt", isFolder: false, letter: "M", ignored: false),
            FileEntry(name: "line\nbreak", isFolder: false, letter: "U", ignored: false),
            FileEntry(name: "tab\t\"x", isFolder: false, letter: "U", ignored: false),
        ])
        // Inside an untracked folder git names only the folder.
        #expect(try await Files.list(repo.path + "/sub/new", repo: repo.path, exec: exec)
            == [FileEntry(name: "f.txt", isFolder: false, letter: "U", ignored: false)])
        // No repository, no git.
        #expect(try await Files.list(repo.path + "/sub", repo: nil, exec: exec).allSatisfy { $0.letter == nil })
        await #expect(throws: HerdrError.self) { try await Files.list(repo.path + "/none", repo: nil, exec: exec) }
    }
}

@Test func `every file for the filter, git's or all`() async throws {
    let repo = try await scratchRepo.value
    for exec in try await execs() {
        #expect(try await Files.paths(repo.path, repo: repo.path, exec: exec).sorted() == [
            ".gitignore", "bin.dat", "crlf.txt", "link", "side.txt", "sub/a.txt", "sub/line\nbreak",
            "sub/moved/sp ace.txt",
            "sub/new/f.txt", "sub/tab\t\"x", "two.txt",
        ])
        let all = try await Files.paths(repo.path + "/sub", repo: nil, exec: exec)
        #expect(all.sorted() == ["a.txt", "line\nbreak", "moved/sp ace.txt", "new/f.txt", "tab\t\"x"])
    }
}

@Test func `reads and saves bytes whole, checked by hash, here and remote`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for exec in try await execs() {
        let file = folder.appending(path: "it's a\nfile")
        let bytes = Data((0 ..< 100_001).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: file.path)
        let read = try await Files.read(file.path, exec: exec)
        #expect(read.data == bytes)

        let edited = Data("new\u{0}text\n".utf8)
        let hash = try await Files.save(edited, to: file.path, replacing: read.hash, exec: exec)
        #expect(try Data(contentsOf: file) == edited)
        #expect(try await Files.read(file.path, exec: exec) == FileContents(data: edited, hash: hash))
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o751)
        // The old hash: the disk changed since.
        await #expect(throws: FileError.changed) {
            try await Files.save(Data(), to: file.path, replacing: read.hash, exec: exec)
        }
        #expect(try Data(contentsOf: file) == edited)
        // A save whose stdin ended early writes nothing.
        let chunks = base64Lines(Data(repeating: 7, count: 100_000))
        await #expect(throws: HerdrError.failed("The save was cut short")) {
            try await exec.checkedOutput(["sh", "-c", Files.saveScript, "sh", file.path, hash, "100000"],
                                         input: chunks.dropLast())
        }
        #expect(try Data(contentsOf: file) == edited)
        // Overwrite: no hash, no check.
        try Data("theirs".utf8).write(to: file)
        let mine = try await Files.save(edited, to: file.path, replacing: nil, exec: exec)
        #expect(try await Files.read(file.path, exec: exec) == FileContents(data: edited, hash: mine))

        // A link stays a link; an empty file saves and reads.
        let link = folder.appending(path: "link")
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        _ = try await Files.save(Data(), to: link.path, replacing: mine, exec: exec)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == file.path)
        #expect(try await Files.read(link.path, exec: exec).data.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["it's a\nfile", "link"])
    }
}

@Test func `a file over the view limit gives its size, a folder is no file`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "big")
    FileManager.default.createFile(atPath: file.path, contents: nil)
    try FileHandle(forWritingTo: file).truncate(atOffset: UInt64(Files.viewLimit + 1))
    for exec in try await execs() {
        await #expect(throws: FileError.tooLarge(Files.viewLimit + 1)) { try await Files.read(file.path, exec: exec) }
        #expect(try await Files.size(file.path, exec: exec) == Files.viewLimit + 1)
        await #expect(throws: HerdrError.failed("Not a file")) { try await Files.read(folder.path, exec: exec) }
    }
}

/// Writes to the file (a new file in the folder) until the stream yields: the watcher starts on its own task.
private func yields(_ changes: AsyncStream<Void>, writing file: URL) async throws {
    let writer = Task {
        while !Task.isCancelled {
            try? Data(UUID().uuidString.utf8)
                .write(to: file.hasDirectoryPath ? file.appending(path: UUID().uuidString) : file)
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
    defer { writer.cancel() }
    let changed = try await withTimeout(.seconds(10), onTimeout: {}, { await changes.first { true } != nil })
    #expect(changed)
}

@Test func `watches a file here, also after an editor replaced it`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "f")
    try Data().write(to: file)
    let changes = Files.watch(file.path, exec: localExec)
    try await yields(changes, writing: file)
    // `.atomic` writes a new file and renames it over the old one; a watcher on the old file may still get two
    // events, the third comes only from the new file.
    try Data("x".utf8).write(to: file, options: .atomic)
    #expect(await changes.first { true } != nil)
    try await yields(changes, writing: file)
    try await yields(changes, writing: file)
}

@Test func `watches a file that comes later, and everything under a folder`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // Its folder too.
    let later = folder.appending(path: "later/f")
    for exec in try await execs() {
        try? FileManager.default.removeItem(at: later.deletingLastPathComponent())
        let changes = Files.watch(later.path, exec: exec)
        try FileManager.default.createDirectory(
            at: later.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try await yields(changes, writing: later)
    }
    let inner = folder.appending(path: "a/b")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    try Data().write(to: inner.appending(path: "f"))
    try await yields(Files.watch(folder.path, exec: localExec), writing: inner.appending(path: "f"))
    // Remote: the folder's own entries and git's view.
    try await yields(Files.watch(folder.path, exec: RelayExec.start()), writing: URL(filePath: folder.path + "/"))
}

@Test func `a remote folder's poll sees an edit to a file already changed`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try await localExec.checkedOutput(["sh", "-c", """
    cd "$1" && git init -q && echo a >f && git add f && git -c user.name=t -c user.email=t@t commit -qm f && echo b >f
    """, "sh", folder.path])
    // `git status` says ` M f` before and after each write.
    try await yields(Files.watch(folder.path, exec: RelayExec.start()), writing: folder.appending(path: "f"))
}

@Test func `polls a remote file every 2 s`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "f")
    try Data().write(to: file)
    try await yields(Files.watch(file.path, exec: RelayExec.start()), writing: file)
}
