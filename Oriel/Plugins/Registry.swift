import Foundation
import HerdrKit
import os

/// Every pane kind the app draws over a placeholder pane (future-work/plugins): the browser, whose manifest is written
/// here, and each plugin package's, read at launch and again after an install, a removal or Reload Plugins. The
/// chooser, ⌘K, Open With and linked opens read this list.
@MainActor
enum Registry {
    /// Native content: no entry, its own toolbar (future-work/plugins/browser-and-native).
    static let browser = PluginManifest(
        id: "browser", name: "Browser", icon: "globe", description: "Web page", keywords: ["web", "url", "localhost"],
        opens: .init(urls: ["http://*", "https://*", "file://*"]), chooser: "Browser",
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
    }

    private static let current = Current()

    /// Reads every package again: after an install, a removal, or Reload Plugins.
    static func reload() {
        current.loaded = load()
    }

    /// The folder `oriel-plugin://<id>/` serves: a default plugin's built pages, else the package's current build.
    static func files(_ id: String) -> URL? {
        defaults.contains(id) ? folder?.appending(path: id) : PluginBuilds.shared.folders[id]
    }

    /// A plugin package's folder, which the app builds from; nil for the browser and the app's built pages.
    static func package(_ id: String) -> URL? {
        current.loaded.folders[id]
    }

    /// The default plugins' built pages and their `package.json`, in place until the app installs them.
    static let folder = Bundle.main.resourceURL?.appending(path: "web")

    /// `~/.config/oriel`; a test points it elsewhere (`-configFolder`).
    static let config = UserDefaults.standard.string(forKey: "configFolder").map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/oriel")

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

    /// The plugins that open a file, best first (future-work/plugins/manifest#which-plugin-opens-a-file): the most
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

    private static let log = Logger(subsystem: "dev.hkandala.oriel", category: "plugins")

    /// The first package of an id wins, in this order: the app's, the settings' local paths, the plugins folder. A bad
    /// manifest or a taken id is left out, with the reason in the log.
    struct Loaded {
        let all: [PluginManifest], defaults: Set<String>, folders: [String: URL]
        let byID: [String: PluginManifest], symbols: Set<String>

        init(all: [PluginManifest], defaults: Set<String>, folders: [String: URL]) {
            (self.all, self.defaults, self.folders) = (all, defaults, folders)
            byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            symbols = Set(all.map(\.icon) + PluginPage.allCases.map(\.symbol) + ExplorerPlace.allCases.map(\.symbol)
                + [missing])
                .subtracting(programIcons.map(\.id))
        }
    }

    private static func load() -> Loaded {
        let mine = packages(in: folder)
        // The old label words open File Explorer or Git.
        var seen = Dictionary(uniqueKeysWithValues: [browser.id, "file", "preview", "markdown", "files", "diff"]
            .map { ($0, "the app") })
        var folders = Set<String>()
        let found = mine + paths().compactMap { package($0, named: true) }
            + packages(in: config.appending(path: "plugins"))
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
            folders: Dictionary(kept.map { ($0.manifest.id, $0.url) }) { first, _ in first })
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
            note(folder, "\(file.path): \(error.text)")
            return nil
        }
    }

    /// A package left out: in the unified log, and in the log file named after its folder (it may have no id).
    private static func note(_ folder: URL, _ text: String) {
        log.error("\(text, privacy: .public)")
        PluginLog.add(folder.lastPathComponent, text)
    }

    /// The local paths in `settings.json`'s `packages`; npm and git sources install into the plugins folder.
    private static func paths() -> [URL] {
        PluginPackages.sources(config.appending(path: "settings.json"))
            .filter { ["/", "~", "."].contains($0.prefix(1)) }.map(local)
    }

    /// A local path source's folder, from the settings' folder or the home folder.
    static func local(_ path: String) -> URL {
        let path = (path as NSString).expandingTildeInPath
        return (path.hasPrefix("/") ? URL(filePath: path) : config.appending(path: path)).standardizedFileURL
    }
}
