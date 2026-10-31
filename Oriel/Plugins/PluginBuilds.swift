import AppKit
import HerdrKit
import WebKit

/// Runs each plugin package's own `build` script (decision 5, as pi's packages), with the npm, pnpm or bun on the
/// login `PATH`: on Reload Plugin, from a card's Build, and after an install. The app ships no bundler; the page loads
/// the built entry (`dist/main.js`) with its chunks and CSS from the entry's folder (`Registry.files`).
@MainActor
final class PluginBuilds {
    static let shared = PluginBuilds()

    /// Each plugin's last build: the next one waits for it, so two never write one plugin's folder at once.
    private var running: [String: Task<PluginProblem?, Never>] = [:]

    /// Runs the plugin's build script, if it has one. Nil when it passed and the entry is there; else what to say in
    /// the card, which also goes to the plugin's log with the script's output.
    func build(_ manifest: PluginManifest) async -> PluginProblem? {
        let id = manifest.id, last = running[id]
        let task = Task { () -> PluginProblem? in
            _ = await last?.value
            // An author's script runs only for a plugin the user trusts; the card asks first.
            guard PluginTrust.shared.allows(manifest), let package = Registry.package(id) else { return nil }
            if Registry.defaults.contains(id), let problem = await DefaultPlugins.shared.installed(manifest) {
                return problem
            }
            let start = ContinuousClock.now
            do {
                guard let output = try await PluginPackages.build(package, exec: localExec.value) else { return nil }
                PluginLog.add(
                    id,
                    "built in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))"
                        + ":\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))",
                )
                return Self.built(manifest)
            } catch {
                return .failed(manifest, "did not build", error, button: "Try Again", builds: true)
            }
        }
        running[id] = task
        return await task.value
    }

    /// The entry the build writes is there; else the card says it is not built, with Build when there is a script.
    static func built(_ manifest: PluginManifest) -> PluginProblem? {
        guard let package = Registry.package(manifest.id), let entry = manifest.entry,
              !FileManager.default.fileExists(atPath: package.appending(path: entry).path) else { return nil }
        let script = PluginPackages.builds(package)
        return .noted(manifest, PluginProblem(
            title: "\(manifest.name.shown) is not built",
            text: "\(entry) is missing. " + (script ? "Build runs its build script."
                : "Its package has no build script: build it with its own tools."),
            button: script ? "Build" : nil, builds: true,
        ))
    }

    /// At launch: the host types package `@oriel/plugin-api` in the plugins folder's `node_modules`, where `tsc`
    /// finds it from any plugin in the folder (a plugin lists it in `peerDependencies` and never bundles it), when the
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
}

/// Why a plugin's page cannot load, in plain words, with the fix as a button where there is one: no package manager,
/// a failed install or build, no built entry, a page that stopped, an API too new. The card shows it; the log has it.
struct PluginProblem {
    let title: String
    let text: String
    /// Its button: Reload, Try Again or Build; none when the user has nothing to press.
    var button: String? = "Reload"
    /// The button builds before it loads again.
    var builds = false

    /// A failed install or build: no package manager says to install Node.js; else the command's last lines.
    static func failed(_ manifest: PluginManifest, _ what: String, _ error: any Error, button: String,
                       builds: Bool = false) -> PluginProblem
    {
        let title = error is PluginPackages.NoManager ? "\(manifest.name.shown) needs Node.js"
            : "\(manifest.name.shown) \(what)"
        return noted(manifest, PluginProblem(title: title, text: error.localizedDescription, button: button,
                                             builds: builds))
    }

    /// The same words in the plugin's log.
    static func noted(_ manifest: PluginManifest, _ problem: PluginProblem) -> PluginProblem {
        PluginLog.add(manifest.id, "\(problem.title): \(problem.text)")
        return problem
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

    /// Show Log: the plugin's log in the app that opens `.log` files (Console), after the lines on their way.
    nonisolated static func show(_ id: String) {
        queue.async {
            let file = folder.appending(path: "\(id).log")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            DispatchQueue.main.async { NSWorkspace.shared.open(file) }
        }
    }
}

extension WebCard {
    /// The page again, from its start: Reload after it stopped, Reload Plugin. A plugin's page once it is trusted and
    /// built.
    func reload() {
        ready = false
        guard let bridge else { return }
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
    /// Before the page loads: the user trusts the plugin (else the card shows the trust prompt), a default plugin is
    /// installed, and the built entry is there; else the card says why. True when the page can load.
    func prepare() async -> Bool {
        guard let plugin else { return false }
        let manifest = plugin.manifest
        guard PluginTrust.shared.allows(manifest) else {
            plugin.web.ready = true
            return false
        }
        var problem: PluginProblem?
        if Registry.defaults.contains(manifest.id) {
            problem = await DefaultPlugins.shared.installed(manifest)
        }
        if let problem = problem ?? PluginBuilds.built(manifest) {
            failure = problem
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

    /// Reload Plugin: its package read again, its build script run, then each of its cards' pages loaded again with
    /// their state and header values. A card whose manifest changed is made again from the new one (its header, and
    /// its trust when the permissions grew). A failed build keeps the pages and says so in each card. Unsaved edits
    /// ask first, on the first card that has them.
    /// ponytail: Discard there drops every card's edits, and a card made again starts from its state file (up to
    /// 500 ms behind); ask per card and hand the state over if that bites.
    /// `build` false: an install that built it already, or ships its build.
    static func reload(_ id: String, asked: Bool = false, build: Bool = true) async {
        if !asked, let dirty = cards.first(where: { $0.manifest.id == id && $0.dirty }) {
            dirty.leave { _ in Task { await reload(id, asked: true, build: build) } }
            return
        }
        Registry.reload()
        guard let manifest = Registry.plugin(id), manifest.entry != nil else { return }
        let cards = cards.filter { $0.manifest == manifest }
        guard build, let problem = await PluginBuilds.shared.build(manifest) else {
            cards.forEach { $0.web.reload() }
            return
        }
        for card in cards {
            if card.web.bridge?.failure != nil || !card.web.ready {
                // It never ran: it shows the new problem.
                card.web.bridge?.failure = problem
                card.web.ready = true
            } else {
                card.web.toast = Toast(text: "\(problem.title): \(problem.text.firstLine)", other: nil,
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
