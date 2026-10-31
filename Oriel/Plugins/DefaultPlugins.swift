import CryptoKit
import Foundation
import HerdrKit

/// File Explorer and Git as packages the user can edit (future-work/plugins, decision 5): the app carries their source
/// (`Resources/web/defaults/<id>`, no `node_modules`) and installs each one into the plugins folder on first launch,
/// a copy and then `npm ci` from its lockfile. An app whose copy differs (a newer version, or a build of the
/// repository with changed source) replaces an unedited copy; an edited one stays until the user picks Update to
/// Version or Reset to Default in the Plugins panel.
@MainActor @Observable
final class DefaultPlugins {
    static let shared = DefaultPlugins()

    /// The installs under way (their cards show it), and why the last one of a plugin failed (its card shows it, with
    /// Reload to try again).
    private(set) var installing: Set<String> = []
    private(set) var failures: [String: String] = [:]
    /// The copies changed since they were installed, and the app's version where its copy differs from the one
    /// installed.
    private(set) var edited: Set<String> = []
    private(set) var newer: [String: String] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    /// Each default's source hash as installed, to tell an edited copy and the app's other one
    /// (`plugins/.defaults.json`).
    private struct Record: Codable {
        let hash: String
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

    /// At launch: the staging folders of installs a quit cut short go; the missing defaults install, unedited copies
    /// the app has another of are replaced, and edited ones are noted.
    func install() async {
        let plugins = PluginInstalls.plugins, files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: plugins.path)) ?? [] where name.hasPrefix(".install-") {
            try? files.removeItem(at: plugins.appending(path: name))
        }
        await check()
        for id in Self.bundled.keys {
            if !files.fileExists(atPath: plugins.appending(path: id).path) || newer[id] != nil && !edited.contains(id) {
                await put(id)
            }
        }
    }

    /// Which copies are edited, and which the app has another of.
    func check() async {
        let records = Self.read()
        var edited = Set<String>(), newer: [String: String] = [:]
        for (id, manifest) in Self.bundled {
            let copy = PluginInstalls.plugins.appending(path: id)
            guard FileManager.default.fileExists(atPath: copy.path), let source = Self.source?.appending(path: id)
            else { continue }
            if await Self.hash(copy) != records[id]?.hash {
                edited.insert(id)
            }
            if await Self.hash(source) != records[id]?.hash {
                newer[id] = manifest.version
            }
        }
        (self.edited, newer) = (edited, newer)
    }

    /// Waits for the plugin's install, made now when its copy is missing: nil once it is in place, else why not.
    func installed(_ id: String) async -> String? {
        let copy = PluginInstalls.plugins.appending(path: id)
        if tasks[id] != nil || !FileManager.default.fileExists(atPath: copy.path) {
            await put(id)
        }
        return FileManager.default.fileExists(atPath: copy.path) ? nil : failures[id] ?? "It is not installed"
    }

    /// Install, Update to Version and Reset to Default: the app's source copied over the plugin's folder, its
    /// dependencies from its lockfile, then its cards load again. One at a time per plugin.
    func put(_ id: String) async {
        if let task = tasks[id] {
            return await task.value
        }
        let task = Task { await copy(id) }
        tasks[id] = task
        installing.insert(id)
        await task.value
        tasks[id] = nil
        installing.remove(id)
    }

    private func copy(_ id: String) async {
        guard let source = Self.source?.appending(path: id) else { return }
        failures[id] = nil
        let plugins = PluginInstalls.plugins,
            had = FileManager.default.fileExists(atPath: plugins.appending(path: id).path)
        let staging = plugins.appending(path: ".install-\(UUID().uuidString)"), copy = staging.appending(path: id)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: copy)
            try await PluginPackages.dependencies(copy, exec: localExec.value)
            let hash = await Self.hash(copy)
            try PluginPackages.place(copy, at: plugins.appending(path: id), keeping: staging)
            var records = Self.read()
            records[id] = Record(hash: hash)
            try JSONEncoder().encode(records).write(to: Self.records, options: .atomic)
            edited.remove(id)
            newer[id] = nil
            // A first install's cards wait for it (`Bridge.prepare`); an update's load the new copy.
            if had {
                Task { await Plugin.reload(id) }
            } else {
                Registry.reload()
            }
        } catch {
            failures[id] = error.localizedDescription.firstLine
            PluginLog.add(id, "install failed: \(error.localizedDescription)")
        }
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
            if url.lastPathComponent == "node_modules" {
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
