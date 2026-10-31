import AppKit
import HerdrKit
import Observation
import WebKit

/// The app's side of a plugin page's `oriel` object (web/oriel/runtime.ts, future-work/plugins/api): the page's
/// calls, the events it hears, and the card's state. Bound to its card when the card is made, so no message names a
/// machine or another card; each call is checked against the manifest's permissions (`PluginCalls`).
@MainActor @Observable
final class Bridge {
    @ObservationIgnored private weak var plugin: Plugin?
    /// The page's changes of its commands (`controls.set` of a command's id): `title`, `checked`, `enabled`.
    private(set) var commands: [String: [String: Any]] = [:]
    /// `main` threw or the page cannot run: the card shows this (a title and the error's first lines) with Reload.
    var failure: (title: String, text: String)?
    /// The plugin's state value as last set (JSON), kept beside the header's values.
    @ObservationIgnored private var state: Any?
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// The page's watches by id, and the running ones while the card shows.
    @ObservationIgnored private var watches: [Int: String] = [:]
    @ObservationIgnored private var watching: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private(set) var visible = false
    @ObservationIgnored private var shownBefore = false
    @ObservationIgnored var keyboard = false {
        didSet {
            if keyboard != oldValue {
                event("keyboard", keyboard)
            }
        }
    }

    /// `run`s under way, and the ones waiting for a slot: two at a time per card.
    @ObservationIgnored private var runs = 0
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    /// The last git write: each waits for the one before it (git takes `index.lock`).
    @ObservationIgnored private var writes: Task<Void, Never>?
    /// The toast the page waits on, by its id.
    @ObservationIgnored private var toast: Int?
    /// The app's theme as the page reads it (`oriel.theme`), from the card's view.
    @ObservationIgnored var theme: [String: Any] = [:] {
        didSet {
            if loaded, (theme as NSDictionary) != (oldValue as NSDictionary) {
                event("theme", theme)
            }
        }
    }

    @ObservationIgnored private var loaded = false

    /// The API version this app gives pages.
    static let api = 1

    init(plugin: Plugin) {
        self.plugin = plugin
        plugin.header.send = { [weak self] in self?.event("control", $0) }
        plugin.header.changed = { [weak self] in self?.save() }
        plugin.web.view.keyboard = { [weak self] in self?.keyboard = $0 }
        if plugin.manifest.api > Self.api {
            failure = (
                "\(plugin.manifest.name) needs a newer Oriel",
                "It is written for version \(plugin.manifest.api) of "
                    + "the plugin API; this Oriel has version \(Self.api).",
            )
        }
    }

    /// The card's context for the runtime, in the page before its code runs.
    func context() -> [String: Any] {
        guard let plugin, let store = plugin.web.store else { return [:] }
        let machine = store.machine, entry = plugin.manifest.entry ?? "main.js"
        var context: [String: Any] = [
            "api": plugin.manifest.api, "id": plugin.label.iid, "arg": plugin.web.arg,
            "plugin": ["id": plugin.manifest.id, "version": plugin.manifest.version],
            "machine": ["id": machine.id, "name": machine.name, "remote": machine.isRemote],
            "cwd": store.pane(plugin.paneID)?.cwd ?? "/", "visible": visible, "keyboard": keyboard,
            "controls": plugin.header.values, "theme": theme,
            // esbuild names the entry's build after it.
            "entry": (entry as NSString).deletingPathExtension + ".js",
        ]
        context["at"] = plugin.web.place
        context["state"] = state
        return context
    }

    /// Reads the instance state file once, before the first load: a relaunch, another device or a card made again
    /// after a drop starts where it was.
    func start() async {
        loaded = true
        guard let plugin, let store = plugin.web.store, state == nil else { return }
        let text = await store.machine.exec().read(home: plugin.label.statePath(session: store.session))
        let file = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        if let controls = file?["controls"] as? [String: Any] {
            plugin.header.restore(controls)
        }
        state = file?["state"].flatMap { $0 is NSNull ? nil : $0 }
    }

