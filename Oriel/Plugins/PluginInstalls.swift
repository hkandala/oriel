import AppKit
import HerdrKit

/// The Plugins panel's work (future-work/plugins, decision 5): install, update and remove of `npm:`, `git:` and local
/// path sources, the `packages` list of `settings.json`, and the trust prompt before a package's dependencies install.
@MainActor @Observable
final class PluginInstalls {
    static let shared = PluginInstalls()

    /// What a row is doing (`Installing…`), by its id: a plugin's id, or a source not installed yet.
    private(set) var busy: [String: String] = [:]
    /// The last install, update or remove that failed: its text, and the same again.
    var failure: (text: String, retry: (() -> Void)?)?

    static var settings: URL {
        Registry.config.appending(path: "settings.json")
    }

    static var plugins: URL {
        Registry.config.appending(path: "plugins")
    }

    var rows: [InstalledPlugin] {
        let sources = PluginPackages.sources(Self.settings)
        let pairs = sources.compactMap { text in PluginSource(text)?.folder.map { ($0, text) } }
        let installed = Dictionary(pairs) { first, _ in first }
        let plugins = Registry.all.filter { $0.id != Registry.browser.id }.map { manifest -> InstalledPlugin in
            let folder = Registry.package(manifest.id)
            let kind: InstalledPlugin.Kind = if Registry.defaults.contains(manifest.id) {
                .bundled
            } else if let folder, folder.deletingLastPathComponent().standardizedFileURL.path
                == Self.plugins.standardizedFileURL.path
            {
                installed[folder.lastPathComponent].map(InstalledPlugin.Kind.installed) ?? .folder
            } else {
                .local(folder?.path ?? "")
            }
            return InstalledPlugin(id: manifest.id, manifest: manifest, kind: kind)
        }
        let present = Set((try? FileManager.default.contentsOfDirectory(atPath: Self.plugins.path)) ?? [])
        let missing = installed.filter { !present.contains($0.key) }.sorted { $0.key < $1.key }
        return plugins + missing.map { InstalledPlugin(id: $0.value, manifest: nil, kind: .installed($0.value)) }
    }

    /// Install from the field: an `npm:` or `git:` source is fetched, its manifest shown in the trust prompt, then its
    /// dependencies installed; a local path is listed after the same prompt.
    func install(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let source = PluginSource(text) else {
            failure = ("Enter npm:<package>, git:<repository> or a folder’s path", nil)
            return
        }
        if let folder = source.folder, !PluginPackages.sources(Self.settings).contains(text),
           FileManager.default.fileExists(atPath: Self.plugins.appending(path: folder).path)
        {
            failure = ("A plugin folder named \(folder) is already installed", nil)
            return
        }
        await run(text, "Installing…") {
            if case let .local(path) = source {
                try await self.list(local: path, text)
            } else {
                try await self.fetch(source, text)
            }
        }
    }

    /// Update: the source fetched again (the newest version its spec allows) and put over the installed copy; it asks
    /// again only when the permissions grew.
    func update(_ row: InstalledPlugin) async {
        guard case let .installed(text) = row.kind, let source = PluginSource(text) else { return }
        await run(row.id, "Updating…") {
            try await self.fetch(source, text)
        }
    }

    /// Remove: off the list, its trust forgotten, and an installed or hand-made folder to the Trash. A local path's
    /// folder stays where it is.
    func remove(_ row: InstalledPlugin) async {
        guard row.kind != .bundled else { return }
        var text = "Its folder in the plugins folder goes to the Trash."
        if case .local = row.kind {
            text = "Its folder stays where it is; Oriel stops loading it."
        }
        guard await ask("Remove “\((row.manifest?.name ?? row.id).shown)”?", text, button: "Remove") else { return }
        await run(row.id, "Removing…") {
            if case let .installed(text) = row.kind {
                try PluginPackages.list(text, in: Self.settings, add: false)
            }
            if case let .local(path) = row.kind {
                let listed = PluginPackages.sources(Self.settings).first { Registry.local($0).path == path }
                if let listed {
                    try PluginPackages.list(listed, in: Self.settings, add: false)
                }
            } else if let folder = Registry.package(row.id) {
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            }
            PluginTrust.shared.forget(row.id)
            Registry.reload()
        }
    }

