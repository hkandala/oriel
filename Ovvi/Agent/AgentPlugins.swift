import AppKit
import HerdrKit

extension AgentCommand {
    /// The plugin registry for agents (agent-control, Plugins): the list, and for a pane on This Mac New Plugin, Reload
    /// Plugin(s) and Install, through the Plugins page's own code. Remove and Update stay the user's, on the plugin's
    /// page in Settings.
    static let plugins = AgentCommand(
        name: "plugins", usage: "plugins [--for <path or URL> | new <name> | reload [<id>] | install <source>]",
        summary: "Lists the kinds an agent can open; makes, reloads and installs plugins",
        help: """
        plugins: the browser and every plugin, and why a package did not load. --for: only the ones that open a \
        file, folder or URL, best first, the default marked, then a file's other Open With choices.
        new <name>: a plugin from the template in the plugins folder, built and confirmed (This Mac only). Pass a long \
        --timeout: it installs the template's dependencies and builds it.
        reload [<id>]: builds one plugin, or every plugin with an open card, and loads its cards again (This Mac \
        only). A card with unsaved edits stops it ("dirty"). Pass a long --timeout for a slow build.
        install <source>: npm:<package>, git:<repository> or a folder, after the user allows it on the Mac (This \
        Mac only). Pass a long --timeout: it answers after the install and the build.
        """,
    ) { call in
        let sub = ["new", "reload", "install"].contains(call.args.first ?? "") ? call.args.removeFirst() : nil
        if let sub, call.store.machine.isRemote {
            throw AgentError(code: "other_machine", message: "plugins \(sub) works only in a pane on This Mac, "
                + "where the plugins are")
        }
        switch sub {
        case "new": return try await newPlugin(&call)
        case "reload": return try await reloadPlugins(&call)
        case "install": return try await installPlugin(&call)
        default: return try await listPlugins(&call)
        }
    }

    private static func listPlugins(_ call: inout AgentCall) async throws -> AgentOutput {
        let path = try call.value("--for")
        try call.done()
        let rows = AgentPluginRows(call)
        guard let path else {
            let broken = Registry.problems.sorted { $0.key < $1.key }.map { id, problem in
                let source = (problem.folder.path as NSString).abbreviatingWithTildeInPath
                return (["id": id, "source": source, "error": problem.error] as [String: Any],
                        [id, "not loaded", "", source, problem.error])
            }
            let entries = Registry.all.map { (rows.entry($0), rows.line($0)) } + broken
            return AgentOutput(entries.map(\.0), text: table(entries.map(\.1)))
        }
        // As `open` takes it: from the command's folder, a folder by the disk; a missing path by its name.
        var full = path, file = false
        if URL(string: path)?.scheme == nil {
            full = call.absolute(path)
            let folder = await call.store.machine.exec().succeeds(#"[ -d "$1" ]"#, [full])
            full += path.hasSuffix("/") || folder ? "/" : ""
            file = !full.hasSuffix("/")
        }
        var openers = Registry.openers(for: full)
        // A file's Open With choices after them: `open <id> <file>` opens with those too.
        if file {
            openers += Registry.openers(full, options: true)
                .filter { plugin in !openers.contains { $0.id == plugin.id } }
        }
        return AgentOutput(
            openers.enumerated()
                .map { index, manifest in rows.entry(manifest).merging(["default": index == 0]) { $1 } },
            text: table(openers.enumerated().map { rows.line($1) + [$0 == 0 ? "default" : ""] }),
        )
    }

    private static func newPlugin(_ call: inout AgentCall) async throws -> AgentOutput {
        let name = try call.argument("name")
        try call.done()
        let folder = try await PluginInstalls.shared.create(named: name)
        let id = folder.lastPathComponent
        return AgentOutput(["id": id, "folder": folder.path, "log": PluginLog.file(id).path])
    }

    private static func installPlugin(_ call: inout AgentCall) async throws -> AgentOutput {
        let typed = try call.argument("source")
        try call.done()
        // A relative folder from the command's folder, not the settings' as in settings.json.
        let source = typed.hasPrefix(".") ? call.absolute(typed) : typed
        guard PluginSource(source) != nil else {
            throw AgentError(
                code: "bad_argument",
                message: "\(typed) is not npm:<package>, git:<repository> or a folder",
            )
        }
        // Again would be an Update, which asks only when its id changed: the user's, on the plugin's page.
        guard !PluginPackages.sources(Registry.settings).contains(source) else {
            throw AgentError(
                code: "bad_argument",
                message: "\(source) is installed; Update is on its page in Settings ▸ Plugins",
            )
        }
        guard let window = call.store.windows.first?.window else { throw AgentError.noWindow(call.store.session) }
        let asker = Asker(name: "\(call.agent) in pane \(call.pane)", window: window)
        let manifest: PluginManifest
        do {
            manifest = try await PluginInstalls.shared.install(source, for: asker)
        } catch is CancellationError {
            throw AgentError(code: "declined", message: "the user did not allow \(source)")
        }
        // Its row's source now, before the reload the install started.
        Registry.reload()
        let rows = AgentPluginRows(call)
        return AgentOutput(rows.entry(manifest), text: table([rows.line(manifest)]))
    }

    /// Reload Plugin, or Reload Plugins without an id. Unsaved edits stop it with `dirty`: Ovvi never discards them
    /// for an agent.
    private static func reloadPlugins(_ call: inout AgentCall) async throws -> AgentOutput {
        let id = try call.optionalArgument()
        try call.done()
        // A folder made since the last read loads too.
        Registry.reload()
        var ids = Set(Plugin.cards.map(\.manifest.id)).sorted()
        if let id {
            guard let manifest = Registry.plugin(id) else {
                throw AgentError(code: "plugin_not_found", message: Registry.problem(id) ?? "no plugin \(id)")
            }
            guard manifest.entry != nil else {
                throw AgentError(code: "bad_argument", message: "\(id) is part of Ovvi and has nothing to build")
            }
            guard PluginTrust.shared.allows(manifest) else {
                throw AgentError(code: "failed", message: "\(id) is not confirmed yet: its card asks the user first")
            }
            ids = [manifest.id]
        }
        var results: [[String: Any]] = [], failures: [String] = []
        func stop(_ dirty: Plugin, _ more: String = "") -> AgentError {
            let done = results.map { "\($0["id"] ?? "")" }
            return AgentError(code: "dirty", message: "\(call.naming(dirty)) has unsaved edits in \(dirty.manifest.id)"
                + more + (done.isEmpty ? "" : "; reloaded before it: \(done.joined(separator: ", "))"))
        }
        // Before anything builds, and again before each plugin: a card can get edits while another one builds.
        for (index, id) in ids.enumerated() {
            if let dirty = Plugin.cards.first(where: { ids[index...].contains($0.manifest.id) && $0.dirty }) {
                throw stop(dirty)
            }
            let start = ContinuousClock.now
            let problem = await Plugin.reload(id, asked: true, keepEdits: true)
            if let problem {
                failures.append("\(problem.title):\n\(problem.text)")
            } else if let dirty = Plugin.cards.first(where: { $0.manifest.id == id && $0.dirty }) {
                // Edits made during its build: that card kept its page, its other cards loaded the new build.
                throw stop(dirty, " and kept its page; \(id)'s other cards reloaded")
            }
            results.append([
                "id": id,
                // A plugin not confirmed yet builds nothing: its cards still ask the user.
                "built": problem == nil && Registry.plugin(id).map(PluginTrust.shared.allows) == true,
                "ms": Int((ContinuousClock.now - start) / .milliseconds(1)),
                "cards": Plugin.cards.count { $0.manifest.id == id },
            ])
        }
        guard failures.isEmpty else {
            throw AgentError(code: "build_failed", message: failures.joined(separator: "\n"))
        }
        if id != nil, let result = results.first {
            return AgentOutput(result)
        }
        return AgentOutput(["plugins": results], text: results.map { result in
            let built = result["built"] as? Bool == true ? "built" : "not built (not confirmed)"
            return "\(result["id"] ?? "") \(built) in \(result["ms"] ?? 0) ms, \(result["cards"] ?? 0) card(s)\n"
        }.joined())
    }

    /// Columns, two spaces apart.
    private static func table(_ lines: [[String]]) -> String {
        let widths = (0 ..< (lines.map(\.count).max() ?? 0)).map { column in
            lines.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        }
        return lines.map { line in
            line.enumerated().map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }
                .joined(separator: "  ").trimmingCharacters(in: .whitespaces) + "\n"
        }.joined()
    }
}

