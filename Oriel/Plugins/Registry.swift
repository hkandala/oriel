import Foundation
import HerdrKit
import os

/// Every pane kind the app draws over a placeholder pane (future-work/plugins): the browser, whose manifest is written
/// here, and each plugin package's, read once at launch. The chooser, ⌘K, Open With and linked opens read this list.
enum Registry {
    /// Native content: no entry, its own toolbar (future-work/plugins/browser-and-native).
    static let browser = PluginManifest(
        id: "browser", name: "Browser", icon: "globe", description: "Web page", keywords: ["web", "url", "localhost"],
        opens: .init(urls: ["http://*", "https://*", "file://*"]), chooser: "Browser",
    )

    /// The browser, the default plugins, then the user's, each group by id: the chooser's order.
    static let all = loaded.all

    /// The ones that came with the app: before the user's in the chooser, after them on a tie for a file.
    static let defaults = loaded.defaults

    private static let loaded = load()
    private static let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The default plugins' built pages and their `package.json`, in place until the app installs them.
    static let folder = Bundle.main.resourceURL?.appending(path: "web")

    /// `~/.config/oriel`; a test points it elsewhere (`-configFolder`).
    static let config = UserDefaults.standard.string(forKey: "configFolder").map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/oriel")

    /// A label's plugin; the words of the five kinds before File Explorer and Git still open.
    static func plugin(_ id: String) -> PluginManifest? {
        byID[["file": "explorer", "preview": "explorer", "markdown": "explorer", "files": "explorer",
              "diff": "git"][id] ?? id]
    }

    /// Every icon a plugin card shows: the plugins' and the File Explorer's pages', and a missing plugin's.
    static let symbols = Set(all.map(\.icon) + PluginPage.allCases.map(\.symbol) + [missing])

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
    private static func load() -> (all: [PluginManifest], defaults: Set<String>) {
        let mine = packages(in: folder)
        var seen = [browser.id: "the app"]
        let found = mine + paths().compactMap(package) + packages(in: config.appending(path: "plugins"))
        let kept = found.filter { manifest, url in
            if let first = seen[manifest.id] {
                let text = "\(url.path): the id \(manifest.id) is taken by \(first)"
                log.error("\(text, privacy: .public)")
                return false
            }
            seen[manifest.id] = url.path
            return true
        }.map(\.manifest)
        let defaults = Set(mine.map(\.manifest.id))
        return ([browser] + kept.filter { defaults.contains($0.id) }
            + kept.filter { !defaults.contains($0.id) }.sorted { $0.id < $1.id }, defaults.union([browser.id]))
    }

    /// Each subfolder's package, by folder name.
    private static func packages(in folder: URL?) -> [(manifest: PluginManifest, url: URL)] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return names.sorted().filter { !$0.hasPrefix(".") }.compactMap { package(folder.appending(path: $0)) }
    }

    private static func package(_ folder: URL) -> (manifest: PluginManifest, url: URL)? {
        let file = folder.appending(path: "package.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        do {
            return try (PluginManifest(package: data), folder)
        } catch {
            log.error("\(file.path, privacy: .public): \(error.text, privacy: .public)")
            return nil
        }
    }

    /// The local paths in `settings.json`'s `packages`, from its folder or the home folder; npm and git sources install
    /// into the plugins folder.
    private static func paths() -> [URL] {
        let settings = config.appending(path: "settings.json")
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return (json["packages"] as? [String] ?? []).filter { ["/", "~", "."].contains($0.prefix(1)) }
            .map { path in
                let path = (path as NSString).expandingTildeInPath
                return (path.hasPrefix("/") ? URL(filePath: path) : config.appending(path: path)).standardizedFileURL
            }
    }
}
