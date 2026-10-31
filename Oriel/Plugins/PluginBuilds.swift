import CryptoKit
import Foundation
import HerdrKit
import WebKit

/// Builds each plugin package's entry with the esbuild the app ships (`Contents/Helpers/esbuild`, as pi ships jiti),
/// from the package's own `node_modules`, into `~/Library/Caches/dev.hkandala.oriel/plugins/<id>/<hash>`. A build is
/// kept by its inputs' hash, so a card made again or a relaunch loads at once; Reload Plugin always builds again.
@MainActor @Observable
final class PluginBuilds {
    static let shared = PluginBuilds()

    /// Each plugin's current build, which the scheme serves (`Registry.files`), and the one before it: a page that
    /// kept running over a rebuild (Keep Editing) still loads its later chunks from it.
    private(set) var folders: [String: URL] = [:]
    private(set) var previous: [String: URL] = [:]
    /// Each plugin's last build: the next one waits for it, so two never write one plugin's folders at once.
    @ObservationIgnored private var running: [String: Task<String?, Never>] = [:]
    /// A build's folder, or esbuild's errors; `built` false for a build found in the cache.
    private struct Made {
        let folder: URL?, errors: String?, built: Bool
    }

    /// Makes the plugin's current build when its inputs changed, or always (`again`). Nil when it passed; esbuild's
    /// errors when it failed, which also go to the plugin's log. A failed build leaves the last one current.
    func build(_ manifest: PluginManifest, again: Bool = false) async -> String? {
        let id = manifest.id, last = running[id]
        let task = Task { () -> String? in
            _ = await last?.value
            guard let package = Registry.package(id), manifest.entry != nil else {
                return "\(manifest.name.shown) has no package to build"
            }
            let start = ContinuousClock.now, keep = folders[id]
            let made = await Task.detached {
                await Self.make(manifest, package, again: again, keep: keep)
            }.value
            if let folder = made.folder, folder != folders[id] {
                previous[id] = folders[id]
                folders[id] = folder
            }
            if let errors = made.errors {
                PluginLog.add(id, "build failed:\n\(errors)")
            } else if made.built {
                PluginLog.add(
                    id,
                    "built in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))",
                )
            }
            return made.errors
        }
        running[id] = task
        return await task.value
    }

    /// At launch: the host types package `@oriel/plugin-api` in the plugins folder's `node_modules`, where `tsc`
    /// finds it from any plugin in the folder (a plugin lists it in `peerDependencies` and never bundles it), when the
    /// app's differs.
    static func writeTypes() {
        guard let source = Registry.folder?.appending(path: "plugin-api") else { return }
        let plugins = Registry.config.appending(path: "plugins")
        let target = plugins.appending(path: "node_modules/@oriel/plugin-api")
        Task.detached {
            let files = FileManager.default
            for name in ["package.json", "oriel.d.ts"] {
                let data = try? Data(contentsOf: source.appending(path: name))
                guard let data, data != (try? Data(contentsOf: target.appending(path: name))) else { continue }
                try? files.createDirectory(at: target, withIntermediateDirectories: true)
                try? data.write(to: target.appending(path: name), options: .atomic)
            }
        }
    }

    nonisolated static let esbuild = Bundle.main.bundleURL.appending(path: "Contents/Helpers/esbuild")
    nonisolated static let cache = URL.cachesDirectory.appending(path: "dev.hkandala.oriel/plugins")

    /// Splitting for the dynamic `import()` of heavy views; assets as files beside the build, served flat; a linked
    /// source map, which only the Web Inspector reads.
    nonisolated static let flags = ["--bundle", "--format=esm", "--splitting", "--minify", "--sourcemap",
                                    "--target=safari18", "--log-level=error", "--color=false"]
        + ["png", "jpg", "jpeg", "gif", "webp", "svg", "woff", "woff2", "ttf", "otf", "wasm"]
        .map { "--loader:.\($0)=file" }

