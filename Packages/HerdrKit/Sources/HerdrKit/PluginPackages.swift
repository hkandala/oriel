import Foundation

/// A plugin package's source in `settings.json`'s `packages`, as pi's (future-work/plugins, decision 5):
/// `npm:<spec>` (`npm:@scope/name@1.2.0`), `git:<repository>[@ref]` (`git:github.com/x/y@v1`, also a URL or a local
/// repository's path), or a local path, which loads in place and is never installed or changed.
public enum PluginSource: Equatable, Sendable {
    case npm(String)
    case git(url: String, ref: String?)
    case local(String)

    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("npm:") {
            let spec = String(text.dropFirst(4))
            guard !spec.isEmpty, !spec.hasPrefix("-") else { return nil }
            self = .npm(spec)
        } else if text.hasPrefix("git:") || ["https://", "http://", "ssh://"].contains(where: text.hasPrefix) {
            var url = text.hasPrefix("git:") ? String(text.dropFirst(4)) : text
            var ref: String?
            // The ref is the last part's `@…`: `git@host:x/y` has its `@` in the host.
            if let slash = url.lastIndex(of: "/"), let sign = url[slash...].lastIndex(of: "@") {
                ref = String(url[url.index(after: sign)...])
                url = String(url[..<sign])
            }
            guard !url.isEmpty, !url.hasPrefix("-"), ref?.hasPrefix("-") != true, ref?.isEmpty != true else {
                return nil
            }
            if !url.contains("://"), !url.hasPrefix("/"), !url.hasPrefix("git@") {
                url = "https://" + url
            }
            self = .git(url: url, ref: ref)
        } else if ["/", "~", "."].contains(text.prefix(1)) {
            self = .local(text)
        } else {
            return nil
        }
    }

    /// The folder in the plugins folder an npm or git source installs into: the package's or the repository's last
    /// name (a tarball's file name). Nil for a local path.
    public var folder: String? {
        let name: Substring
        switch self {
        case let .npm(spec):
            // A tarball's path, `@scope/name@range` or `name@range`.
            let path = ["/", ".", "~"].contains(spec.prefix(1)) || spec.hasPrefix("file:")
            let bare = path ? Substring(spec)
                : spec.dropFirst().split(separator: "@", maxSplits: 1).first.map { spec.prefix(1) + $0 } ?? ""
            name = (bare.split(separator: "/").last ?? "").replacing(/\.(tgz|tar\.gz)$/, with: "")
        case let .git(url, _):
            name = (url.split(separator: "/").last ?? "").replacing(/\.git$/, with: "")
        case .local: return nil
        }
        // The plugins folder's `node_modules` holds the host types package.
        return name.isEmpty || name.hasPrefix(".") || name == "node_modules" ? nil : String(name)
    }
}

/// Install, update and remove of plugin packages from npm and git into the plugins folder, with the npm, pnpm or bun
/// on the login `PATH` (the app ships no package manager), and the `packages` list of `settings.json`.
public enum PluginPackages {
    /// A package fetched into a folder of its own in the plugins folder, its manifest read before any of its code or
    /// scripts ran: the trust prompt shows it, then `finish` or `discard`.
    public struct Staged: Sendable {
        public let source: PluginSource
        public let manifest: PluginManifest
        /// The package's folder.
        public let folder: URL
        let staging: URL
    }