    /// New Plugin…: the app's template (`plugins/template`) copied into the plugins folder under a name, installed and
    /// built, trusted (the user made it), and shown in Finder for an editor or an agent.
    func create() async {
        let alert = NSAlert()
        alert.messageText = "New Plugin"
        alert.informativeText = "Oriel copies its template into the plugins folder, then installs and builds it."
        let field = NSTextField(string: "")
        field.frame.size.width = 260
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let answer = if let window = NSApp.keyWindow {
            await alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces).shown
        let id = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.joined(separator: "-")
        guard answer == .alertFirstButtonReturn, !id.isEmpty,
              let template = Registry.folder?.appending(path: "template")
        else { return }
        let folder = Self.plugins.appending(path: id)
        guard Registry.plugin(id) == nil, !FileManager.default.fileExists(atPath: folder.path) else {
            failure = ("A plugin named \(id) is already there", nil)
            return
        }
        await run(id, "Creating…") {
            try FileManager.default.createDirectory(at: Self.plugins, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: template, to: folder)
            let file = folder.appending(path: "package.json")
            let text = try String(contentsOf: file, encoding: .utf8).replacing("my-plugin", with: id)
                .replacing("My Plugin", with: name)
            try text.write(to: file, atomically: true, encoding: .utf8)
            let manifest = try PluginManifest(package: Data(contentsOf: file))
            let exec = await localExec.value
            let output = try await PluginPackages.dependencies(folder, exec: exec)
                + (PluginPackages.build(folder, exec: exec) ?? "")
            PluginLog.add(id, "created from the template:\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            PluginTrust.shared.allow(manifest)
            Registry.reload()
            NSWorkspace.shared.activateFileViewerSelecting([folder.appending(path: "src/main.ts")])
        }
    }

    private func fetch(_ source: PluginSource, _ text: String) async throws {
        let exec = await localExec.value
        let staged = try await PluginPackages.fetch(source, into: Self.plugins, exec: exec)
        do {
            try free(staged.manifest.id, for: Self.plugins.appending(path: source.folder ?? ""))
            guard await trusts(staged.manifest, from: text) else { return PluginPackages.discard(staged) }
            let output = try await PluginPackages.finish(staged, into: Self.plugins, exec: exec).output
            PluginLog.add(staged.manifest.id, "installed from \(text):\n"
                + output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            PluginPackages.discard(staged)
            PluginLog.add(staged.manifest.id, "install from \(text) failed: \(error.localizedDescription)")
            throw error
        }
        try installed(staged.manifest, text)
    }

    private func list(local path: String, _ text: String) async throws {
        let folder = Registry.local(path)
        let manifest = try PluginManifest(package: Data(contentsOf: folder.appending(path: "package.json")))
        try free(manifest.id, for: folder)
        guard await trusts(manifest, from: text) else { return }
        try installed(manifest, text)
    }

    /// An id the app or another folder has would install a package the registry leaves out.
    private func free(_ id: String, for folder: URL) throws {
        if let other = Registry.package(id), other.standardizedFileURL.path != folder.standardizedFileURL.path {
            throw HerdrError.failed("The id \(id) is taken by \((other.path as NSString).abbreviatingWithTildeInPath)")
        }
    }

    /// Listed and trusted once it is in place, then its cards load again.
    private func installed(_ manifest: PluginManifest, _ source: String) throws {
        try PluginPackages.list(source, in: Self.settings, add: true)
        PluginTrust.shared.allow(manifest)
        Task { await Plugin.reload(manifest.id) }
    }

    /// The trust prompt at install: the source and what the plugin can do. A new source always asks; an update only
    /// when its permissions grew.
    private func trusts(_ manifest: PluginManifest, from source: String) async -> Bool {
        let new = !PluginPackages.sources(Self.settings).contains(source)
        guard new || !PluginTrust.shared.allows(manifest) else { return true }
        let text = ["\(manifest.id) \(manifest.version.shown) from \(source)", manifest.description.shown,
                    PluginTrust.words(manifest).joined(separator: " ")].filter { !$0.isEmpty }
        return await ask("Trust “\(manifest.name.shown)”?", text.joined(separator: "\n\n"), button: "Install")
    }

    private func ask(_ title: String, _ text: String, button: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow else { return alert.runModal() == .alertFirstButtonReturn }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    /// One at a time per row; a failure's Retry runs it again.
    private func run(_ id: String, _ doing: String, _ body: @escaping () async throws -> Void) async {
        guard busy[id] == nil else { return }
        busy[id] = doing
        failure = nil
        defer { busy[id] = nil }
        do {
            try await body()
        } catch {
            let text = (error as? ManifestError).map { "package.json: \($0.text)" } ?? error.localizedDescription
            failure = (text.firstLine, { Task { await self.run(id, doing, body) } })
            if Registry.plugin(id) != nil {
                PluginLog.add(id, "\(doing) failed: \(text)")
            }
        }
    }
}

/// One row of the list: a plugin, or a listed source whose install is missing.
struct InstalledPlugin: Identifiable {
    enum Kind: Equatable {
        /// Came with the app, installed in the plugins folder on first launch.
        case bundled
        /// Installed from this `npm:` or `git:` source; not on disk yet when `manifest` is nil.
        case installed(String)
        /// A local path in the settings, loaded in place.
        case local(String)
        /// A folder put in the plugins folder by hand (or by an agent).
        case folder
    }

    let id: String
    let manifest: PluginManifest?
    let kind: Kind

    /// The line under its name.
    var source: String {
        switch kind {
        case .bundled: "Comes with Oriel"
        case let .installed(source): source
        case let .local(path): (path as NSString).abbreviatingWithTildeInPath
        case .folder: Registry.package(id).map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
        }
    }
}
