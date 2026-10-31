import CryptoKit
import Foundation
import HerdrKit

/// Builds each plugin package's entry with the esbuild the app ships (`Contents/Helpers/esbuild`, as pi ships jiti),
/// from the package's own `node_modules`, into `~/Library/Caches/dev.hkandala.oriel/plugins/<id>/<hash>`. A build is
/// kept by its inputs' hash, so a card made again or a relaunch loads at once; Reload Plugin always builds again.
@MainActor @Observable
final class PluginBuilds {
    static let shared = PluginBuilds()

    /// Each plugin's current build, which the scheme serves (`Registry.files`).
    private(set) var folders: [String: URL] = [:]
    @ObservationIgnored private var running: [String: Task<Made, Never>] = [:]
    /// A build's folder, or esbuild's errors; `built` false for a build found in the cache.
    private struct Made {
        let folder: URL?, errors: String?, built: Bool
    }

    /// Makes the plugin's current build when its inputs changed, or always (`again`). Nil when it passed; esbuild's
    /// errors when it failed, which also go to the plugin's log. A failed build leaves the last one current.
    func build(_ manifest: PluginManifest, again: Bool = false) async -> String? {
        let id = manifest.id
        if let task = running[id] {
            let errors = await task.value.errors
            guard again else { return errors }
        }
        guard let package = Registry.package(id), let entry = manifest.entry else {
            return "\(manifest.name) has no package to build"
        }
        let start = ContinuousClock.now
        let task = Task.detached { await Self.make(id, package, entry, again: again) }
        running[id] = task
        let made = await task.value, (folder, errors) = (made.folder, made.errors)
        if running[id] == task {
            running[id] = nil
        }
        if let folder {
            folders[id] = folder
        }
        if let errors {
            PluginLog.add(id, "build failed:\n\(errors)")
        } else if made.built {
            PluginLog.add(id, "built in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))")
        }
        return errors
    }

    /// The host types package `@oriel/plugin-api` in the plugins folder's `node_modules`, where `tsc` finds it from
    /// any plugin in the folder (a plugin lists it in `peerDependencies` and never bundles it). At launch, when the
    /// app's differs.
    static func writeTypes() {
        guard let source = Registry.folder?.appending(path: "plugin-api") else { return }
        let target = Registry.config.appending(path: "plugins/node_modules/@oriel/plugin-api")
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

    private nonisolated static func make(_ id: String, _ package: URL, _ entry: String,
                                         again: Bool) async -> Made
    {
        let files = FileManager.default, root = cache.appending(path: id),
            folder = root.appending(path: inputs(package))
        if !again, files.fileExists(atPath: folder.path) {
            return Made(folder: folder, errors: nil, built: false)
        }
        // Into a folder of its own, then in place: a card never loads half a build.
        let temporary = root.appending(path: ".\(UUID().uuidString)")
        let (status, output) = await run(flags + [entry, "--outdir=\(temporary.path)"], in: package)
        guard status == 0 else {
            try? files.removeItem(at: temporary)
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Made(folder: nil, errors: text.isEmpty ? "esbuild failed (\(status))" : text, built: true)
        }
        try? files.removeItem(at: folder)
        do {
            try files.moveItem(at: temporary, to: folder)
        } catch {
            return Made(folder: nil, errors: error.localizedDescription, built: true)
        }
        // The plugin's older builds go; a card still on one loads the new one at its next load.
        for old in (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent != folder.lastPathComponent
        {
            try? files.removeItem(at: old)
        }
        return Made(folder: folder, errors: nil, built: true)
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

extension Bridge {
    /// Before the page loads: the user trusts the plugin (else the card shows the trust prompt) and its build passed
    /// (else the card shows the errors with Reload). True when the page can load.
    func prepare() async -> Bool {
        guard let plugin else { return false }
        guard PluginTrust.shared.allows(plugin.manifest) else {
            plugin.web.ready = true
            return false
        }
        if let errors = await PluginBuilds.shared.build(plugin.manifest) {
            failure = ("\(plugin.manifest.name) did not build", errors)
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
    /// its trust when the permissions grew). A failed build keeps the pages and says so in each card; a card with
    /// unsaved edits asks first.
    static func reload(_ id: String) async {
        Registry.reload()
        guard let manifest = Registry.plugin(id), manifest.entry != nil, !Registry.defaults.contains(id) else { return }
        let cards = cards.filter { $0.manifest == manifest && $0.web.page == .main }
        if let errors = await PluginBuilds.shared.build(manifest, again: true) {
            for card in cards {
                if card.web.bridge?.failure != nil || !card.web.ready {
                    // It never ran: it shows the new errors.
                    card.web.reload()
                } else {
                    card.web.toast = Toast(text: "\(manifest.name) did not build: \(errors.firstLine)", other: nil,
                                           main: ("Try Again", { Task { await reload(id) } }))
                }
            }
            return
        }
        for card in cards {
            card.leave { $0.web.reload() }
        }
    }

    /// Reload Plugins: every package read again (new, removed and changed manifests), then each plugin with an open
    /// card built and loaded again.
    static func reloadAll() async {
        Registry.reload()
        for id in Set(cards.map(\.manifest.id)) {
            await reload(id)
        }
    }
}

extension String {
    var firstLine: String {
        split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? self
    }
}