    /// One build, run after the plugin's last one ended. `keep`: the current build, which stays as the previous one.
    private nonisolated static func make(_ manifest: PluginManifest, _ package: URL, again: Bool,
                                         keep: URL?) async -> Made
    {
        let files = FileManager.default, root = cache.appending(path: manifest.id),
            folder = root.appending(path: inputs(package))
        if !again, files.fileExists(atPath: folder.path) {
            return Made(folder: folder, errors: nil, built: false)
        }
        // Into a folder of its own, then in place: a card never loads half a build.
        let temporary = root.appending(path: ".\(UUID().uuidString)"), meta = root.appending(path: ".meta.json")
        defer { try? files.removeItem(at: temporary) }
        let (status, output) = await run(flags + [manifest.entry ?? "", "--outdir=\(temporary.path)",
                                                  "--metafile=\(meta.path)"], in: package)
        guard status == 0 else {
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Made(folder: nil, errors: text.isEmpty ? "esbuild failed (\(status))" : text, built: true)
        }
        do {
            try PluginPackages.inside(package, read(meta))
            try copy(manifest.assets, from: package, to: temporary)
            try? files.removeItem(at: folder)
            try files.moveItem(at: temporary, to: folder)
        } catch {
            return Made(folder: nil, errors: (error as? PluginError)?.text ?? error.localizedDescription, built: true)
        }
        // The plugin's older builds go, but the one cards may still run.
        for old in (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where ![folder.lastPathComponent, keep?.lastPathComponent].contains(old.lastPathComponent)
        {
            try? files.removeItem(at: old)
        }
        return Made(folder: folder, errors: nil, built: true)
    }

    /// The files esbuild read, from its metafile, relative to the package.
    private nonisolated static func read(_ meta: URL) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: meta)) as? [String: Any]
        return ((json?["inputs"] as? [String: Any]) ?? [:]).keys.sorted()
    }

    /// The manifest's `assets` beside the build, flat: a `*` in a path's last part matches as a shell's does.
    private nonisolated static func copy(_ assets: [String], from package: URL, to build: URL) throws {
        for asset in assets {
            let path = package.appending(path: asset), pattern = path.lastPathComponent
            let folder = path.deletingLastPathComponent()
            let names = pattern.contains("*") ? try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { fnmatch(pattern, $0, 0) == 0 } : [pattern]
            let files = names.map { folder.appending(path: $0) }
            try PluginPackages.inside(package, files.map { String($0.path.dropFirst(package.path.count + 1)) })
            for file in files {
                try FileManager.default.copyItem(at: file, to: build.appending(path: file.lastPathComponent))
            }
        }
    }

    /// The hash of what a build reads: the package's files (path, size, time) outside `node_modules`, the package
    /// manager's record of `node_modules` (an install rewrites it), the flags and esbuild.
    /// ponytail: an edit inside `node_modules` is not seen; Reload Plugin builds again anyway.
    nonisolated static func inputs(_ package: URL) -> String {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        func line(_ url: URL) -> String? {
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return "\(url.path) \(values.fileSize ?? 0) \(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        let modules = package.appending(path: "node_modules")
        var lines = ([modules, esbuild] + [".package-lock.json", ".modules.yaml"].map { modules.appending(path: $0) })
            .compactMap(line)
        let walk = FileManager.default.enumerator(at: package, includingPropertiesForKeys: Array(keys),
                                                  options: .skipsHiddenFiles)
        while let url = walk?.nextObject() as? URL {
            if url.lastPathComponent == "node_modules" {
                walk?.skipDescendants()
            } else if let line = line(url) {
                lines.append(line)
            }
        }
        let text = (flags + lines.sorted()).joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// esbuild in the package's folder, without `NODE_PATH`: imports resolve from the package's own `node_modules`.
    /// Its status and its messages.
    private nonisolated static func run(_ arguments: [String], in folder: URL) async -> (Int32, String) {
        await withCheckedContinuation { done in
            // Off Swift's pool: the read and the wait block.
            DispatchQueue.global().async {
                let process = Process(), output = Pipe()
                process.executableURL = esbuild
                process.arguments = arguments
                process.currentDirectoryURL = folder
                process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "NODE_PATH" }
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = output
                process.standardError = output
                do {
                    try process.run()
                } catch {
                    done.resume(returning: (-1, error.localizedDescription))
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                done.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

/// `~/Library/Logs/Oriel/plugins/<id>.log`: a plugin's build errors, console lines, uncaught errors and denied calls,
/// each with its time, for the author and their agents (`tail -f`).
enum PluginLog {
    nonisolated static let folder = URL.homeDirectory.appending(path: "Library/Logs/Oriel/plugins")
    private nonisolated static let queue = DispatchQueue(label: "dev.hkandala.oriel.plugin-log")

    nonisolated static func add(_ id: String, _ text: String) {
        // A page's line breaks stay indented under its line, so they never read as the app's own lines.
        let text = text.replacingOccurrences(of: "\n", with: "\n  ")
        let line = Data("\(Date.now.ISO8601Format(.iso8601(timeZone: .current))) \(text)\n".utf8)
        queue.async {
            let file = folder.appending(path: "\(id).log"), files = FileManager.default
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            // ponytail: starts over past 1 MB; keep a second file if authors need more history.
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if size.map({ $0 > 1 << 20 }) ?? true {
                files.createFile(atPath: file.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        }
    }
}

extension WebCard {
    /// The page again, from its start: Reload after it stopped, Reload Plugin. A plugin's page once it is trusted and
    /// built.
    func reload() {
        ready = false
        guard let bridge else {
            script()
            view.load(URLRequest(url: PluginScheme.url(plugin)))
            return
        }
        loads += 1
        let load = loads
        Task { [weak self] in
            // Only the last reload loads: Allow and a Reload Plugin may overlap.
            guard await bridge.prepare(), let self, load == loads else { return }
            bridge.failure = nil
            bridge.reset()
            script()
            view.load(URLRequest(url: PluginScheme.url(plugin)))
        }
    }
}

extension Bridge {
    /// Before the page loads: the user trusts the plugin (else the card shows the trust prompt) and its build passed
    /// (else the card shows the errors with Reload). True when the page can load.
    func prepare() async -> Bool {
        guard let plugin else { return false }
        guard PluginTrust.shared.allows(plugin.manifest) else {
            plugin.web.ready = true
            return false
        }
        if Registry.defaults.contains(plugin.manifest.id),
           let error = await DefaultPlugins.shared.installed(plugin.manifest.id)
        {
            failure = ("\(plugin.manifest.name.shown) could not install", error)
            plugin.web.ready = true
            return false
        }
        if let errors = await PluginBuilds.shared.build(plugin.manifest) {
            failure = ("\(plugin.manifest.name.shown) did not build", errors)
            plugin.web.ready = true
            return false
        }
        return true
    }
}

extension Plugin {
    /// Every plugin card the app has made, in every window, floating ones too.
    static var cards: [Plugin] {
        WindowPages.windows.flatMap(\.terminals.plugins.values)
    }

    /// Reload Plugin: its package read again, its build made again, then each of its cards' pages loaded again with
    /// their state and header values. A card whose manifest changed is made again from the new one (its header, and
    /// its trust when the permissions grew). A failed build keeps the pages and says so in each card. Unsaved edits
    /// ask first, on the first card that has them.
    /// ponytail: Discard there drops every card's edits, and a card made again starts from its state file (up to
    /// 500 ms behind); ask per card and hand the state over if that bites.
    static func reload(_ id: String, asked: Bool = false) async {
        if !asked, let dirty = cards.first(where: { $0.manifest.id == id && $0.dirty }) {
            dirty.leave { _ in Task { await reload(id, asked: true) } }
            return
        }
        Registry.reload()
        guard let manifest = Registry.plugin(id), manifest.entry != nil else { return }
        let cards = cards.filter { $0.manifest == manifest }
        guard let errors = await PluginBuilds.shared.build(manifest, again: true) else {
            cards.forEach { $0.web.reload() }
            return
        }
        for card in cards {
            if card.web.bridge?.failure != nil || !card.web.ready {
                // It never ran: it shows the new errors.
                card.web.bridge?.failure = ("\(manifest.name.shown) did not build", errors)
                card.web.ready = true
            } else {
                card.web.toast = Toast(text: "\(manifest.name.shown) did not build: \(errors.firstLine)", other: nil,
                                       main: ("Try Again", { Task { await reload(id) } }))
            }
        }
    }

    /// Reload Plugins: every package read again (new, removed and changed manifests), then each plugin with an open
    /// card built and loaded again.
    static func reloadAll(asked: Bool = false) async {
        if !asked, let dirty = cards.first(where: \.dirty) {
            dirty.leave { _ in Task { await reloadAll(asked: true) } }
            return
        }
        Registry.reload()
        for id in Set(cards.map(\.manifest.id)) {
            await reload(id, asked: true)
        }
    }
}

extension String {
    var firstLine: String {
        split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? self
    }
}
