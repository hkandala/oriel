import HerdrKit
import SwiftUI

/// `open`, `reveal`, `card` and `shown` (agent-control/cli): cards an agent opens and points at, never moving the
/// user's view.
extension AgentCommand {
    static let open = AgentCommand(
        name: "open", usage: "open <kind-or-path> [<arg>...] [<place>] [--new]",
        summary: "Opens a browser or plugin card beside this pane",
        help: """
        A kind is an id from `ovvi plugins`; write a path of the same name as ./name. A path or URL alone opens with \
        its default plugin. Relative paths are from the working folder; `browser ./report.html` opens a file on This \
        Mac.
        <place>: --beside <pane> [--down] (a split, right or below; this pane by default), --tab (a new tab at the \
        end of this pane's workspace, not selected), --float (as --tab, then floats it), --replace <pane> (that \
        browser or plugin card shows it).
        A card of the same kind and argument in the session is the answer ("reused": true) unless --new, which \
        --replace does not take.
        """,
    ) { call in
        let new = call.flag("--new"), place = try call.place()
        let first = try call.argument("kind or path")
        var words: [String] = []
        while let word = try call.optionalArgument() {
            words.append(word)
        }
        try call.done()
        let (plugin, arg) = try await call.opening(first, words)
        if case let .replace(target) = place {
            guard !new else { throw AgentError.usage("--replace makes no new card") }
            return try await call.replace(target, plugin, arg)
        }
        // A card of that kind and argument where the new one would go.
        let store = if case let .beside(target, _) = place {
            try call.found(target).0
        } else {
            call.store
        }
        if !new, let same = store.panes.first(where: { pane in
            pane.plugin.map { $0.manifest?.id == plugin.id && $0.place == arg } == true
        }), let label = same.plugin {
            return call.opened(same.id, label, in: store, reused: true)
        }
        let label = store.newLabel(plugin, arg: arg)
        guard PaneLabel(label.text) != nil else { throw AgentError.noLabel(first) }
        let (made, id) = try await call.newPane(place, label: label)
        return call.opened(id, label, in: made, reused: false)
    }

    static let reveal = AgentCommand(
        name: "reveal", usage: "reveal <pane>", summary: "Points the user at a pane, without moving their view",
        help: "In view, its card's border flashes; else each window that shows the session says so, with Show.",
    ) { call in
        let target = try call.target(call.argument("pane"))
        try call.done()
        let (store, pane) = try call.found(target)
        let shown = store.inView.contains(pane.id)
        if shown {
            store.flash(pane.id)
        } else {
            store.notice("\(call.agent) points to \(store.title(pane))", show: pane)
        }
        return AgentOutput(["pane": pane.id, "shown": shown])
    }

    static let card = AgentCommand(
        name: "card", usage: "card <pane>", summary: "What a card shows: kind, argument, title, unsaved edits",
        help: """
        kind is a browser or plugin id, terminal or agent; an agent card adds agent and chat, and view (chat or tui) \
        when it has the chat view. arg is a card's argument, a terminal's folder.
        """,
    ) { call in
        let target = try call.target(call.argument("pane"))
        try call.done()
        let (store, pane) = try call.found(target)
        var json: [String: Any] = ["pane": pane.id, "title": store.title(pane), "floating": target.floating != nil,
                                   "shown": store.inView.contains(pane.id)]
        if let label = pane.plugin {
            let card = pane.card
            json["kind"] = label.manifest?.id ?? label.plugin
            json["arg"] = label.place
            json["dirty"] = card?.dirty == true
            json["error"] = label.manifest == nil ? Registry.problem(label.plugin) ?? "no plugin \(label.plugin)"
                : card?.web.bridge?.failure.map { "\($0.title): \($0.text)" }
        } else {
            json["kind"] = pane.agent == nil ? "terminal" : "agent"
            json["arg"] = pane.cwd ?? ""
            json["dirty"] = false
            if let agent = pane.agent {
                json["agent"] = agent
                let chat = store.chat(pane)
                json["chat"] = chat?.showsChat == true
                json["view"] = chat.map { $0.showsChat ? "chat" : "tui" }
            }
        }
        return AgentOutput(json)
    }

    static let shown = AgentCommand(
        name: "shown", usage: "shown", summary: "The panes of this session that this Ovvi shows now",
        help: "shown: in a tab in view; floating: in windows of their own; windows: the windows that show it.",
    ) { call in
        try call.done()
        let store = call.store, floating = store.floatingPanes
        return AgentOutput([
            "shown": store.inView.subtracting(floating).sorted(),
            "floating": floating.sorted(),
            "windows": store.windows.count(where: { $0.visible && $0.current?.store === store }),
        ])
    }
}

extension AgentCall {
    /// The asking pane as the user knows it, for a notice or a prompt: its agent's name ("Claude Code"), else its
    /// program's ("zsh"), else its card's title.
    var agent: String {
        store.pane(pane).map { $0.agentLabel ?? $0.programName ?? $0.cardTitle } ?? pane
    }