    /// An event for the page's `oriel.on` handlers (and the runtime's own: watches, toasts).
    func event(_ name: String, _ data: Any) {
        plugin?.web.view.callAsyncJavaScript("window.oriel_receive?.(name, data)", arguments: ["name": name,
                                                                                               "data": data],
                                             in: nil, in: .page)
    }

    /// ⌘S, or ⌘F, ⌘G and ⇧⌘G, when the manifest `handles` them.
    func command(_ name: String) {
        if plugin?.manifest.handles.contains(name == "save" ? "save" : "find") == true {
            event(name, NSNull())
        }
    }

    /// The card moved: after `card.go`, Back, Forward or a rename from elsewhere.
    func place(_ arg: String, at landing: String?) {
        var place: [String: Any] = ["arg": arg]
        place["at"] = landing
        event("place", place)
    }

    /// While the card shows (`PluginCard`): `visible`, and the watches run; showing again calls each watch once.
    func shown() async {
        visible = true
        event("visible", true)
        for id in watches.keys {
            watch(id)
            if shownBefore {
                event("watch", id)
            }
        }
        shownBefore = true
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        visible = false
        event("visible", false)
        watching.values.forEach { $0.cancel() }
        watching = [:]
    }

    private func watch(_ id: Int) {
        guard visible, let path = watches[id], let store = plugin?.web.store else { return }
        watching[id]?.cancel()
        watching[id] = Task { [weak self] in
            for await _ in await Files.watch(path, exec: store.machine.exec()) {
                self?.event("watch", id)
            }
        }
    }

    /// 500 ms after the last change of the state or a header value, the instance state file on the card's machine:
    /// `{"controls": …, "state": …}`, at most 256 KiB, last writer wins. Not after the pane closed: its device removed
    /// the file.
    private func save() {
        guard let plugin, let store = plugin.web.store else { return }
        var file: [String: Any] = ["controls": plugin.header.values]
        file["state"] = state
        guard let data = try? JSONSerialization.data(withJSONObject: file), data.count <= 256 << 10 else { return }
        let path = plugin.label.statePath(session: store.session), terminalID = plugin.terminalID
        saving?.cancel()
        saving = Task { [weak store] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let store, store.panes.contains(where: { $0.terminalID == terminalID })
            else { return }
            await store.machine.exec().write(home: path, String(decoding: data, as: UTF8.self))
        }
    }

    /// One message from the page, `{ call, args }`: its JSON reply, or the error the page's promise rejects with
    /// (`<code>: <text>`).
    func call(_ message: [String: Any]) async -> (Any?, String?) {
        let name = message["call"] as? String ?? "", args = message["args"] as? [String: Any] ?? [:]
        do {
            guard let plugin, failure == nil || name == "card.failed" else { throw PluginError("closed", "Closed") }
            try PluginCalls.check(name, plugin.manifest.permissions)
            let reply = try await answer(name, args, plugin)
            guard let reply else { return (nil, nil) }
            if let data = reply as? Data {
                return (String(decoding: data, as: UTF8.self), nil)
            }
            let data = try JSONSerialization.data(withJSONObject: reply, options: .fragmentsAllowed)
            return (String(decoding: data, as: UTF8.self), nil)
        } catch let error as PluginError {
            return (nil, "\(error.code): \(error.text)")
        } catch {
            return (nil, "failed: \(error.localizedDescription)")
        }
    }

    /// The reply as JSON values, or as JSON already (`Data`); nil for none.
    private func answer(_ name: String, _ args: [String: Any], _ plugin: Plugin) async throws -> Any? {
        switch name {
        case "run": return try await run(args, plugin)
        case "files.info": return try await info(args)
        case "files.watch", "files.unwatch": try watch(name, args)
        case _ where PluginCalls.gitWrites.contains(name): return try await serial { try await self.calls(name, args) }
        case _ where name.hasPrefix("files.") || name.hasPrefix("git."): return try await calls(name, args)
        case _ where name.hasPrefix("card.") || name.hasPrefix("state.") || name.hasPrefix("controls."):
            try own(name, args, plugin)
        default: return try await card(name, args, plugin)
        }
        return nil
    }

