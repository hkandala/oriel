import Foundation
@testable import HerdrKit
import Testing

/// Every permission, on This Mac.
private let all = PluginCalls(permissions: ["files:read", "files:write", "git", "run", "clipboard"], exec: localExec,
                              remote: false, gitRuns: true)

/// The call's reply as JSON values.
private func call(_ name: String, _ args: [String: Any], _ calls: PluginCalls = all) async throws -> Any? {
    let data = try await calls.call(name, JSONSerialization.data(withJSONObject: args))
    return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
}

/// The call's error code.
private func failure(_ name: String, _ args: [String: Any], _ calls: PluginCalls = all) async -> String? {
    do {
        _ = try await call(name, args, calls)
        return nil
    } catch let error as PluginError {
        return error.code
    } catch {
        return "\(error)"
    }
}

@Test func `a call outside the manifest's permissions is denied before it runs`() async {
    let none = PluginCalls(permissions: [], exec: localExec, remote: false, gitRuns: true)
    for (name, permission) in [
        ("files.read", "files:read"),
        ("files.list", "files:read"),
        ("files.watch", "files:read"),
        ("files.write", "files:write"),
        ("git.status", "git"),
        ("git.commit", "git"),
        ("run", "run"),
        ("clipboard.write", "clipboard"),
    ] {
        #expect(PluginCalls.permission(name) == permission)
        #expect(await failure(name, ["path": "/tmp"], none) == "denied")
    }
    #expect(PluginCalls.permission("toast") == nil)
    let reader = PluginCalls(permissions: ["files:read"], exec: localExec, remote: false, gitRuns: true)
    #expect(await failure("files.write", ["path": "/tmp/x", "text": ""], reader) == "denied")
}