    /// A pane argument's store and pane, in a session that Ovvi shows.
    func found(_ target: PaneTarget) throws -> (HostStore, HostStore.Pane) {
        guard let store = target.store else {
            throw AgentError(code: "failed", message: "Ovvi does not show herdr session \(target.session)")
        }
        guard let pane = store.pane(target.id) else {
            throw AgentError.paneNotFound(target.id, in: target.session)
        }
        return (store, pane)
    }

    /// `open`'s answer; a card out of view gets the notice, with Show.
    func opened(_ id: String, _ label: PaneLabel, in store: HostStore, reused: Bool) -> AgentOutput {
        let shown = store.inView.contains(id)
        if !shown, let pane = store.pane(id) {
            let kind = label.manifest?.name ?? label.plugin, title = store.title(pane)
            store.notice(reused ? "\(agent) points to \(title)"
                : "\(agent) opened \(kind)\(title == kind ? "" : " \(title)")", show: pane)
        }
        return AgentOutput(["pane": id, "kind": label.manifest?.id ?? label.plugin, "arg": label.place,
                            "label": label.text, "reused": reused, "shown": shown])
    }

    /// `--replace`: the card's label names the new kind and argument with its iid, so the card shows it as a label
    /// from elsewhere (a browser as a new page of its history). Never over a terminal or unsaved edits.
    func replace(_ target: PaneTarget, _ plugin: PluginManifest, _ arg: String) async throws -> AgentOutput {
        let (store, pane) = try found(target)
        guard let old = pane.plugin else {
            throw AgentError(code: "bad_argument", message: "pane \(pane.id) is no browser or plugin card")
        }
        if pane.card?.dirty == true {
            throw AgentError(code: "dirty", message: "pane \(pane.id) has unsaved edits")
        }
        let label = PaneLabel(plugin: plugin.id, iid: old.iid, arg: arg)
        guard PaneLabel(label.text) != nil else { throw AgentError.noLabel(arg) }
        // A browser card made later loads its saved address before its label's, as after a typed one.
        if old.plugin == Registry.browser.id {
            await store.machine.exec().remove(home: old.statePath(session: store.session))
        }
        try await store.request { try await $0.rename(pane: pane.id, label: label.text) }
        try await settle { store.pane(pane.id)?.label == label.text }
        return opened(pane.id, label, in: store, reused: false)
    }

    /// The kind and the label's argument of `open`'s words (agent-control/cli, Kind or path).
    func opening(_ first: String, _ words: [String]) async throws -> (PluginManifest, String) {
        if let plugin = Registry.plugin(first) {
            return try await (plugin, arg(plugin, words))
        }
        if let problem = Registry.problem(first) {
            throw AgentError(code: "plugin_not_found", message: problem)
        }
        guard words.isEmpty else {
            throw AgentError(code: "plugin_not_found", message: "no plugin \(first); `ovvi plugins` lists them")
        }
        if first.lowercased().hasPrefix("file://") {
            return try await (Registry.browser, arg(Registry.browser, [first]))
        }
        if web(first) {
            let plugin = Registry.openers(for: first).first ?? Registry.browser
            return try await (plugin, arg(plugin, [first]))
        }
        let path = absolute(first), folder = try await isFolder(path)
        guard let plugin = Registry.openers(for: folder ? path + "/" : path).first else {
            throw AgentError(code: "bad_argument", message: "no plugin opens \(first)")
        }
        return try await (plugin, arg(plugin, path: path, folder: folder, source: nil))
    }

    /// A kind's argument from its words: a URL, or a path and for Git its source; none for a kind that opens nothing.
    private func arg(_ plugin: PluginManifest, _ words: [String]) async throws -> String {
        let opens = plugin.opens, takes = !opens.files.isEmpty || opens.folders || opens.git
        guard let first = words.first else {
            guard !takes, opens.urls.isEmpty else {
                throw AgentError(code: "bad_argument", message: "\(plugin.id) needs a \(takes ? "path" : "URL")")
            }
            return ""
        }
        guard words.count <= (opens.git ? 2 : 1) else {
            throw AgentError.usage("extra argument \(words[opens.git ? 2 : 1])")
        }
        if !opens.urls.isEmpty, !takes || web(first) {
            // A path is a file URL, and a file URL names a Mac file: for a pane on This Mac only, whatever the kind.
            let path = !first.contains("://") && ["/", "."].contains(first.prefix(1))
            let mac = store.machine.isRemote && (path || first.lowercased().hasPrefix("file:"))
            let url = mac ? nil : plugin.id == Registry.browser.id
                ? Browser.url(path ? fileURL(first) : first, local: true)?.absoluteString
                : plugin.opens(url: first) ? first : nil
            guard let url else {
                throw AgentError(code: "bad_argument", message: mac ? "\(plugin.id) opens a file on This Mac only"
                    : "\(plugin.id) does not open \(first)")
            }
            return url
        }
        let path = absolute(first)
        return try await arg(plugin, path: path, folder: isFolder(path), source: words.dropFirst().first)
    }

