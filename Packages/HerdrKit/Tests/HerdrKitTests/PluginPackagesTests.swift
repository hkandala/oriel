import Foundation
@testable import HerdrKit
import Testing

/// npm never reaches the network here (`npm_config_offline`), and git none of the user's config.
private let offline = ProcessExec(localExec.environment.merging([
    "npm_config_offline": "true", "npm_config_userconfig": "/dev/null",
    "npm_config_cache": URL.temporaryDirectory.appending(path: "oriel-npm-cache").path,
    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
]) { $1 }, herdr: nil, asked: .now)

private func package(_ folder: URL, version: String, extra: [String: Any] = [:]) throws {
    let json: [String: Any] = [
        "name": "csv-table", "version": version, "description": "Tables",
        "oriel": ["id": "csv-table", "name": "CSV Table", "api": 1, "entry": "main.ts", "icon": "tablecells",
                  "permissions": ["files:read"]],
    ].merging(extra) { $1 }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: json).write(to: folder.appending(path: "package.json"))
    try Data("export default () => {}\n".utf8).write(to: folder.appending(path: "main.ts"))
}

@Test func `sources read as pi's, each with the folder it installs into`() {
    #expect(PluginSource("npm:@scope/csv-table@1.2.0") == .npm("@scope/csv-table@1.2.0"))
    #expect(PluginSource("npm:@scope/csv-table@1.2.0")?.folder == "csv-table")
    #expect(PluginSource("npm:csv-table@^1")?.folder == "csv-table")
    #expect(PluginSource("npm:csv-table")?.folder == "csv-table")
    #expect(PluginSource("npm:/tmp/csv-table-0.1.0.tgz")?.folder == "csv-table-0.1.0")
    #expect(PluginSource("npm:/Users/me/@work/csv.tgz")?.folder == "csv")
    #expect(PluginSource("git:github.com/x/node_modules")?.folder == nil)
    #expect(PluginSource("git:github.com/x/csv-table@v1") == .git(url: "https://github.com/x/csv-table", ref: "v1"))
    #expect(PluginSource("git:github.com/x/csv-table.git")?.folder == "csv-table")
    #expect(PluginSource("git:git@github.com:x/csv-table") == .git(url: "git@github.com:x/csv-table", ref: nil))
    #expect(PluginSource("https://github.com/x/csv-table") == .git(url: "https://github.com/x/csv-table", ref: nil))
    #expect(PluginSource("git:/tmp/repo@abc123") == .git(url: "/tmp/repo", ref: "abc123"))
    #expect(PluginSource("~/plugins/csv") == .local("~/plugins/csv"))
    #expect(PluginSource("./csv")?.folder == nil)
    // Nothing that reads as an option to npm or git, and no bare words.
    for bad in ["npm:", "npm:--global", "git:/tmp/repo@-x", "git:-u/x", "csv-table"] {
        #expect(PluginSource(bad) == nil, "\(bad)")
    }
}

@Test func `a git source installs at its ref, and an update puts the new clone over the old`() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let repo = scratch.appending(path: "csv-table"), plugins = scratch.appending(path: "plugins")
    try package(repo, version: "1.0.0")
    let git = ["git", "-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@t"]
    _ = try await offline.checkedOutput(["git", "init", "--quiet", repo.path])
    _ = try await offline.checkedOutput(git + ["add", "."])
    _ = try await offline.checkedOutput(git + ["commit", "--quiet", "-m", "one"])
    _ = try await offline.checkedOutput(git + ["tag", "v1"])
    try package(repo, version: "2.0.0")
    _ = try await offline.checkedOutput(git + ["commit", "--quiet", "-am", "two"])

    let pinned = try #require(PluginSource("git:\(repo.path)@v1"))
    let staged = try await PluginPackages.fetch(pinned, into: plugins, exec: offline)
    #expect(staged.manifest.version == "1.0.0")
    let folder = try await PluginPackages.finish(staged, into: plugins, exec: offline)
    #expect(folder == plugins.appending(path: "csv-table"))
    // Only the installed package is left in the plugins folder.
    #expect(try FileManager.default.contentsOfDirectory(atPath: plugins.path) == ["csv-table"])

    let latest = try await PluginPackages.fetch(#require(PluginSource("git:\(repo.path)")), into: plugins,
                                                exec: offline)
    _ = try await PluginPackages.finish(latest, into: plugins, exec: offline)
    let manifest = try PluginManifest(package: Data(contentsOf: folder.appending(path: "package.json")))
    #expect(manifest.version == "2.0.0")
    #expect(try FileManager.default.contentsOfDirectory(atPath: plugins.path) == ["csv-table"])
}

