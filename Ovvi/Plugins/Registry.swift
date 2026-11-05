import Foundation
import HerdrKit
import os

/// Every pane kind the app draws over a placeholder pane (plugins): the browser, whose manifest is written
/// here, and each plugin package's, read at launch and again after an install, a removal or Reload Plugins. The
/// chooser, ⌘K, Open With and linked opens read this list.
@MainActor
enum Registry {
    /// Native content: no entry, its own toolbar (plugins/browser).
    static let browser = PluginManifest(
        id: "browser", name: "Browser", icon: "globe", description: "Web page", keywords: ["web", "url", "localhost"],
        opens: .init(urls: ["http://*", "https://*", "file://*"]), chooser: "Browser",
        settings: [.init(id: "network", type: "choice", title: "Web pages on remote machines load through",
                         default: .text("machine"),
                         description: "For new cards. The machine chip in a card switches it.",
                         options: [
                             .init(value: "machine", title: "The Machine"),
                             .init(value: "mac", title: "This Mac"),
                         ])],
    )

    /// The browser, the default plugins, then the user's, each group by id: the chooser's order.
    static var all: [PluginManifest] {
        current.loaded.all
    }

    /// The ones that came with the app: before the user's in the chooser, after them on a tie for a file.
    static var defaults: Set<String> {
        current.loaded.defaults
    }

    /// Observed, so the chooser and the menus show a list read again.
    @Observable final class Current {
        var loaded = load()
        var hidden = Registry.hidden()
    }

    private static let current = Current()

    /// Reads every package again: after an install, a removal, or Reload Plugins.
    static func reload() {
        current.loaded = load()
        current.hidden = hidden()
        PluginSettings.shared.reload()
    }

    /// Whether the New Pane chooser has a row for it: it declares one, and the user did not turn it off (its page in
    /// Settings, the confirmation).
    static func inNewPane(_ manifest: PluginManifest) -> Bool {
        manifest.chooser != nil && !current.hidden.contains(manifest.id)
    }

    /// An id (a plugin's, or an agent's command) the user turned off in New Pane.
    static func hiddenInNewPane(_ id: String) -> Bool {
        current.hidden.contains(id)
    }

    static func show(_ id: String, inNewPane: Bool) {
        do {
            try PluginPackages.list(id, in: settings, add: !inNewPane, key: hideKey)
        } catch {
            // The Plugins page's notice; the switch reads the file again, so it shows what is saved.
            PluginInstalls.shared.failure = ("Could not save settings.json: \(error.localizedDescription)", nil)
        }
        current.hidden = hidden()
    }

    private static let hideKey = "hideInNewPane"

    private static func hidden() -> Set<String> {
        Set(PluginPackages.sources(settings, key: hideKey))
    }

    /// File Explorer's extensions by place, read again with every package.
    static var places: [String: Set<String>] {
        current.loaded.places
    }

    /// The folder `ovvi-plugin://<id>/` serves: the built entry's (`dist`), with its chunks, CSS and assets.
    static func files(_ id: String) -> URL? {
        guard let entry = plugin(id)?.entry else { return nil }
        return package(id)?.appending(path: entry).deletingLastPathComponent()
    }

    /// A plugin package's folder, which the app builds from (a default plugin's installed copy, maybe not made yet);
    /// nil for the browser.
    static func package(_ id: String) -> URL? {
        current.loaded.folders[id]
    }

    /// What the app carries for plugins (`make web`): the runtime, `card.css`, the types package and the default
    /// plugins' source (`defaults/<id>`).
    static let folder = Bundle.main.resourceURL?.appending(path: "web")

    /// `~/.config/ovvi`; a test points it elsewhere (`-configFolder`).
    static let config = UserDefaults.standard.string(forKey: "configFolder").map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/ovvi")

    static let settings = config.appending(path: "settings.json")

    /// A label's plugin; the words of the five kinds before File Explorer and Git still open.
    static func plugin(_ id: String) -> PluginManifest? {
        current.loaded.byID[["file": "explorer", "preview": "explorer", "markdown": "explorer", "files": "explorer",
                             "diff": "git"][id] ?? id]
    }

    /// Every SF Symbol a plugin card shows: the plugins' and the File Explorer's pages', and a missing plugin's. Not a
    /// program icon's id (`terminal`, `swift`): those tiles stay the catalog's.
    static var symbols: Set<String> {
        current.loaded.symbols
    }

    static let missing = "puzzlepiece.extension"

    /// The plugins that open a file, best first (plugins/manifest#which-plugin-opens-a-file): the most
    /// specific pattern, then a user's plugin before one of the app's, then the lower id. `option` ones only when
    /// `options`.
    static func openers(_ path: String, options: Bool = false) -> [PluginManifest] {
        let ranked = all.compactMap { plugin in
            plugin.rank(file: path).flatMap { options || plugin.opens.priority == "default" ? ($0, plugin) : nil }
        }
        return ranked.sorted { first, second in
            let (mine, theirs) = (defaults.contains(first.1.id), defaults.contains(second.1.id))
            return first.0 != second.0 ? first.0 > second.0 : mine != theirs ? theirs : first.1.id < second.1.id
        }.map(\.1)
    }