    /// The card's own calls: its place, loader, Edited dot and failure; its state; its header.
    private func own(_ name: String, _ args: [String: Any], _ plugin: Plugin) throws {
        switch name {
        case "card.go":
            guard let arg = args["arg"] as? String else { throw PluginError("failed", "arg is missing") }
            plugin.go(arg, at: args["at"] as? String)
        case "card.ready": plugin.web.ready = true
        case "card.setDirty": plugin.web.dirty = args["dirty"] as? Bool == true
        case "card.failed":
            failure = ("\(plugin.manifest.name) stopped", [args["text"], args["stack"]].compactMap { $0 as? String }
                .filter { !$0.isEmpty }.joined(separator: "\n"))
            plugin.web.ready = true
        case "state.set":
            let value = args["value"] ?? NSNull()
            guard let data = try? JSONSerialization.data(withJSONObject: [value]), data.count <= 256 << 10 else {
                throw PluginError("tooLarge", "The state is over 256 KiB, or not JSON")
            }
            state = value is NSNull ? nil : value
            save()
        case "controls.set":
            let id = args["id"] as? String ?? "", change = args["change"] as? [String: Any] ?? [:]
            if plugin.manifest.commands.contains(where: { $0.id == id }) {
                commands[id, default: [:]].merge(change) { $1 }
            } else {
                plugin.header.set(id, change)
            }
        default: throw PluginError("failed", "No call \(name)")
        }
    }

    /// A watch from the page, or its end.
    private func watch(_ name: String, _ args: [String: Any]) throws {
        guard let id = args["id"] as? Int else { throw PluginError("failed", "id is missing") }
        guard name == "files.watch" else {
            watches[id] = nil
            watching.removeValue(forKey: id)?.cancel()
            return
        }
        guard let path = args["path"] as? String, path.hasPrefix("/") else {
            throw PluginError("failed", "path must be an absolute path")
        }
        watches[id] = path
        watch(id)
    }

    /// A call on the card's machine (HerdrKit's `PluginCalls`).
    func calls(_ name: String, _ args: [String: Any]) async throws -> Data {
        guard let plugin, let store = plugin.web.store else { throw PluginError("closed", "Closed") }
        let data = try JSONSerialization.data(withJSONObject: args)
        let calls = await PluginCalls(permissions: plugin.manifest.permissions, exec: store.machine.exec(),
                                      remote: store.machine.isRemote,
                                      gitRuns: name.hasPrefix("git.") ? store.gitRuns() : false)
        return try await calls.call(name, data)
    }

    /// Two at a time per card; the rest wait in order. In the pane's folder unless the page says otherwise.
    private func run(_ args: [String: Any], _ plugin: Plugin) async throws -> Data {
        while runs >= 2 {
            await withCheckedContinuation { waiting.append($0) }
        }
        runs += 1
        defer {
            runs -= 1
            if !waiting.isEmpty {
                waiting.removeFirst().resume()
            }
        }
        var args = args
        if args["cwd"] == nil {
            args["cwd"] = plugin.web.store?.pane(plugin.paneID)?.cwd ?? "/"
        }
        return try await calls("run", args)
    }

    /// After the git write before it, whether it worked or not.
    private func serial(_ body: @escaping () async throws -> Data) async throws -> Data {
        let previous = writes
        let write = Task { () -> Result<Data, any Error> in
            await previous?.value
            do {
                return try await .success(body())
            } catch {
                return .failure(error)
            }
        }
        writes = Task { _ = await write.value }
        return try await write.value.get()
    }

    /// The page's toast, replacing one it waits on (that one resolves with no button).
    func show(_ text: String, buttons: [String]?, id: Int) {
        guard let web = plugin?.web else { return }
        if let toast {
            event("toast", ["id": toast])
        }
        toast = id
        let picked = { [weak self] (title: String) in
            guard let self, toast == id else { return }
            toast = nil
            event("toast", ["id": id, "button": title])
        }
        let main = buttons?.last ?? "OK", other = buttons?.count == 2 ? buttons?.first : nil
        web.toast = Toast(text: text, other: other.map { title in (title, { picked(title) }) },
                          main: (main, { buttons == nil ? picked("") : picked(main) }))
    }
}