@Test func `an npm source installs with its dependencies in its own node_modules`() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let source = scratch.appending(path: "source"), plugins = scratch.appending(path: "plugins")
    // A dependency from the package's own files, and the host types as a peer, which must not install.
    try package(source, version: "1.0.0", extra: [
        "dependencies": ["pad": "file:vendor/pad"], "peerDependencies": ["@oriel/plugin-api": "*"],
    ])
    let pad = source.appending(path: "vendor/pad")
    try FileManager.default.createDirectory(at: pad, withIntermediateDirectories: true)
    try Data(#"{"name":"pad","version":"1.0.0","main":"index.js"}"#.utf8).write(to: pad.appending(path: "package.json"))
    try Data("module.exports = (s) => ` ${s}`\n".utf8).write(to: pad.appending(path: "index.js"))
    let packed = try await offline.checkedOutput(["sh", "-c", #"cd "$1" && npm pack --silent"#, "sh", source.path])
    let tarball = source.appending(path: packed.split(separator: "\n").last.map(String.init) ?? "").path

    let staged = try await PluginPackages.fetch(#require(PluginSource("npm:\(tarball)")), into: plugins,
                                                exec: offline)
    #expect(staged.manifest.id == "csv-table")
    let folder = try await PluginPackages.finish(staged, into: plugins, exec: offline)
    #expect(folder.lastPathComponent == "csv-table-1.0.0")
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "node_modules/pad/index.js").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "node_modules/@oriel").path))
}

@Test func `a package that is not a plugin is left out of the plugins folder`() async throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let repo = scratch.appending(path: "plain"), plugins = scratch.appending(path: "plugins")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try Data(#"{"name":"plain","version":"1.0.0"}"#.utf8).write(to: repo.appending(path: "package.json"))
    _ = try await offline.checkedOutput(["git", "init", "--quiet", repo.path])
    _ = try await offline.checkedOutput(["git", "-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@t", "add",
                                         "."])
    _ = try await offline.checkedOutput(["git", "-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@t",
                                         "commit", "--quiet", "-m", "one"])
    await #expect(throws: ManifestError.self) {
        try await PluginPackages.fetch(#require(PluginSource("git:\(repo.path)")), into: plugins, exec: offline)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: plugins.path).isEmpty)
}

@Test func `a build may read only the package's own files, links included`() throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let package = scratch.appending(path: "plugin"), modules = package.appending(path: "node_modules")
    try FileManager.default.createDirectory(at: modules.appending(path: ".pnpm/dep"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: modules.appending(path: "dep"),
                                               withDestinationURL: modules.appending(path: ".pnpm/dep"))
    try FileManager.default.createSymbolicLink(at: package.appending(path: "keys"), withDestinationURL: scratch)
    for file in ["main.ts", "node_modules/.pnpm/dep/index.js", "../secret.json"] {
        try Data().write(to: package.appending(path: file))
    }
    try PluginPackages.inside(package, ["main.ts", "node_modules/dep/index.js", "(disabled):fs", "<data:text/plain,a>"])
    for outside in ["../secret.json", "keys/secret.json", "../missing.js"] {
        #expect(throws: PluginError.self, "\(outside)") { try PluginPackages.inside(package, [outside]) }
    }
}

@Test func `the settings list keeps the file's other keys and each source once`() throws {
    let scratch = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let settings = scratch.appending(path: "oriel/settings.json")
    try PluginPackages.list("npm:a", in: settings, add: true)
    try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"theme":"x","packages":["./b",{"source":"npm:a"}]}"#.utf8).write(to: settings)
    try PluginPackages.list("npm:a", in: settings, add: true)
    #expect(PluginPackages.sources(settings) == ["./b", "npm:a"])
    try PluginPackages.list("./b", in: settings, add: false)
    #expect(PluginPackages.sources(settings) == ["npm:a"])
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
    #expect(json?["theme"] as? String == "x")
}