    /// The plugins that open a path or web address, best first, so the first is an open's default: for an http(s)
    /// address the `default` plugins whose `urls` match it (a user's first, as for files), then the browser; for a
    /// folder (it ends in `/`) the plugins that open folders; else a file's `openers`.
    static func openers(for arg: String) -> [PluginManifest] {
        let scheme = URL(string: arg)?.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            return arg.hasSuffix("/") ? all.filter(\.opens.folders) : openers(arg)
        }
        let matches = all.filter { $0.id != browser.id && $0.opens.priority == "default" && $0.opens(url: arg) }
        return matches.filter { !defaults.contains($0.id) } + matches.filter { defaults.contains($0.id) } + [browser]
    }

    private static let log = Logger(subsystem: "dev.ovvi.app", category: "plugins")

    /// The first package of an id wins, in this order: the app's, the settings' local paths, the plugins folder. A bad
    /// manifest or a taken id is left out, with the reason in the log.
    struct Loaded {
        let all: [PluginManifest], defaults: Set<String>, folders: [String: URL]
        let byID: [String: PluginManifest], symbols: Set<String>
        let problems: [String: Problem]
        /// File Explorer's places.json (`ExplorerPlace`): the installed copy's, else the app's (first launch).
        let places: [String: Set<String>]

        init(all: [PluginManifest], defaults: Set<String>, folders: [String: URL], problems: [String: Problem]) {
            (self.all, self.defaults, self.folders, self.problems) = (all, defaults, folders, problems)
            places = [folders["explorer"], Registry.folder?.appending(path: "defaults/explorer")]
                .lazy.compactMap { $0.flatMap { try? Data(contentsOf: $0.appending(path: "places.json")) } }.first
                .flatMap { try? JSONDecoder().decode([String: Set<String>].self, from: $0) } ?? [:]
            byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            symbols = Set(all.map(\.icon) + ExplorerPlace.allCases.map(\.symbol)
                + [missing])
                .subtracting(programIcons.map(\.id))
        }
    }

    private static func load() -> Loaded {
        leftOut = [:]
        // The defaults' installed copies, with the app's manifest while a copy is missing (first launch).
        let plugins = config.appending(path: "plugins")
        let mine = packages(in: folder?.appending(path: "defaults")).map { manifest, url in
            let copy = plugins.appending(path: url.lastPathComponent)
            return package(copy) ?? (manifest, copy)
        }
        // The old label words open File Explorer or Git.
        var seen = Dictionary(uniqueKeysWithValues: [browser.id, "file", "preview", "markdown", "files", "diff"]
            .map { ($0, "the app") })
        var folders = Set<String>()
        let found = mine + paths().compactMap { package($0, named: true) }
            + packages(in: plugins)
        // A settings path into the plugins folder is the same package.
        let kept = found.filter { folders.insert($0.url.standardizedFileURL.path).inserted }.filter { manifest, url in
            if let first = seen[manifest.id] {
                note(url, "\(url.path): the id \(manifest.id) is taken by \(first)")
                return false
            }
            seen[manifest.id] = url.path
            return true
        }
        let defaults = Set(mine.map(\.manifest.id)), manifests = kept.map(\.manifest)
        return Loaded(all: [browser] + manifests.filter { defaults.contains($0.id) }
            + manifests.filter { !defaults.contains($0.id) }.sorted { $0.id < $1.id },
            defaults: defaults.union([browser.id]),
            folders: Dictionary(kept.map { ($0.manifest.id, $0.url) }) { first, _ in first },
            problems: leftOut.filter { problem in !manifests.contains { $0.id == problem.key } })
    }

    /// Each subfolder's package, by folder name.
    private static func packages(in folder: URL?) -> [(manifest: PluginManifest, url: URL)] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return names.sorted().filter { !$0.hasPrefix(".") }.compactMap { package(folder.appending(path: $0)) }
    }

    /// `named`: the settings list it, so a missing one is a mistake to log; the plugins folder's other files are not.
    private static func package(_ folder: URL, named: Bool = false) -> (manifest: PluginManifest, url: URL)? {
        let file = folder.appending(path: "package.json")
        guard let data = try? Data(contentsOf: file) else {
            if named {
                note(folder, "\(file.path): no package.json")
            }
            return nil
        }
        do {
            return try (PluginManifest(package: data), folder)
        } catch {
            let text = "\(file.path): \(error.text)"
            note(folder, text)
            // A label naming its id shows why it did not load, when the id itself reads.
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let id = (json?["ovvi"] as? [String: Any])?["id"] as? String {
                leftOut[id] = Problem(folder: folder, error: "package.json: \(error.text)")
                // `note` wrote it under the folder's name.
                if id != folder.lastPathComponent {
                    PluginLog.add(id, text)
                }
            }
            return nil
        }
    }

    /// Why a package with this id was left out (a bad manifest), while the list is read; `Loaded.problems` after.
    private static var leftOut: [String: Problem] = [:]

    /// A package left out for its manifest: its folder, and the error in it.
    struct Problem {
        let folder: URL
        let error: String
    }

    /// Every package with an id that was left out, by that id.
    static var problems: [String: Problem] {
        current.loaded.problems
    }

    /// Why the plugin of a label did not load: its manifest's error.
    static func problem(_ id: String) -> String? {
        current.loaded.problems[id].map { "\($0.folder.path)/\($0.error)" }
    }

    /// A package left out: in the unified log, and in the log file named after its folder (it may have no id).
    private static func note(_ folder: URL, _ text: String) {
        log.error("\(text, privacy: .public)")
        PluginLog.add(folder.lastPathComponent, text)
    }

    /// The local paths in `settings.json`'s `packages`; npm and git sources install into the plugins folder.
    private static func paths() -> [URL] {
        PluginPackages.sources(settings)
            .filter { ["/", "~", "."].contains($0.prefix(1)) }.map(local)
    }

    /// A local path source's folder, from the settings' folder or the home folder.
    static func local(_ path: String) -> URL {
        let path = (path as NSString).expandingTildeInPath
        return (path.hasPrefix("/") ? URL(filePath: path) : config.appending(path: path)).standardizedFileURL
    }
}
