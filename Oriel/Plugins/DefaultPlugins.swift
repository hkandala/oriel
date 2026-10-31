import AppKit
import CryptoKit
import HerdrKit

/// File Explorer and Git as packages the user can edit (future-work/plugins, decision 5): the app carries their source
/// (`Resources/web/defaults/<id>`, no `node_modules`) and installs each one into the plugins folder on first launch,
/// a copy and then `npm ci` from its lockfile. An app with a newer version replaces an unedited copy; an edited copy,
/// or one the app has other source for at the same version (a build of the repository), stays until the user picks
/// Update to Version or Reset to Default in the Plugins panel.
@MainActor @Observable
final class DefaultPlugins {
    static let shared = DefaultPlugins()

    /// The installs under way (their cards show it), and why the last one of a plugin failed (its card shows it, with
    /// Reload to try again).
    private(set) var installing: Set<String> = []
    private(set) var failures: [String: PluginProblem] = [:]
    /// What the panel offers per default: the app's newer version (Update to Version), or nil for its other source
    /// or the user's edits (Reset to Default).
    private(set) var offers: [String: String?] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    /// Each default as installed (`plugins/.defaults.json`): its version, the app's source's hash, and the copy's
    /// after its install (a package manager may write its lockfile into it), to tell an edited copy.
    private struct Record: Codable {
        let version: String, source: String, copy: String
    }

    private static var records: URL {
        PluginInstalls.plugins.appending(path: ".defaults.json")
    }

    private static var source: URL? {
        Registry.folder?.appending(path: "defaults")
    }

    /// The defaults the app carries, by id (their folder's name).
    private static var bundled: [String: PluginManifest] {
        guard let source, let names = try? FileManager.default.contentsOfDirectory(atPath: source.path) else {
            return [:]
        }
        return Dictionary(names.compactMap { name in
            (try? Data(contentsOf: source.appending(path: "\(name)/package.json")))
                .flatMap { try? PluginManifest(package: $0) }.map { (name, $0) }
        }) { first, _ in first }
    }