    /// A folder's or a file's argument: a repository's root (`/repo/`, then a Git source), a folder as Open File
    /// Explorer Here takes it, or the file.
    private func arg(_ plugin: PluginManifest, path: String, folder: Bool, source: String?) async throws -> String {
        let name = (path as NSString).lastPathComponent
        if plugin.opens.git {
            guard folder, await store.gitRuns(), let root = await Git.root(path, exec: store.machine.exec()) else {
                throw AgentError(code: "bad_argument", message: "\(path) is no folder of a git repository")
            }
            guard let source else { return root + "/" }
            guard source == "uncommitted" || (4 ... 40).contains(source.count) && source
                .allSatisfy({ $0.isASCII && $0.isHexDigit })
            else {
                throw AgentError(code: "bad_argument", message: "\(source) is not uncommitted or a commit hash")
            }
            return "\(root)/ \(source)"
        }
        if let source {
            throw AgentError.usage("extra argument \(source)")
        }
        if folder {
            guard plugin.opens.folders else {
                throw AgentError(code: "bad_argument", message: "\(plugin.id) does not open folders")
            }
            return await store.arg(plugin, in: path)
        }
        guard plugin.rank(file: path) != nil else {
            throw AgentError(code: "bad_argument", message: "\(plugin.id) does not open \(name)")
        }
        return path
    }

    private func web(_ text: String) -> Bool {
        ["http", "https"].contains(URL(string: text)?.scheme?.lowercased() ?? "")
    }

    /// A path's file URL; its `?query` and `#fragment` stay the URL's (`./page.html?v=3`).
    private func fileURL(_ path: String) -> String {
        let end = path.firstIndex { "?#".contains($0) } ?? path.endIndex
        return URL(filePath: absolute(String(path[..<end]))).absoluteString + path[end...]
    }

    /// A path from the request's working folder, without `.` and `..`.
    func absolute(_ path: String) -> String {
        URL(filePath: path, relativeTo: URL(filePath: cwd, directoryHint: .isDirectory)).standardized.path
    }

    /// Whether the path is a folder, on the asking pane's machine; a missing one is `bad_argument`.
    private func isFolder(_ path: String) async throws -> Bool {
        let exec = await store.machine.exec()
        async let exists = exec.succeeds(#"[ -e "$1" ]"#, [path]), folder = exec.succeeds(#"[ -d "$1" ]"#, [path])
        guard await exists else { throw AgentError(code: "bad_argument", message: "no file or folder \(path)") }
        return await folder
    }
}

extension HostStore {
    /// Its panes that float in a window of their own, over a visible window.
    var floatingPanes: Set<String> {
        Set(windows.filter(\.visible).flatMap(\.withFloats).filter { $0.store === self }
            .flatMap { page in panes.filter(page.floats).map(\.id) })
    }

    /// How long an agent's notice and flash last when a test holds them (`-agentHoldSeconds`), so that a slow query
    /// still finds them.
    private static let held = UserDefaults.standard.string(forKey: "agentHoldSeconds").flatMap(Double.init)
        .map { Duration.seconds($0) }
    private static var flashes = 0

    /// An agent's notice in each window that shows the session, in the information tone, with Show.
    func notice(_ text: String, show pane: Pane) {
        Task { await show(Notice(text: text, tone: .info, show: pane.terminalID), for: Self.held ?? .seconds(4)) }
    }

    /// The card's border flashes in the accent color once (`reveal`); a second reveal starts it again.
    func flash(_ pane: String) {
        flashing = pane
        Self.flashes += 1
        let flash = Self.flashes
        Task {
            try? await Task.sleep(for: Self.held ?? .milliseconds(600))
            if Self.flashes == flash {
                flashing = nil
            }
        }
    }

    /// A pane's title in a notice or an answer: a card's as its window shows it (a browser's page title), an agent's,
    /// else the terminal's.
    func title(_ pane: Pane) -> String {
        WindowPages.windows.lazy.flatMap(\.withFloats).first { $0.store === self }?.kindTitle(pane)?.detail
            ?? pane.plugin?.title ?? pane.cardTitle
    }
}

extension HostStore.Pane {
    /// Its plugin card, in the first window that made one.
    var card: Plugin? {
        terminalID.flatMap { id in WindowPages.windows.lazy.compactMap { $0.terminals.plugins[id] }.first }
    }
}

/// `ovvi reveal`: the card's border lights in the accent color once.
struct CardFlash: View {
    let store: HostStore
    let id: String

    var body: some View {
        ZStack {
            if store.flashing == id {
                CardSurface.shape.strokeBorder(Color.accentColor, lineWidth: 2).transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityElement().accessibilityLabel("Revealed").accessibilityIdentifier("pane.\(id).flash")
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.flashing == id)
    }
}

extension AgentError {
    /// A control character or over 1024 characters.
    static func noLabel(_ arg: String) -> AgentError {
        AgentError(code: "bad_argument", message: "\(arg) makes no label: a control character, or over 1024 characters")
    }
}