@Test func `files read, write by hash, and say what is wrong`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "a.txt").path
    let written = try #require(await call("files.write", ["path": file, "text": "\u{FEFF}héllo\n"]) as? [String: Any])
    let read = try #require(await call("files.read", ["path": file]) as? [String: Any])
    #expect(read["text"] as? String == "héllo\n")
    // The byte order mark goes to the page (JSONSerialization drops it on reading only).
    let raw = try await all.call("files.read", JSONSerialization.data(withJSONObject: ["path": file]))
    #expect(raw.contains(0xEF))
    #expect(read["hash"] as? String == written["hash"] as? String)
    #expect(read["writable"] as? Bool == true)
    // A save over an old hash changes nothing.
    _ = try await call("files.write", ["path": file, "text": "two", "over": #require(read["hash"] as? String)])
    #expect(await failure("files.write", ["path": file, "text": "three", "over": read["hash"] ?? ""]) == "changed")
    #expect(try String(contentsOfFile: file, encoding: .utf8) == "two")

    try Data([0xFF, 0x00, 0x01]).write(to: folder.appending(path: "b.png"))
    let png = folder.appending(path: "b.png").path
    #expect(await failure("files.read", ["path": png]) == "notText")
    let bytes = try #require(await call("files.readBytes", ["path": png]) as? [String: Any])
    #expect(bytes["base64"] as? String == "/wAB")
    #expect(bytes["type"] as? String == "image/png")
    _ = try await call("files.write", ["path": png, "base64": "AQID"])
    #expect(try Data(contentsOf: URL(filePath: png)) == Data([1, 2, 3]))

    #expect(await failure("files.read", ["path": folder.appending(path: "none").path]) == "notFound")
    #expect(await failure("files.read", ["path": "a.txt"]) == "failed")
    #expect(await failure("files.read", ["path": "-x"]) == "failed")
}

@Test func `files info, list and paths, with git's ignored files`() async throws {
    let repo = try await scratchRepo.value
    let info = try #require(await call("files.info", ["path": repo.appending(path: "two.txt").path]) as? [String: Any])
    #expect(info["name"] as? String == "two.txt")
    #expect(info["size"] as? Int == 4)
    let read = try #require(await call("files.read", ["path": repo.appending(path: "two.txt").path]) as? [String: Any])
    #expect(info["hash"] as? String == read["hash"] as? String)
    #expect(info["folder"] as? Bool == false)
    #expect(info["type"] as? String == "public.plain-text")
    let folder = try #require(await call("files.info", ["path": repo.appending(path: "sub").path]) as? [String: Any])
    #expect(folder["folder"] as? Bool == true)
    #expect(await failure("files.info", ["path": repo.appending(path: "none").path]) == "notFound")

    let entries = try #require(await call("files.list", ["path": repo.path]) as? [[String: Any]])
    let build = try #require(entries.first { $0["name"] as? String == "build" })
    #expect(build["folder"] as? Bool == true && build["ignored"] as? Bool == true)
    #expect(entries.contains { $0["name"] as? String == "two.txt" && $0["ignored"] as? Bool == false })
    // Inside the repository, not at its root: still git's.
    let sub = try #require(await call("files.list", ["path": repo.appending(path: "build").path]) as? [[String: Any]])
    #expect(sub.first?["ignored"] as? Bool == true)

    let paths = try #require(await call("files.paths", ["path": repo.path]) as? [String])
    #expect(paths.contains("two.txt") && !paths.contains("build/out"))
}

@Test func `git reads: root, status, changes, head, branches, log and diff`() async throws {
    let repo = try await scratchRepo.value
    #expect(try await call("git.root", ["folder": repo.appending(path: "sub").path]) as? String == repo.path)
    #expect(try await call("git.root", ["folder": "/"]) is NSNull)
    let status = try #require(await call("git.status", ["root": repo.path]) as? [[String: Any]])
    #expect(status.contains { $0["path"] as? String == "sub/a.txt" && $0["letter"] as? String == "M" })
    let changes = try #require(await call("git.changes", ["root": repo.path]) as? [String: [[String: Any]]])
    #expect(changes["staged"]?.contains { $0["letter"] as? String == "R" && $0["oldPath"] != nil } == true)
    #expect(changes["unstaged"]?.contains { $0["path"] as? String == "sub/a.txt" } == true)
    let head = try #require(await call("git.head", ["root": repo.path]) as? [String: Any])
    #expect(head["branch"] as? String == "main")
    // Sorted keys: the same reply is the same text every time.
    let raw = try await all.call("git.head", JSONSerialization.data(withJSONObject: ["root": repo.path]))
    #expect(String(decoding: raw, as: UTF8.self) == #"{"ahead":0,"behind":0,"branch":"main"}"#)
    let branches = try #require(await call("git.branches", ["root": repo.path]) as? [[String: Any]])
    #expect(branches.compactMap { $0["name"] as? String } == ["main", "side"])
    let log = try #require(await call("git.log", ["root": repo.path, "limit": 2]) as? [[String: Any]])
    #expect(log.count == 2)
    #expect(log.first?["parents"] as? [Int] == [0, 1])
    #expect(log.first?["date"] as? Double == 1_000_000_400_000)
    let patch = try #require(await call("git.diff", ["root": repo.path, "source": "uncommitted"]) as? String)
    #expect(patch.contains("diff --git a/sub/a.txt b/sub/a.txt"))
    #expect(await failure("git.diff", ["root": repo.path, "source": "-x"]) == "failed")
    let none = PluginCalls(permissions: ["git"], exec: localExec, remote: false, gitRuns: false)
    #expect(await failure("git.status", ["root": repo.path], none) == "failed")
}

@Test func `git writes: stage, unstage, commit, switch, and a remote's fetch, push and pull`() async throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try await localExec.checkedOutput(["sh", "-c", #"""
    set -e; cd "$1"; git init -q --bare remote.git; git init -q -b main work; cd work
    git config user.name t; git config user.email t@t; git remote add origin ../remote.git
    echo a >'*.txt'; echo b >b.txt
    """#, "sh", folder.path])
    let root = folder.appending(path: "work").path
    func changes() async throws -> [String: [String]] {
        let json = try #require(await call("git.changes", ["root": root]) as? [String: [[String: Any]]])
        return json.mapValues { $0.compactMap { $0["path"] as? String } }
    }
    // A path, not a pattern.
    _ = try await call("git.stage", ["root": root, "paths": ["*.txt"]])
    #expect(try await changes() == ["staged": ["*.txt"], "unstaged": ["b.txt"]])
    _ = try await call("git.stage", ["root": root])
    _ = try await call("git.unstage", ["root": root, "paths": ["b.txt"]])
    #expect(try await changes() == ["staged": ["*.txt"], "unstaged": ["b.txt"]])
    #expect(await failure("git.commit", ["root": root, "message": "  "]) == "failed")
    _ = try await call("git.commit", ["root": root, "message": "one\n"])
    _ = try await call("git.push", ["root": root])
    _ = try await call("git.fetch", ["root": root])
    _ = try await call("git.pull", ["root": root])
    let head = try #require(await call("git.head", ["root": root]) as? [String: Any])
    #expect(head["ahead"] as? Int == 0)
    _ = try await localExec.checkedOutput(["git", "-C", root, "branch", "-q", "other"])
    _ = try await call("git.switch", ["root": root, "branch": "other"])
    #expect(try await call("git.head", ["root": root]).flatMap { $0 as? [String: Any] }?["branch"] as? String
        == "other")
    // Never an option: `--detach` would work.
    #expect(await failure("git.switch", ["root": root, "branch": "--detach"]) == "failed")
    #expect(try await call("git.head", ["root": root]).flatMap { $0 as? [String: Any] }?["branch"] as? String
        == "other")
    // git's message, never a password prompt.
    #expect(await failure("git.switch", ["root": root, "branch": "none"]) == "failed")
}

@Test func `run gives the exit code, stdout and stderr in its folder, with stdin, and stops at its timeout`(
) async throws {
    let reply = try #require(await call("run", ["argv": ["sh", "-c", "pwd; cat; echo err >&2; exit 3"],
                                                "cwd": "/usr", "stdin": "a b\nc\n"]) as? [String: Any])
    #expect(reply["code"] as? Int == 3)
    #expect(reply["stdout"] as? String == "/usr\na b\nc\n")
    #expect(reply["stderr"] as? String == "err\n")
    #expect(reply["truncated"] as? Bool == false)
    // argv, not a shell line.
    let echo = try #require(await call("run", ["argv": ["echo", "$HOME;", "x"], "cwd": "/"]) as? [String: Any])
    #expect(echo["stdout"] as? String == "$HOME; x\n")
    #expect(await failure("run", ["argv": ["sleep", "5"], "cwd": "/", "timeout": 200]) == "timeout")
    #expect(await failure("run", ["argv": [], "cwd": "/"]) == "failed")
    #expect(await failure("run", ["argv": ["true"], "cwd": "."]) == "failed")
    let long = try #require(await call("run", ["argv": ["sh", "-c", "yes 0123456789abcdef | head -c 5000000"],
                                               "cwd": "/"]) as? [String: Any])
    #expect(long["truncated"] as? Bool == true)
    #expect((long["stdout"] as? String)?.utf8.count ?? 0 < 4 << 20)
}