    /// The staging folders of installs a quit cut short go, before any install starts.
    private init() {
        let plugins = PluginInstalls.plugins, files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: plugins.path)) ?? [] where name.hasPrefix(".install-") {
            try? files.removeItem(at: plugins.appending(path: name))
        }
    }

    /// At launch: the missing defaults install, and unedited copies older than the app's version are replaced.
    func install() async {
        let records = Self.read()
        for (id, manifest) in Self.bundled {
            let copy = PluginInstalls.plugins.appending(path: id)
            guard FileManager.default.fileExists(atPath: copy.path) else {
                await put(id)
                continue
            }
            if let record = records[id], Self.newer(manifest.version, than: record.version),
               await Self.hash(copy) == record.copy
            {
                await put(id)
            }
        }
        await check()
    }

    /// What the panel offers for each installed default.
    func check() async {
        let records = Self.read()
        var offers: [String: String?] = [:]
        for (id, manifest) in Self.bundled where !installing.contains(id) {
            let copy = PluginInstalls.plugins.appending(path: id)
            guard FileManager.default.fileExists(atPath: copy.path), let source = Self.source?.appending(path: id)
            else { continue }
            let record = records[id]
            if Self.newer(manifest.version, than: record?.version ?? "") {
                offers[id] = .some(manifest.version)
            } else if await Self.hash(copy) != record?.copy {
                offers[id] = .some(nil)
            } else if await Self.hash(source) != record?.source {
                offers[id] = .some(nil)
            }
        }
        self.offers = offers
    }

    /// Waits for the plugin's install, made now when its copy is missing: nil once it is in place, else why not.
    func installed(_ manifest: PluginManifest) async -> PluginProblem? {
        let id = manifest.id, copy = PluginInstalls.plugins.appending(path: id)
        if tasks[id] != nil || !FileManager.default.fileExists(atPath: copy.path) {
            await put(id)
        }
        guard !FileManager.default.fileExists(atPath: copy.path) else { return nil }
        return failures[id] ?? PluginProblem(title: "\(manifest.name.shown) is not installed", text: "",
                                             button: "Try Again")
    }

    /// Update to Version and Reset to Default: an edited copy goes to the Trash, after a question.
    func reset(_ id: String) async {
        let copy = PluginInstalls.plugins.appending(path: id), record = Self.read()[id]
        let edited = await Self.hash(copy) != record?.copy
        if edited {
            let alert = NSAlert()
            alert.messageText = "Replace your edited \(Self.bundled[id]?.name ?? id)?"
            alert.informativeText = "Your copy goes to the Trash, and Oriel installs its own."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            let answer = if let window = NSApp.keyWindow {
                await alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            guard answer == .alertFirstButtonReturn else { return }
        }
        await put(id, trash: edited)
        await check()
    }

    /// The app's source copied over the plugin's folder, its dependencies from its lockfile and its build, then its
    /// cards load again. One at a time per plugin; `trash`: the old copy goes to the Trash, not away.
    func put(_ id: String, trash: Bool = false) async {
        if let task = tasks[id] {
            return await task.value
        }
        let task = Task { await copy(id, trash: trash) }
        tasks[id] = task
        installing.insert(id)
        await task.value
        tasks[id] = nil
        installing.remove(id)
    }

    private func copy(_ id: String, trash: Bool) async {
        guard let source = Self.source?.appending(path: id) else { return }
        failures[id] = nil
        let plugins = PluginInstalls.plugins,
            had = FileManager.default.fileExists(atPath: plugins.appending(path: id).path)
        let staging = plugins.appending(path: ".install-\(UUID().uuidString)"), copy = staging.appending(path: id)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: copy)
            let exec = await localExec.value
            let output = try await PluginPackages.dependencies(copy, exec: exec)
                + (PluginPackages.build(copy, exec: exec) ?? "")
            PluginLog.add(id, "installed:\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            let hashes = await (Self.hash(source), Self.hash(copy))
            try PluginPackages.place(copy, at: plugins.appending(path: id), keeping: staging)
            if trash {
                try? FileManager.default.trashItem(at: staging.appending(path: "old"), resultingItemURL: nil)
            }
            var records = Self.read()
            records[id] = Record(version: Self.bundled[id]?.version ?? "", source: hashes.0, copy: hashes.1)
            try JSONEncoder().encode(records).write(to: Self.records, options: .atomic)
            offers[id] = nil
            // A first install's cards wait for it (`Bridge.prepare`); an update's load the new copy.
            if had {
                Task { await Plugin.reload(id, build: false) }
            } else {
                Registry.reload()
            }
        } catch {
            if let manifest = Self.bundled[id] {
                failures[id] = .failed(manifest, "could not install", error, button: "Try Again")
            }
        }
    }

    /// A version above another, part by part (`1.10.0` over `1.9.2`).
    private static func newer(_ version: String, than other: String) -> Bool {
        version.compare(other, options: .numeric) == .orderedDescending
    }

    private static func read() -> [String: Record] {
        (try? JSONDecoder().decode([String: Record].self, from: Data(contentsOf: records))) ?? [:]
    }

    /// The package's files outside `node_modules`, by path in it and content.
    private nonisolated static func hash(_ folder: URL) async -> String {
        var hasher = SHA256()
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: .skipsHiddenFiles)
        var files: [URL] = []
        while let url = walk?.nextObject() as? URL {
            // What its install and its build write.
            if ["node_modules", "dist"].contains(url.lastPathComponent) {
                walk?.skipDescendants()
            } else if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(url)
            }
        }
        let base = folder.standardizedFileURL.path.count
        for file in files.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data(file.standardizedFileURL.path.dropFirst(base).utf8))
            hasher.update(data: (try? Data(contentsOf: file)) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