    /// Fetches an npm or git source: `npm pack` and its tarball unpacked, or a clone at the ref. No scripts run.
    public static func fetch(_ source: PluginSource, into plugins: URL, exec: any Exec) async throws -> Staged {
        guard source.folder != nil else { throw HerdrError.failed("A local path is not installed") }
        let staging = plugins.appending(path: ".install-\(UUID().uuidString)")
        let folder = staging.appending(path: "package")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            switch source {
            case let .npm(spec):
                guard await exec.succeeds("command -v npm", []) else {
                    throw HerdrError.failed("Installing from npm needs npm on your PATH")
                }
                let packed = try await exec.checkedOutput(["npm", "pack", spec, "--pack-destination", staging.path,
                                                           "--json", "--ignore-scripts"], timeout: .seconds(300))
                let json = try? JSONSerialization.jsonObject(with: Data(packed.utf8)) as? [[String: Any]]
                guard let file = json?.first?["filename"] as? String else {
                    throw HerdrError.failed("npm pack printed no package")
                }
                // A scoped package's tarball name has no folder in it.
                let tarball = staging.appending(path: (file as NSString).lastPathComponent).path
                _ = try await exec.checkedOutput(["tar", "-xzf", tarball, "-C", staging.path])
                try? FileManager.default.removeItem(atPath: tarball)
            case let .git(url, ref):
                let git = ["env", "GIT_TERMINAL_PROMPT=0", "git"]
                _ = try await exec.checkedOutput(git + ["clone", "--quiet", "--", url, folder.path],
                                                 timeout: .seconds(300))
                if let ref {
                    _ = try await exec.checkedOutput(git + ["-C", folder.path, "checkout", "--quiet", ref, "--"])
                }
            case .local: break
            }
            let manifest = try PluginManifest(package: Data(contentsOf: folder.appending(path: "package.json")))
            return Staged(source: source, manifest: manifest, folder: folder, staging: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Installs its dependencies and puts it in place as the source's folder, over an older install. Its path.
    public static func finish(_ staged: Staged, into plugins: URL, exec: any Exec) async throws -> URL {
        defer { discard(staged) }
        try await dependencies(staged.folder, exec: exec)
        guard let name = staged.source.folder else { throw HerdrError.failed("A local path is not installed") }
        let target = plugins.appending(path: name)
        try place(staged.folder, at: target, keeping: staged.staging)
        return target
    }

    /// Moves a folder over `target`; the old one waits in `staging` until the move worked, else it goes back.
    public static func place(_ folder: URL, at target: URL, keeping staging: URL) throws {
        let files = FileManager.default, old = staging.appending(path: "old"),
            had = files.fileExists(atPath: target.path)
        if had {
            try files.moveItem(at: target, to: old)
        }
        do {
            try files.moveItem(at: folder, to: target)
        } catch {
            if had {
                try? files.moveItem(at: old, to: target)
            }
            throw error
        }
    }

    public static func discard(_ staged: Staged) {
        try? FileManager.default.removeItem(at: staged.staging)
    }

    /// The package's `dependencies` and `devDependencies` in its own `node_modules`, from its lockfile when it has
    /// one: with the manager of its lockfile, else the first of npm, pnpm and bun on the `PATH`. No scripts run, and
    /// no peer dependencies install: `@oriel/plugin-api` is the app's.
    public static func dependencies(_ folder: URL, exec: any Exec) async throws {
        let json = try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "package.json")))
            as? [String: Any]
        let deps = ["dependencies", "devDependencies"].contains { !((json?[$0] as? [String: Any]) ?? [:]).isEmpty }
        guard deps else { return }
        let has = { (name: String) in FileManager.default.fileExists(atPath: folder.appending(path: name).path) }
        let locked = has("package-lock.json") ? "npm" : has("pnpm-lock.yaml") ? "pnpm"
            : has("bun.lock") || has("bun.lockb") ? "bun" : nil
        var found: String?
        for manager in [locked].compactMap(\.self) + ["npm", "pnpm", "bun"] where found == nil {
            if await exec.succeeds("command -v \"$1\"", [manager]) {
                found = manager
            }
        }
        let frozen = found == locked
        let argv: [String] = switch found {
        case "npm": ["npm", frozen ? "ci" : "install", "--no-audit", "--no-fund", "--ignore-scripts",
                     "--legacy-peer-deps"]
        case "pnpm": ["pnpm", "install", frozen ? "--frozen-lockfile" : "--no-frozen-lockfile", "--ignore-scripts",
                      "--config.auto-install-peers=false"]
        case "bun": ["bun", "install", "--ignore-scripts", "--omit=peer"] + (frozen ? ["--frozen-lockfile"] : [])
        default: throw HerdrError.failed("Oriel installs a plugin's dependencies with npm, pnpm or bun, and none is "
                + "on your PATH")
        }
        _ = try await exec.checkedOutput(["sh", "-c", #"cd "$1" && shift && exec "$@""#, "sh", folder.path] + argv,
                                         timeout: .seconds(600))
    }

    /// A build reads the plugin's own files and `node_modules` only (decision 5): esbuild resolves an import from a
    /// parent's `node_modules` or a `../` path, and would bundle any file of the Mac into a page with no permissions.
    /// `paths` are relative to the package; a link counts by where it leads (pnpm's lead into the package's own
    /// `node_modules`).
    public static func inside(_ package: URL, _ paths: [String]) throws(PluginError) {
        /// `realpath`, not `resolvingSymlinksInPath`, which drops `/private` only from paths that exist.
        func real(_ url: URL) -> String? {
            realpath(url.path, nil).map { path in
                defer { free(path) }
                return String(cString: path)
            }
        }
        let root = (real(package) ?? package.path) + "/"
        // esbuild's modules that are no file: `(disabled):fs`, `<data:…>`.
        let files = paths.filter { !$0.hasPrefix("(") && !$0.hasPrefix("<") }
        if let outside = files.first(where: { real(package.appending(path: $0))?.hasPrefix(root) != true }) {
            throw PluginError("outside", "\(outside): imports from outside the package")
        }
    }

    // MARK: settings.json

    /// The `packages` of `settings.json`: strings, or objects with their `source` (pi's form).
    public static func sources(_ settings: URL) -> [String] {
        (read(settings)["packages"] as? [Any] ?? []).compactMap {
            $0 as? String ?? ($0 as? [String: Any])?["source"] as? String
        }
    }

    /// Adds the source to the list (once), or takes it out; the file's other keys stay.
    public static func list(_ source: String, in settings: URL, add: Bool) throws {
        var json = read(settings)
        var packages = (json["packages"] as? [Any] ?? []).filter {
            ($0 as? String ?? ($0 as? [String: Any])?["source"] as? String) != source
        }
        if add {
            packages.append(source)
        }
        json["packages"] = packages
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys,
                                                                   .withoutEscapingSlashes])
            .write(to: settings, options: .atomic)
    }

    private static func read(_ settings: URL) -> [String: Any] {
        (try? Data(contentsOf: settings)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? [:]
    }
}
