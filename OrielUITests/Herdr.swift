import XCTest

/// The tests' herdr side: calls through the e2e helper, ids from its replies, cleanups after a test.
extension OrielUITests {
    func read(_ pane: String) async throws -> String {
        let read = try await Self.call(one, "pane.read", ["pane_id": pane, "source": "visible"])["read"]
        return try field((read as? [String: Any])?["text"], "pane.read's text")
    }

    /// herdr's `pane.get` of the pane.
    func pane(_ id: String, in session: String? = nil) async throws -> [String: Any] {
        try await field(Self.call(session ?? one, "pane.get", ["pane_id": id])["pane"], "pane \(id)")
    }

    func terminalID(_ pane: String, in session: String? = nil) async throws -> String {
        try await field(self.pane(pane, in: session)["terminal_id"], "\(pane)'s terminal")
    }

    func send(_ text: String, to pane: String) async throws {
        try await Self.call(one, "pane.send_text", ["pane_id": pane, "text": text])
    }

    /// The helper or herdr said no, or a reply lacks a field. Thrown, not recorded: teardowns try? it.
    struct Failed: Error, CustomStringConvertible {
        let description: String
    }

    /// The value as `T`, or Failed naming it.
    func field<T>(_ value: Any?, _ what: String) throws -> T {
        guard let value = value as? T else { throw Failed(description: "no \(what)") }
        return value
    }

    /// The id of what herdr made, from its reply: `id(created, "tab")` is `tab.tab_id`, `"root_pane"` gives `pane_id`.
    func id(_ reply: [String: Any], _ key: String) throws -> String {
        let name = key.split(separator: "_").last ?? ""
        return try field((reply[key] as? [String: Any])?["\(name)_id"], "\(key) id")
    }

    /// After the test, closes the tab or workspace of session one, unless the test did.
    func closeAfter(_ kind: String, _ id: String) {
        addTeardownBlock { [one] in _ = try? await Self.call(one, "\(kind).close", ["\(kind)_id": id]) }
    }

    /// After the test, closes every tab or workspace of session one that is not in `before`.
    func closeNew(_ kind: String, besides before: [String]) {
        addTeardownBlock { [one] in
            for id in try await Self.ids(kind, in: one) where !before.contains(id) {
                _ = try? await Self.call(one, "\(kind).close", ["\(kind)_id": id])
            }
        }
    }

    /// herdr's ids are `w<n>:t<m>`.
    func workspace(of tab: String) -> String {
        String(tab.prefix { $0 != ":" })
    }

    /// Splits the pane to the right in herdr; the new pane's id.
    @discardableResult
    func split(_ pane: String) async throws -> String {
        try await id(Self.call(one, "pane.split", ["target_pane_id": pane, "direction": "right", "cwd": "/tmp",
                                                   "focus": false]), "pane")
    }

    /// A workspace of its own, closed after the test: its tab's id and its pane's.
    func createWorkspace(_ label: String, cwd: String = "/tmp") async throws -> (tab: String, pane: String) {
        let created = try await Self.call(one, "workspace.create", ["label": label, "cwd": cwd, "focus": false])
        try closeAfter("workspace", id(created, "workspace"))
        return try (id(created, "tab"), id(created, "root_pane"))
    }

    /// The names of the pane's foreground processes.
    func foreground(_ pane: String) async throws -> [String] {
        let info = try await Self.call(one, "pane.process_info", ["pane_id": pane])["process_info"]
        let processes = (info as? [String: Any])?["foreground_processes"] as? [[String: Any]] ?? []
        return processes.compactMap { $0["name"] as? String }
    }

    /// Session one's `session.snapshot`.
    func snapshot() async throws -> [String: Any] {
        try await Self.snapshot(one)
    }

    @discardableResult
    nonisolated static func snapshot(_ session: String) async throws -> [String: Any] {
        let snapshot = try await call(session, "session.snapshot", [:])["snapshot"]
        guard let snapshot = snapshot as? [String: Any] else { throw Failed(description: "no snapshot of \(session)") }
        return snapshot
    }

    /// Waits until the session answers; `start` starts its server first when it does not, and gives it a workspace.
    /// Its snapshot.
    @discardableResult
    func running(_ session: String, start: Bool = true) async throws -> [String: Any] {
        if start, await (try? Self.snapshot(session)) == nil {
            try await Self.post("\(session)/start")
        }
        let snapshot = try await poll("\(session) to answer") { try? await Self.snapshot(session) }
        guard start, (snapshot["workspaces"] as? [Any] ?? []).isEmpty else { return snapshot }
        try await Self.call(session, "workspace.create", ["label": "five", "cwd": "/tmp", "focus": false])
        return try await Self.snapshot(session)
    }

    /// The session's first workspace and the pane of its active tab, which its page shows first. Tests close and make
    /// five's workspaces, so its ids change from run to run.
    func shown(_ snapshot: [String: Any]) throws -> (workspace: String, pane: String) {
        let workspace: [String: Any] = try field((snapshot["workspaces"] as? [[String: Any]])?.first, "workspace")
        let tab: String = try field(workspace["active_tab_id"], "active tab")
        let panes = snapshot["panes"] as? [[String: Any]] ?? []
        return try (field(workspace["workspace_id"], "workspace id"),
                    field(panes.first { $0["tab_id"] as? String == tab }?["pane_id"], "pane of \(tab)"))
    }

    func tabIDs() async throws -> [String] {
        try await Self.ids("tab", in: one)
    }

    /// The session's `tab` or `workspace` ids. Off the main actor for async teardown blocks: after a failure, one on
    /// the main actor waits for it until the 2-minute allowance runs out.
    nonisolated static func ids(_ kind: String, in session: String) async throws -> [String] {
        try await (snapshot(session)[kind + "s"] as? [[String: Any]] ?? []).compactMap { $0[kind + "_id"] as? String }
    }

    /// The tab herdr has now and did not have `before`.
    func newTabID(after before: [String]) async throws -> String {
        try await poll("a new tab in herdr") { () async throws -> String? in
            try await tabIDs().first { !before.contains($0) }
        }
    }

    /// The session's herdr runs (`terminal session` and `remote-api-bridge`), any client's, as `pid argv` lines.
    func runs(_ session: String) async throws -> [String] {
        try await String(decoding: Self.post("\(session)/children"), as: UTF8.self).split(separator: "\n")
            .map(String.init)
    }

    /// The session's `terminal session` runs.
    func streams(_ session: String) async throws -> [String] {
        try await runs(session).filter { $0.contains("terminal session") }
    }

    /// One herdr API call on a throwaway session, through the helper.
    @discardableResult
    nonisolated static func call(_ session: String, _ method: String,
                                 _ params: [String: Any]) async throws -> [String: Any]
    {
        let body = try JSONSerialization.data(withJSONObject: ["id": "1", "method": method, "params": params])
        let data = try await post(session, body + Data("\n".utf8))
        let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = reply?["result"] as? [String: Any] else {
            throw Failed(description: "\(method): \(String(decoding: data, as: UTF8.self))")
        }
        return result
    }

    /// One POST to the e2e helper: `<session>` for an API call, `<session>/<action>` for the others (see the helper).
    /// Throws unless it answers 200.
    @discardableResult
    nonisolated static func post(_ path: String, _ body: Data = Data()) async throws -> Data {
        let helper = ProcessInfo.processInfo.environment["ORIEL_HELPER"] ?? "run through make e2e"
        guard let url = URL(string: "\(helper)/\(path)") else { throw Failed(description: "no URL \(helper)") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failed(description: "\(path): \(String(decoding: data, as: UTF8.self))")
        }
        return data
    }
}