/// A plugin as `ovvi plugins` tells it: its manifest's fields as written, and its Plugins page row's source.
@MainActor
private struct AgentPluginRows {
    let sources: [String: String]
    /// The log is a file on the Mac: only an agent there can read it.
    let local: Bool

    init(_ call: AgentCall) {
        sources = Dictionary(PluginInstalls.shared.rows.map { ($0.id, $0.kind == .bundled ? "app" : $0.source) }) { $1 }
        local = !call.store.machine.isRemote
    }

    func source(_ manifest: PluginManifest) -> String {
        sources[manifest.id] ?? "app"
    }

    func entry(_ manifest: PluginManifest) -> [String: Any] {
        let opens = manifest.opens
        var written: [String: Any] = [:]
        written["files"] = opens.files.isEmpty ? nil : opens.files
        written["folders"] = opens.folders ? true : nil
        written["git"] = opens.git ? true : nil
        written["urls"] = opens.urls.isEmpty ? nil : opens.urls
        written["priority"] = opens.priority == "default" ? nil : opens.priority
        var entry: [String: Any] = [
            "id": manifest.id, "name": manifest.name, "icon": manifest.icon, "description": manifest.description,
            "version": manifest.version, "opens": written, "chooser": manifest.chooser ?? NSNull(),
            "source": source(manifest),
        ]
        if local, manifest.entry != nil {
            entry["log"] = PluginLog.file(manifest.id).path
        }
        return entry
    }

    func line(_ manifest: PluginManifest) -> [String] {
        let opens = manifest.opens
        let kinds = [("files", !opens.files.isEmpty), ("folders", opens.folders), ("git", opens.git),
                     ("urls", !opens.urls.isEmpty)].filter(\.1).map(\.0)
        return [manifest.id, manifest.name.shown, kinds.joined(separator: ","), source(manifest)]
    }
}

private extension AgentCall {
    /// A plugin card's pane as this caller names it: `w1:p3` in its session, `‹session›/‹pane›` on its machine, else
    /// with the machine's name.
    func naming(_ card: Plugin) -> String {
        guard let other = card.web.store, other !== store else { return "pane \(card.paneID)" }
        return other.machine.id == store.machine.id ? "pane \(other.session)/\(card.paneID)"
            : "pane \(card.paneID) of \(other.name)"
    }
}
